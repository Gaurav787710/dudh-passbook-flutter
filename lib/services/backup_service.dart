import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../database/database_helper.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';
import '../models/advance.dart';
import '../models/rate_chart.dart';

/// Backup Service for Dudh Passbook
/// Handles database backup and restore functionality
class BackupService {
  static final BackupService instance = BackupService._init();
  BackupService._init();

  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Export all data to JSON file and share it
  Future<Map<String, dynamic>> exportBackup({required int dairyId}) async {
    try {
      // Collect all data from database
      final farmers = await _db.getAllFarmers(dairyId: dairyId, activeOnly: false);
      final milkEntries = await _db.getMilkEntries(dairyId: dairyId);
      final payments = await _db.getPayments(dairyId: dairyId);
      final advances = await _db.getAdvances(dairyId: dairyId);
      final rateCharts = await _db.getRateCharts();
      final users = await _db.getAllUsers(dairyId: dairyId);

      // Create backup data structure - convert objects to maps
      final backupData = {
        'version': 1,
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

      // Convert to JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'dudhpassbook_backup_$timestamp.json';
      final file = File('${tempDir.path}/$fileName');

      // Write to file
      await file.writeAsString(jsonString);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Dudh Passbook Backup',
        text: 'Dudh Passbook database backup created on ${DateTime.now().toString().split('.')[0]}',
      );

      return {
        'success': true,
        'message': 'Backup created successfully',
        'counts': backupData['counts'],
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to create backup: $e',
      };
    }
  }

  /// Import data from JSON backup file
  Future<Map<String, dynamic>> importBackup({required int dairyId}) async {
    try {
      // Pick JSON file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        return {
          'success': false,
          'error': 'No file selected',
        };
      }

      // Read file
      final filePath = result.files.single.path;
      if (filePath == null) {
        return {
          'success': false,
          'error': 'Could not access selected file',
        };
      }
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // Parse JSON
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate backup structure
      if (!backupData.containsKey('version') || !backupData.containsKey('data')) {
        return {
          'success': false,
          'error': 'Invalid backup file format',
        };
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
      // Dedup: syncId (primary) or farmerCode+dateTime+shift (fallback)
      if (data.containsKey('milkEntries')) {
        final entries = data['milkEntries'] as List;
        final existingEntries = await _db.getMilkEntries(dairyId: dairyId);
        final existingKeys = <String>{};
        for (final e in existingEntries) {
          existingKeys.add('${e.farmerCode}_${e.dateTime.toIso8601String()}_${e.shift}');
        }
        final existingSyncIds = <String>{};
        for (final e in existingEntries) {
          existingSyncIds.add(e.syncId);
        }
        
        for (var entryMap in entries) {
          try {
            final map = Map<String, dynamic>.from(entryMap as Map);
            map['dairyId'] = dairyId;
            map['farmerId'] = remapFarmerId(map['farmerId']);
            map.remove('id');

            // Check syncId first
            final syncId = map['syncId'] as String?;
            if (syncId != null && existingSyncIds.contains(syncId)) {
              skippedDuplicates++;
              continue;
            }

            // Fallback: farmerCode + dateTime + shift
            final dateStr = (map['dateTime'] ?? '').toString();
            final farmerCode = (map['farmerCode'] ?? '').toString();
            final shift = (map['shift'] ?? '').toString();
            final key = '${farmerCode}_${dateStr}_$shift';
            
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
      // Dedup: syncId (primary), or farmerCode+paymentDate+type+amount (fallback)
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
            map.remove('id');

            // Check syncId first
            final syncId = map['syncId'] as String?;
            if (syncId != null && existingSyncIds.contains(syncId)) {
              skippedDuplicates++;
              continue;
            }

            // Fallback: farmerCode + paymentDate + type + netAmount
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
      // Dedup: farmerCode + date + amount
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
        'message': 'Backup restored successfully',
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
      return {
        'success': false,
        'error': 'Failed to restore backup: $e',
      };
    }
  }
}
