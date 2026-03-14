import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';
import '../models/advance.dart';
import '../models/rate_chart.dart';

/// Google Drive Backup Service for Dudh Passbook
/// Handles automatic and manual backup to Google Drive
class GoogleDriveBackupService {
  static final GoogleDriveBackupService instance = GoogleDriveBackupService._init();
  GoogleDriveBackupService._init();

  final DatabaseHelper _db = DatabaseHelper.instance;

  static const String _backupFileName = 'dudhpassbook_backup.json';

  // Reuse one GoogleSignIn instance to avoid scope re-request loops
  // NOTE: driveAppdataScope STILL requires enabling Google Drive API in Cloud Console
  // at: https://console.developers.google.com/apis/api/drive.googleapis.com
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      drive.DriveApi.driveAppdataScope,
    ],
  );

  /// Get authenticated Drive API client
  Future<drive.DriveApi?> _getDriveApi() async {
    try {
      // Try silent sign-in first
      var account = await _googleSignIn.signInSilently();
      if (account == null) {
        // Request interactive sign-in with Drive scope consent
        account = await _googleSignIn.signIn();
      }

      if (account == null) {
        return null;
      }

      // Check if scopes are granted – re-request if not
      if (!await _googleSignIn.requestScopes([drive.DriveApi.driveAppdataScope])) {
        return null;
      }

      final httpClient = await _googleSignIn.authenticatedClient();
      if (httpClient == null) {
        return null;
      }

      return drive.DriveApi(httpClient);
    } catch (e) {
      return null;
    }
  }

  /// Export backup data to Google Drive (uses appDataFolder — no Drive API needed)
  Future<Map<String, dynamic>> backupToDrive({required int dairyId}) async {
    try {
      // Get Drive API
      final driveApi = await _getDriveApi();
      if (driveApi == null) {
        return {'success': false, 'error': 'Google Drive authentication failed. Please sign in with Google first.'};
      }

      // Collect all data from database
      final farmers = await _db.getAllFarmers(dairyId: dairyId, activeOnly: false);
      final milkEntries = await _db.getMilkEntries(dairyId: dairyId);
      final payments = await _db.getPayments(dairyId: dairyId);
      final advances = await _db.getAdvances(dairyId: dairyId);
      final rateCharts = await _db.getRateCharts();
      final users = await _db.getAllUsers(dairyId: dairyId);

      // Create backup data structure
      final backupData = {
        'version': 2,
        'createdAt': DateTime.now().toIso8601String(),
        'dairyId': dairyId,
        'data': {
          'farmers': farmers.map((f) => f.toMap()).toList(),
          'milkEntries': milkEntries.map((e) => e.toMap()).toList(),
          'payments': payments.map((p) => p.toMap()).toList(),
          'advances': advances.map((a) => a.toMap()).toList(),
          'rateCharts': rateCharts.map((r) => r.toMap()).toList(),
          'users': users.where((u) => u['role'] == 'staff').toList(),
        },
        'counts': {
          'farmers': farmers.length,
          'milkEntries': milkEntries.length,
          'payments': payments.length,
          'advances': advances.length,
          'rateCharts': rateCharts.length,
          'staff': users.where((u) => u['role'] == 'staff').length,
        }
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);

      // Check if existing backup file exists and update it, or create new
      final existingFiles = await driveApi.files.list(
        q: "name = '$_backupFileName' and trashed = false",
        spaces: 'appDataFolder',
        $fields: 'files(id, name)',
      );

      String? fileId;
      if (existingFiles.files != null && existingFiles.files!.isNotEmpty) {
        // Update existing file
        fileId = existingFiles.files!.first.id;
        await driveApi.files.update(
          drive.File()..name = _backupFileName,
          fileId!,
          uploadMedia: drive.Media(
            Stream.value(jsonBytes),
            jsonBytes.length,
            contentType: 'application/json',
          ),
        );
      } else {
        // Create new file
        final fileMetadata = drive.File()
          ..name = _backupFileName
          ..parents = ['appDataFolder']
          ..mimeType = 'application/json';

        final result = await driveApi.files.create(
          fileMetadata,
          uploadMedia: drive.Media(
            Stream.value(jsonBytes),
            jsonBytes.length,
            contentType: 'application/json',
          ),
        );
        fileId = result.id;
      }

      // Also save a timestamped copy for history
      final historyFileName = 'backup_${DateTime.now().toIso8601String().split('T')[0]}.json';

      // Check if today's backup already exists
      final todayFiles = await driveApi.files.list(
        q: "name = '$historyFileName' and trashed = false",
        spaces: 'appDataFolder',
        $fields: 'files(id, name)',
      );

      if (todayFiles.files == null || todayFiles.files!.isEmpty) {
        final historyMetadata = drive.File()
          ..name = historyFileName
          ..parents = ['appDataFolder']
          ..mimeType = 'application/json';

        await driveApi.files.create(
          historyMetadata,
          uploadMedia: drive.Media(
            Stream.value(jsonBytes),
            jsonBytes.length,
            contentType: 'application/json',
          ),
        );
      }

      // Save last backup date
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastDriveBackupDate', DateTime.now().toIso8601String());

      return {
        'success': true,
        'message': 'Backup saved to Google Drive successfully!',
        'counts': backupData['counts'],
        'fileId': fileId,
      };
    } catch (e) {
      String errorMsg = e.toString();
      // Provide actionable message for common Drive API errors
      if (errorMsg.contains('403') && errorMsg.contains('Drive API')) {
        errorMsg = 'Google Drive API is not enabled for your project. '
            'Go to https://console.developers.google.com/apis/api/drive.googleapis.com '
            'and enable it for the correct project. '
            'Make sure you select the same project linked to your Firebase app.';
      }
      return {
        'success': false,
        'error': errorMsg,
      };
    }
  }

  /// Restore backup from Google Drive
  Future<Map<String, dynamic>> restoreFromDrive({required int dairyId}) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) {
        return {'success': false, 'error': 'Google Drive authentication failed'};
      }

      // Find the main backup file in appDataFolder
      final fileList = await driveApi.files.list(
        q: "name = '$_backupFileName' and trashed = false",
        spaces: 'appDataFolder',
        $fields: 'files(id, name, modifiedTime)',
        orderBy: 'modifiedTime desc',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return {'success': false, 'error': 'No backup file found in Drive'};
      }

      final fileId = fileList.files!.first.id!;

      // Download the file
      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataBytes = [];
      await for (var chunk in response.stream) {
        dataBytes.addAll(chunk);
      }

      final jsonString = utf8.decode(dataBytes);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate backup structure
      if (!backupData.containsKey('data')) {
        return {'success': false, 'error': 'Invalid backup file format'};
      }

      final data = backupData['data'] as Map<String, dynamic>;
      int restoredFarmers = 0;
      int restoredEntries = 0;
      int restoredPayments = 0;
      int restoredAdvances = 0;
      int restoredRateCharts = 0;
      int skippedDuplicates = 0;

      // ---- STEP 1: Restore farmers & build OLD-ID → NEW-ID mapping ----
      // farmerCode is stable across backup/restore; farmerId (auto-increment) is NOT.
      // We map backup farmerId → local farmerId so entries/payments point to correct farmer.
      final farmerIdMap = <int, int>{}; // backup farmerId → local farmerId
      final existingFarmers = await _db.getAllFarmers(dairyId: dairyId, activeOnly: false);

      if (data.containsKey('farmers')) {
        final farmers = data['farmers'] as List;
        for (var farmerMap in farmers) {
          try {
            final map = Map<String, dynamic>.from(farmerMap as Map);
            final backupId = (map['id'] as num?)?.toInt();
            final code = map['code'] ?? '';

            // Check if farmer already exists by code
            final existing = existingFarmers.where((f) => f.code == code).toList();
            if (existing.isNotEmpty) {
              // Farmer exists — record mapping, don't re-insert
              if (backupId != null) {
                farmerIdMap[backupId] = existing.first.id!;
              }
              skippedDuplicates++;
            } else {
              // New farmer — insert with fresh id
              map.remove('id'); // let DB auto-generate
              map['dairyId'] = dairyId;
              final farmer = Farmer.fromMap(map);
              final newId = await _db.insertFarmer(farmer);
              if (backupId != null) {
                farmerIdMap[backupId] = newId;
              }
              // Add to existingFarmers so subsequent lookups work
              farmer.id = newId;
              existingFarmers.add(farmer);
              restoredFarmers++;
            }
          } catch (e) {
            skippedDuplicates++;
          }
        }
      }

      // Helper to remap farmerId from backup to local
      int remapFarmerId(dynamic backupFarmerId) {
        final bid = (backupFarmerId is num) ? backupFarmerId.toInt() : 0;
        return farmerIdMap[bid] ?? bid;
      }

      // ---- STEP 2: Restore milk entries ----
      // Dedup key: farmerCode + dateTime + shift + cattleType (stable across restores)
      if (data.containsKey('milkEntries')) {
        final entries = data['milkEntries'] as List;
        final existingEntries = await _db.getMilkEntries(dairyId: dairyId);
        final existingKeys = <String>{};
        for (final e in existingEntries) {
          existingKeys.add('${e.farmerCode}_${e.dateTime.toIso8601String()}_${e.shift}_${e.cattleType}');
        }
        // Also track syncIds to avoid re-inserting
        final existingSyncIds = <String>{};
        for (final e in existingEntries) {
          existingSyncIds.add(e.syncId);
        }

        for (var entryMap in entries) {
          try {
            final map = Map<String, dynamic>.from(entryMap as Map);
            map['dairyId'] = dairyId;
            map['farmerId'] = remapFarmerId(map['farmerId']);
            map.remove('id'); // let DB auto-generate

            // Check syncId first (most reliable)
            final syncId = map['syncId'] as String?;
            if (syncId != null && existingSyncIds.contains(syncId)) {
              skippedDuplicates++;
              continue;
            }

            // Fallback: farmerCode + dateTime + shift + cattleType
            final dateStr = (map['dateTime'] ?? '').toString();
            final farmerCode = (map['farmerCode'] ?? '').toString();
            final shift = (map['shift'] ?? '').toString();
            final cattleType = (map['cattleType'] ?? 'cow').toString();
            final key = '${farmerCode}_${dateStr}_${shift}_$cattleType';

            if (!existingKeys.contains(key)) {
              final entry = MilkEntry.fromMap(map);
              await _db.insertMilkEntry(entry);
              existingKeys.add(key);
              if (syncId != null) existingSyncIds.add(syncId);
              restoredEntries++;
            } else {
              skippedDuplicates++;
            }
          } catch (e) {
            skippedDuplicates++;
          }
        }
      }

      // ---- STEP 3: Restore payments ----
      // Dedup key: syncId (primary), or farmerCode+date+type+amount (fallback)
      // Old key used farmerId+fromDate+toDate which fails for advances (null dates)
      if (data.containsKey('payments')) {
        final payments = data['payments'] as List;
        final existingPayments = await _db.getPayments(dairyId: dairyId);
        final existingSyncIds = <String>{};
        final existingKeys = <String>{};
        for (final p in existingPayments) {
          existingSyncIds.add(p.syncId);
          final amt = p.netAmount.toStringAsFixed(2);
          existingKeys.add('${p.farmerCode}_${p.paymentDate.toIso8601String()}_${p.type}_$amt');
        }

        for (var paymentMap in payments) {
          try {
            final map = Map<String, dynamic>.from(paymentMap as Map);
            map['dairyId'] = dairyId;
            map['farmerId'] = remapFarmerId(map['farmerId']);
            map.remove('id'); // let DB auto-generate

            // Check syncId first
            final syncId = map['syncId'] as String?;
            if (syncId != null && existingSyncIds.contains(syncId)) {
              skippedDuplicates++;
              continue;
            }

            // Fallback: farmerCode + paymentDate + type + amount
            final fc = (map['farmerCode'] ?? '').toString();
            final pd = (map['paymentDate'] ?? '').toString();
            final tp = (map['type'] ?? 'PAYMENT').toString();
            final na = (map['netAmount'] is num) ? (map['netAmount'] as num).toStringAsFixed(2) : '0.00';
            final key = '${fc}_${pd}_${tp}_$na';

            if (!existingKeys.contains(key)) {
              final payment = Payment.fromMap(map);
              await _db.insertPayment(payment);
              existingKeys.add(key);
              if (syncId != null) existingSyncIds.add(syncId);
              restoredPayments++;
            } else {
              skippedDuplicates++;
            }
          } catch (e) {
            skippedDuplicates++;
          }
        }
      }

      // ---- STEP 4: Restore advances ----
      // Dedup: farmerCode + date + amount (each advance is unique by these)
      if (data.containsKey('advances')) {
        final advances = data['advances'] as List;
        final existingAdvances = await _db.getAdvances(dairyId: dairyId);
        final existingKeys = <String>{};
        for (final a in existingAdvances) {
          existingKeys.add('${a.farmerCode}_${a.date.toIso8601String()}_${a.amount.toStringAsFixed(2)}');
        }

        for (var advanceMap in advances) {
          try {
            final map = Map<String, dynamic>.from(advanceMap as Map);
            map['dairyId'] = dairyId;
            map['farmerId'] = remapFarmerId(map['farmerId']);
            map.remove('id');

            final fc = (map['farmerCode'] ?? '').toString();
            final dt = (map['date'] ?? '').toString();
            final amt = (map['amount'] is num) ? (map['amount'] as num).toStringAsFixed(2) : '0.00';
            final key = '${fc}_${dt}_$amt';

            if (!existingKeys.contains(key)) {
              final advance = Advance.fromMap(map);
              await _db.insertAdvance(advance);
              existingKeys.add(key);
              restoredAdvances++;
            } else {
              skippedDuplicates++;
            }
          } catch (e) {
            skippedDuplicates++;
          }
        }
      }

      // ---- STEP 5: Restore rate charts ----
      if (data.containsKey('rateCharts')) {
        final charts = data['rateCharts'] as List;
        final existingCharts = await _db.getRateCharts();
        final existingKeys = <String>{};
        for (final r in existingCharts) {
          existingKeys.add('${r.cattleType}_${r.fatMin}_${r.fatMax}_${r.snfMin}_${r.snfMax}');
        }

        for (var chartMap in charts) {
          try {
            final map = Map<String, dynamic>.from(chartMap as Map);
            map['dairyId'] = dairyId;
            map.remove('id');
            final key = '${map['cattleType']}_${map['fatMin']}_${map['fatMax']}_${map['snfMin']}_${map['snfMax']}';

            if (!existingKeys.contains(key)) {
              final chart = RateChart.fromMap(map);
              await _db.insertRateChart(chart);
              existingKeys.add(key);
              restoredRateCharts++;
            } else {
              skippedDuplicates++;
            }
          } catch (e) {
            skippedDuplicates++;
          }
        }
      }

      return {
        'success': true,
        'message': 'Backup restored from Google Drive successfully!',
        'restored': {
          'farmers': restoredFarmers,
          'milkEntries': restoredEntries,
          'payments': restoredPayments,
          'advances': restoredAdvances,
          'rateCharts': restoredRateCharts,
        },
        'skipped': skippedDuplicates,
      };
    } catch (e) {
      return {'success': false, 'error': 'Failed to restore from Drive: $e'};
    }
  }

  /// Perform auto-backup (called by WorkManager)
  static Future<void> performAutoBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dairyId = prefs.getInt('dairyId');
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (!isLoggedIn || dairyId == null) {
        debugPrint('[AutoBackup] Skipped: not logged in or no dairyId');
        return;
      }

      // Dedup: skip if already backed up today
      final lastBackup = prefs.getString('lastAutoBackupDate');
      if (lastBackup != null) {
        final lastDate = DateTime.tryParse(lastBackup);
        if (lastDate != null) {
          final now = DateTime.now();
          if (lastDate.year == now.year &&
              lastDate.month == now.month &&
              lastDate.day == now.day) {
            debugPrint('[AutoBackup] Already backed up today, skipping');
            return;
          }
        }
      }

      final result = await instance.backupToDrive(dairyId: dairyId);
      if (result['success'] == true) {
        await prefs.setString(
            'lastAutoBackupDate', DateTime.now().toIso8601String());
        debugPrint('[AutoBackup] Success');
      } else {
        debugPrint('[AutoBackup] Failed: ${result['error']}');
      }
    } catch (e) {
      debugPrint('[AutoBackup] Error: $e');
    }
  }
}
