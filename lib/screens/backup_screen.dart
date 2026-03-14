import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/backup_service.dart';
import '../services/google_drive_backup_service.dart';
import '../utils/theme_helper.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _isLoading = false;
  String? _lastBackupDate;
  String? _lastDriveBackupDate;
  int? _dairyId;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryBlue => const Color(0xFF1976D2);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dairyId = prefs.getInt('dairyId');
      _lastBackupDate = prefs.getString('lastBackupDate');
      _lastDriveBackupDate = prefs.getString('lastDriveBackupDate');
      _languageCode = prefs.getString('language_code') ?? 'hi';
    });
  }

  /// Backup to Google Drive
  Future<void> _backupToDrive() async {
    if (_isLoading) return;
    if (_dairyId == null) {
      _showSnackBar('Error: Dairy ID not found', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await GoogleDriveBackupService.instance.backupToDrive(dairyId: _dairyId!);

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastDriveBackupDate', DateTime.now().toIso8601String());
        if (mounted) setState(() => _lastDriveBackupDate = DateTime.now().toIso8601String());

        final counts = result['counts'] as Map<String, dynamic>?;
        _showSuccessDialog(
          title: _isHindi ? 'Drive बैकअप सफल!' : 'Drive Backup Done!',
          message: _isHindi ? 'आपका डेटा Google Drive पर सेव हो गया।' : 'Your data has been saved to Google Drive.',
          details: counts != null
            ? 'Farmers: ${counts['farmers']}, Entries: ${counts['milkEntries']}, Payments: ${counts['payments']}'
            : null,
        );
      } else {
        _showSnackBar(result['error'] ?? 'Failed to backup to Drive', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Restore from Google Drive
  Future<void> _restoreFromDrive() async {
    if (_isLoading) return;
    if (_dairyId == null) {
      _showSnackBar('Error: Dairy ID not found', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cloud_download_rounded, color: Colors.orange.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            Text(_isHindi ? 'Drive से रिस्टोर?' : 'Restore from Drive?'),
          ],
        ),
        content: Text(
          _isHindi
              ? 'Google Drive से बैकअप डेटा रिस्टोर होगा। मौजूदा डेटा नहीं मिटेगा।'
              : 'Data will be imported from Google Drive backup. Existing data will not be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
            child: Text(_isHindi ? 'रिस्टोर करें' : 'Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await GoogleDriveBackupService.instance.restoreFromDrive(dairyId: _dairyId!);

      if (result['success'] == true) {
        final restored = result['restored'] as Map<String, dynamic>?;
        final skipped = result['skipped'] ?? 0;
        _showSuccessDialog(
          title: _isHindi ? 'रिस्टोर सफल!' : 'Restore Complete!',
          message: _isHindi ? 'Google Drive से डेटा रिस्टोर हो गया।' : 'Data restored from Google Drive.',
          details: restored != null
            ? 'Restored - Farmers: ${restored['farmers']}, Entries: ${restored['milkEntries']}, Payments: ${restored['payments']}\nSkipped: $skipped'
            : null,
        );
      } else {
        _showSnackBar(result['error'] ?? 'Failed to restore from Drive', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createBackup() async {
    if (_isLoading) return;
    if (_dairyId == null) {
      _showSnackBar('Error: Dairy ID not found', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await BackupService.instance.exportBackup(dairyId: _dairyId!);

      if (result['success'] == true) {
        // Save last backup date
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastBackupDate', DateTime.now().toIso8601String());
        if (mounted) setState(() => _lastBackupDate = DateTime.now().toIso8601String());

        final counts = result['counts'] as Map<String, dynamic>?;
        _showSuccessDialog(
          title: 'Backup Created!',
          message: 'Your data has been exported successfully.',
          details: counts != null
            ? 'Farmers: ${counts['farmers']}, Entries: ${counts['milkEntries']}, Payments: ${counts['payments']}'
            : null,
        );
      } else {
        _showSnackBar(result['error'] ?? 'Failed to create backup', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (_isLoading) return;
    if (_dairyId == null) {
      _showSnackBar('Error: Dairy ID not found', isError: true);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.warning_rounded, color: Colors.orange.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Restore Backup?'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This will import data from a backup file. Existing data will NOT be deleted, but duplicates will be skipped.'),
            SizedBox(height: 12),
            Text(
              'Make sure you select a valid Dudh Passbook backup file.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final result = await BackupService.instance.importBackup(dairyId: _dairyId!);

      if (result['success'] == true) {
        final restored = result['restored'] as Map<String, dynamic>?;
        final skipped = result['skipped'] ?? 0;
        _showSuccessDialog(
          title: 'Backup Restored!',
          message: 'Your data has been imported successfully.',
          details: restored != null
            ? 'Restored - Farmers: ${restored['farmers']}, Entries: ${restored['milkEntries']}, Payments: ${restored['payments']}\nSkipped duplicates: $skipped'
            : null,
        );
      } else {
        _showSnackBar(result['error'] ?? 'Failed to restore backup', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccessDialog({required String title, required String message, String? details}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (details != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(details, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'Never';
    try {
      final date = DateTime.parse(isoDate);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Icon(Icons.arrow_back_rounded, color: textDark, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Backup & Restore',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Google Drive Backup Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [primaryGreen.withOpacity(0.1), primaryBlue.withOpacity(0.1)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: primaryGreen.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_done_rounded, color: primaryGreen, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Google Drive Backup',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _isHindi
                                      ? 'हर रात 12 बजे ऑटो बैकअप होता है'
                                      : 'Auto backup every night at 12 AM',
                                  style: TextStyle(fontSize: 12, color: textLight),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_rounded, size: 18, color: textLight),
                            const SizedBox(width: 8),
                            Text(
                              _isHindi ? 'पिछला Drive बैकअप: ' : 'Last Drive Backup: ',
                              style: TextStyle(fontSize: 12, color: textLight),
                            ),
                            Expanded(
                              child: Text(
                                _formatDate(_lastDriveBackupDate),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Drive Backup Button
                GestureDetector(
                  onTap: _backupToDrive,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.backup_rounded, color: primaryGreen, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi ? 'Drive पर बैकअप करें' : 'Backup to Drive',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isHindi ? 'Google Drive पर डेटा सेव करें' : 'Save data to Google Drive',
                                style: TextStyle(fontSize: 13, color: textLight),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Drive Restore Button
                GestureDetector(
                  onTap: _restoreFromDrive,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.cloud_download_rounded, color: primaryBlue, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi ? 'Drive से रिस्टोर' : 'Restore from Drive',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isHindi ? 'Google Drive से डेटा रिस्टोर करें' : 'Restore data from Google Drive',
                                style: TextStyle(fontSize: 13, color: textLight),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _isHindi ? 'या फ़ाइल से' : 'OR from File',
                        style: TextStyle(fontSize: 12, color: textLight),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 16),

                // Last Local Backup Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.history_rounded, color: Colors.grey.shade600, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isHindi ? 'पिछला फ़ाइल बैकअप' : 'Last File Backup',
                              style: TextStyle(fontSize: 12, color: textLight),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(_lastBackupDate),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Backup Button
                GestureDetector(
                  onTap: _createBackup,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: primaryGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.cloud_upload_rounded, color: primaryGreen, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Create Backup',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isHindi ? 'बैकअप बनाएं और शेयर करें' : 'Export all data to JSON file',
                                style: TextStyle(fontSize: 13, color: textLight),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Restore Button
                GestureDetector(
                  onTap: _restoreBackup,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.cloud_download_rounded, color: primaryBlue, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Restore Backup',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isHindi ? 'बैकअप से डेटा रिस्टोर करें' : 'Import data from JSON file',
                                style: TextStyle(fontSize: 13, color: textLight),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Warning Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded, color: Colors.orange.shade700, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Important',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Keep your backup file safe. Anyone with this file can see your data.',
                              style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
