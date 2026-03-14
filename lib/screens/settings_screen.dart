import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import '../services/firestore_sync_service.dart';
import '../main.dart';
import '../utils/theme_helper.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _language = 'hi';
  bool get _isHindi => _language == 'hi';

  // App Settings
  String _themeMode = 'light'; // light, dark, system
  bool _quickEntryMode = false;
  String _fixedRateEntryBehavior = 'pending'; // 'pending' or 'complete'
  bool _autoCalculateRate = true;
  bool _showFatSnfWarning = true;
  bool _showEntryConfirmation = true;
  String _defaultShift = 'auto'; // auto, morning, evening
  double _minFatWarningBuffalo = 5.0;
  double _maxFatWarningBuffalo = 10.0;
  double _minFatWarningCow = 2.0;
  double _maxFatWarningCow = 6.0;
  bool _soundOnEntry = true;
  bool _printAfterBilling = false;

  // Original values (to detect changes)
  String _origThemeMode = 'light';
  String _origLanguage = 'hi';
  bool _origQuickEntryMode = false;
  String _origFixedRateEntryBehavior = 'pending';
  bool _origAutoCalculateRate = true;
  bool _origShowFatSnfWarning = true;
  bool _origShowEntryConfirmation = true;
  String _origDefaultShift = 'auto';
  double _origMinFatBuffalo = 5.0;
  double _origMaxFatBuffalo = 10.0;
  double _origMinFatCow = 2.0;
  double _origMaxFatCow = 6.0;
  bool _origSoundOnEntry = true;
  bool _origPrintAfterBilling = false;

  // Sync
  bool _isSyncing = false;
  String? _lastSyncTime;

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark => _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get accentBlue => const Color(0xFF1976D2);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);

  bool get _hasUnsavedChanges =>
      _themeMode != _origThemeMode ||
      _language != _origLanguage ||
      _quickEntryMode != _origQuickEntryMode ||
      _fixedRateEntryBehavior != _origFixedRateEntryBehavior ||
      _autoCalculateRate != _origAutoCalculateRate ||
      _showFatSnfWarning != _origShowFatSnfWarning ||
      _showEntryConfirmation != _origShowEntryConfirmation ||
      _defaultShift != _origDefaultShift ||
      _minFatWarningBuffalo != _origMinFatBuffalo ||
      _maxFatWarningBuffalo != _origMaxFatBuffalo ||
      _minFatWarningCow != _origMinFatCow ||
      _maxFatWarningCow != _origMaxFatCow ||
      _soundOnEntry != _origSoundOnEntry ||
      _printAfterBilling != _origPrintAfterBilling;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSyncStatus();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('language_code') ?? 'hi';
      _themeMode = prefs.getString('theme_mode') ?? 'light';
      _quickEntryMode = prefs.getBool('quickEntryMode') ?? false;
      _fixedRateEntryBehavior = prefs.getString('fixedRateEntryBehavior') ?? 'pending';
      _autoCalculateRate = prefs.getBool('autoCalculateRate') ?? true;
      _showFatSnfWarning = prefs.getBool('showFatSnfWarning') ?? true;
      _showEntryConfirmation = prefs.getBool('showEntryConfirmation') ?? true;
      _defaultShift = prefs.getString('defaultShift') ?? 'auto';
      _minFatWarningBuffalo = prefs.getDouble('minFatWarningBuffalo') ?? 5.0;
      _maxFatWarningBuffalo = prefs.getDouble('maxFatWarningBuffalo') ?? 10.0;
      _minFatWarningCow = prefs.getDouble('minFatWarningCow') ?? 2.0;
      _maxFatWarningCow = prefs.getDouble('maxFatWarningCow') ?? 6.0;
      _soundOnEntry = prefs.getBool('soundOnEntry') ?? true;
      _printAfterBilling = prefs.getBool('printAfterBilling') ?? false;

      // Store originals
      _origThemeMode = _themeMode;
      _origLanguage = _language;
      _origQuickEntryMode = _quickEntryMode;
      _origAutoCalculateRate = _autoCalculateRate;
      _origShowFatSnfWarning = _showFatSnfWarning;
      _origShowEntryConfirmation = _showEntryConfirmation;
      _origDefaultShift = _defaultShift;
      _origMinFatBuffalo = _minFatWarningBuffalo;
      _origMaxFatBuffalo = _maxFatWarningBuffalo;
      _origMinFatCow = _minFatWarningCow;
      _origMaxFatCow = _maxFatWarningCow;
      _origSoundOnEntry = _soundOnEntry;
      _origPrintAfterBilling = _printAfterBilling;
    });
  }

  Future<void> _saveAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', _language);
    await prefs.setString('theme_mode', _themeMode);
    await prefs.setBool('quickEntryMode', _quickEntryMode);
    await prefs.setString('fixedRateEntryBehavior', _fixedRateEntryBehavior);
    await prefs.setBool('autoCalculateRate', _autoCalculateRate);
    await prefs.setBool('showFatSnfWarning', _showFatSnfWarning);
    await prefs.setBool('showEntryConfirmation', _showEntryConfirmation);
    await prefs.setString('defaultShift', _defaultShift);
    await prefs.setDouble('minFatWarningBuffalo', _minFatWarningBuffalo);
    await prefs.setDouble('maxFatWarningBuffalo', _maxFatWarningBuffalo);
    await prefs.setDouble('minFatWarningCow', _minFatWarningCow);
    await prefs.setDouble('maxFatWarningCow', _maxFatWarningCow);
    await prefs.setBool('soundOnEntry', _soundOnEntry);
    await prefs.setBool('printAfterBilling', _printAfterBilling);

    // Apply theme
    if (_themeMode != _origThemeMode && mounted) {
      ThemeMode themeMode;
      switch (_themeMode) {
        case 'dark':
          themeMode = ThemeMode.dark;
          break;
        case 'system':
          themeMode = ThemeMode.system;
          break;
        default:
          themeMode = ThemeMode.light;
      }
      DairyMasterProApp.setThemeMode(context, themeMode);
    }

    // Apply locale change
    if (_language != _origLanguage && mounted) {
      DairyMasterProApp.setLocale(context, Locale(_language));
    }

    // Update originals
    if (!mounted) return;
    setState(() {
      _origThemeMode = _themeMode;
      _origLanguage = _language;
      _origQuickEntryMode = _quickEntryMode;
      _origFixedRateEntryBehavior = _fixedRateEntryBehavior;
      _origAutoCalculateRate = _autoCalculateRate;
      _origShowFatSnfWarning = _showFatSnfWarning;
      _origShowEntryConfirmation = _showEntryConfirmation;
      _origDefaultShift = _defaultShift;
      _origMinFatBuffalo = _minFatWarningBuffalo;
      _origMaxFatBuffalo = _maxFatWarningBuffalo;
      _origMinFatCow = _minFatWarningCow;
      _origMaxFatCow = _maxFatWarningCow;
      _origSoundOnEntry = _soundOnEntry;
      _origPrintAfterBilling = _printAfterBilling;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(_isHindi ? 'सेटिंग्स सेव हो गईं!' : 'Settings saved successfully!'),
            ],
          ),
          backgroundColor: primaryGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
            ),
            const SizedBox(width: 12),
            Text(_isHindi ? 'बिना सेव किए वापस?' : 'Unsaved Changes', style: const TextStyle(fontSize: 17)),
          ],
        ),
        content: Text(
          _isHindi
              ? 'आपने कुछ सेटिंग्स बदली हैं जो सेव नहीं हुई हैं। बिना सेव किए वापस जाना चाहते हैं?'
              : 'You have unsaved changes. Do you want to go back without saving?',
          style: TextStyle(color: Colors.grey.shade600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isHindi ? 'रुकें' : 'Stay', style: TextStyle(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isHindi ? 'बिना सेव' : 'Discard', style: const TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveAllSettings();
              if (context.mounted) Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(_isHindi ? 'सेव करें' : 'Save'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _loadSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt('lastFirestoreSync');
    if (lastSync != null && mounted) {
      final date = DateTime.fromMillisecondsSinceEpoch(lastSync);
      setState(() {
        _lastSyncTime =
            '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _performCloudSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final dairyId = prefs.getInt('dairyId');

      final result = await FirestoreSyncService.instance.fullSync(
        localDairyId: dairyId,
      );

      if (mounted) {
        if (result['success'] == true) {
          final uploaded = result['uploaded'] ?? 0;
          final downloaded = result['downloaded'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_done_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Sync Complete! ↑ $uploaded ↓ $downloaded')),
                ],
              ),
              backgroundColor: primaryGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          await _loadSyncStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync Failed: ${result['error']}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 12),
            Text(_isHindi ? 'लॉगआउट' : 'Logout', style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          _isHindi ? 'क्या आप लॉगआउट करना चाहते हैं?' : 'Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(_isHindi ? 'लॉगआउट' : 'Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Centralized secure logout
      await FirestoreSyncService.instance.performSecureLogout();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _changeTheme(String mode) {
    setState(() => _themeMode = mode);
    // Theme will be applied when save button is pressed
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canPop = await _onWillPop();
        if (canPop && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isHindi ? 'सेटिंग्स' : 'Settings',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_hasUnsavedChanges)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _saveAllSettings,
                icon: const Icon(Icons.save_rounded, color: Colors.white, size: 20),
                label: Text(_isHindi ? 'सेव' : 'Save', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== APPEARANCE =====
          _buildSectionCard(
            title: _isHindi ? 'दिखावट' : 'Appearance',
            icon: Icons.palette_rounded,
            child: Column(
              children: [
                _buildSettingLabel(_isHindi ? 'थीम' : 'Theme'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildThemeOption('light', Icons.light_mode_rounded, _isHindi ? 'लाइट' : 'Light'),
                    const SizedBox(width: 8),
                    _buildThemeOption('dark', Icons.dark_mode_rounded, _isHindi ? 'डार्क' : 'Dark'),
                    const SizedBox(width: 8),
                    _buildThemeOption('system', Icons.settings_brightness_rounded, _isHindi ? 'सिस्टम' : 'System'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== LANGUAGE =====
          _buildSectionCard(
            title: _isHindi ? 'भाषा' : 'Language',
            icon: Icons.language_rounded,
            child: Column(
              children: [
                _buildLanguageOption('hi', 'हिंदी (Hindi)', '🇮🇳'),
                const SizedBox(height: 8),
                _buildLanguageOption('en', 'English', '🇺🇸'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== MILK ENTRY SETTINGS =====
          _buildSectionCard(
            title: _isHindi ? 'दूध एंट्री सेटिंग्स' : 'Milk Entry Settings',
            icon: Icons.water_drop_rounded,
            child: Column(
              children: [
                _buildSwitchTile(
                  icon: Icons.flash_on_rounded,
                  title: _isHindi ? 'क्विक एंट्री मोड' : 'Quick Entry Mode',
                  subtitle: _isHindi ? 'FAT/SNF बाद में करें' : 'Add FAT/SNF later',
                  value: _quickEntryMode,
                  activeColor: Colors.orange,
                  onChanged: (v) {
                    setState(() => _quickEntryMode = v);
                  },
                ),
                const Divider(height: 24),
                // Fixed Rate Entry Behavior
                _buildSettingLabel(_isHindi ? 'फिक्स्ड रेट एंट्री व्यवहार' : 'Fixed Rate Entry Behavior'),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    _isHindi
                        ? 'जब किसान का फिक्स्ड रेट हो और FAT खाली छोड़ें तो'
                        : 'When farmer has fixed rate and FAT is left empty',
                    style: TextStyle(fontSize: 12, color: textLight),
                  ),
                ),
                Row(
                  children: [
                    _buildChoiceChip(
                      'pending',
                      _isHindi ? 'पेंडिंग' : 'Pending',
                      _fixedRateEntryBehavior,
                      Icons.pending_actions_rounded,
                      (v) => setState(() => _fixedRateEntryBehavior = v),
                    ),
                    const SizedBox(width: 8),
                    _buildChoiceChip(
                      'complete',
                      _isHindi ? 'सीधा पूर्ण' : 'Direct Complete',
                      _fixedRateEntryBehavior,
                      Icons.check_circle_rounded,
                      (v) => setState(() => _fixedRateEntryBehavior = v),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildSwitchTile(
                  icon: Icons.calculate_rounded,
                  title: _isHindi ? 'ऑटो रेट कैलकुलेट' : 'Auto Calculate Rate',
                  subtitle: _isHindi ? 'FAT/SNF से रेट अपने-आप' : 'Auto rate from FAT/SNF',
                  value: _autoCalculateRate,
                  activeColor: Colors.blue,
                  onChanged: (v) {
                    setState(() => _autoCalculateRate = v);
                  },
                ),
                const Divider(height: 24),
                _buildSwitchTile(
                  icon: Icons.check_circle_outline_rounded,
                  title: _isHindi ? 'एंट्री कन्फर्मेशन' : 'Entry Confirmation',
                  subtitle: _isHindi ? 'एंट्री सेव से पहले कन्फर्म करें' : 'Confirm before saving entry',
                  value: _showEntryConfirmation,
                  activeColor: Colors.green,
                  onChanged: (v) {
                    setState(() => _showEntryConfirmation = v);
                  },
                ),
                const Divider(height: 24),
                _buildSwitchTile(
                  icon: Icons.warning_amber_rounded,
                  title: _isHindi ? 'FAT/SNF चेतावनी' : 'FAT/SNF Warning',
                  subtitle: _isHindi ? 'असामान्य वैल्यू पर चेतावनी' : 'Warn on abnormal values',
                  value: _showFatSnfWarning,
                  activeColor: Colors.amber,
                  onChanged: (v) {
                    setState(() => _showFatSnfWarning = v);
                  },
                ),
                const Divider(height: 24),
                _buildSwitchTile(
                  icon: Icons.volume_up_rounded,
                  title: _isHindi ? 'एंट्री पर ध्वनि' : 'Sound on Entry',
                  subtitle: _isHindi ? 'एंट्री सेव होने पर आवाज़' : 'Play sound when entry saved',
                  value: _soundOnEntry,
                  activeColor: Colors.purple,
                  onChanged: (v) {
                    setState(() => _soundOnEntry = v);
                  },
                ),
                const Divider(height: 24),
                _buildSettingLabel(_isHindi ? 'डिफ़ॉल्ट शिफ्ट' : 'Default Shift'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildChoiceChip('auto', _isHindi ? 'ऑटो' : 'Auto', _defaultShift, Icons.auto_mode_rounded, (v) {
                      setState(() => _defaultShift = v);
                    }),
                    const SizedBox(width: 8),
                    _buildChoiceChip('morning', _isHindi ? 'सुबह' : 'Morning', _defaultShift, Icons.wb_sunny_rounded, (v) {
                      setState(() => _defaultShift = v);
                    }),
                    const SizedBox(width: 8),
                    _buildChoiceChip('evening', _isHindi ? 'शाम' : 'Evening', _defaultShift, Icons.nights_stay_rounded, (v) {
                      setState(() => _defaultShift = v);
                    }),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== BILLING SETTINGS =====
          _buildSectionCard(
            title: _isHindi ? 'बिलिंग सेटिंग्स' : 'Billing Settings',
            icon: Icons.receipt_long_rounded,
            child: Column(
              children: [
                _buildSwitchTile(
                  icon: Icons.print_rounded,
                  title: _isHindi ? 'बिलिंग के बाद प्रिंट' : 'Print After Billing',
                  subtitle: _isHindi ? 'बिल बनने के बाद ऑटो प्रिंट' : 'Auto print after bill generation',
                  value: _printAfterBilling,
                  activeColor: Colors.teal,
                  onChanged: (v) {
                    setState(() => _printAfterBilling = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== FAT WARNING RANGES =====
          if (_showFatSnfWarning)
            _buildSectionCard(
              title: _isHindi ? 'FAT चेतावनी रेंज' : 'FAT Warning Range',
              icon: Icons.tune_rounded,
              child: Column(
                children: [
                  _buildSettingLabel(_isHindi ? 'भैंस FAT रेंज' : 'Buffalo FAT Range'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildNumberField(_isHindi ? 'न्यूनतम' : 'Min', _minFatWarningBuffalo, (v) {
                        setState(() => _minFatWarningBuffalo = v);
                      })),
                      const SizedBox(width: 12),
                      Expanded(child: _buildNumberField(_isHindi ? 'अधिकतम' : 'Max', _maxFatWarningBuffalo, (v) {
                        setState(() => _maxFatWarningBuffalo = v);
                      })),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSettingLabel(_isHindi ? 'गाय FAT रेंज' : 'Cow FAT Range'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildNumberField(_isHindi ? 'न्यूनतम' : 'Min', _minFatWarningCow, (v) {
                        setState(() => _minFatWarningCow = v);
                      })),
                      const SizedBox(width: 12),
                      Expanded(child: _buildNumberField(_isHindi ? 'अधिकतम' : 'Max', _maxFatWarningCow, (v) {
                        setState(() => _maxFatWarningCow = v);
                      })),
                    ],
                  ),
                ],
              ),
            ),
          if (_showFatSnfWarning) const SizedBox(height: 16),

          // ===== CLOUD SYNC =====
          _buildSectionCard(
            title: _isHindi ? 'क्लाउड सिंक' : 'Cloud Sync',
            icon: Icons.cloud_sync_rounded,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: FirestoreSyncService.instance.isAuthenticated
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: FirestoreSyncService.instance.isAuthenticated
                          ? Colors.green.shade300
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: FirestoreSyncService.instance.isAuthenticated
                              ? Colors.green.shade100
                              : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          FirestoreSyncService.instance.isAuthenticated
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          color: FirestoreSyncService.instance.isAuthenticated
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              FirestoreSyncService.instance.isAuthenticated
                                  ? (_isHindi ? 'कनेक्टेड' : 'Connected')
                                  : (_isHindi ? 'कनेक्ट नहीं' : 'Not Connected'),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textDark),
                            ),
                            if (_lastSyncTime != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_isHindi ? "अंतिम सिंक" : "Last Sync"}: $_lastSyncTime',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSyncing ? null : _performCloudSync,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSyncing
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.sync_rounded, size: 20),
                              const SizedBox(width: 8),
                              Text(_isHindi ? 'अभी सिंक करें' : 'Sync Now', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ===== ABOUT =====
          _buildSectionCard(
            title: _isHindi ? 'ऐप के बारे में' : 'About',
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                _buildInfoRow(_isHindi ? 'वर्शन' : 'Version', '1.0.0'),
                const SizedBox(height: 12),
                _buildInfoRow(_isHindi ? 'डेवलपर' : 'Developer', 'Dudh Passbook'),
                const SizedBox(height: 12),
                _buildInfoRow(_isHindi ? 'सहायता' : 'Support', 'help@dudhpassbook.com'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SizedBox(height: 24),

          // Save Button
          if (_hasUnsavedChanges)
            SizedBox(
              height: 54,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveAllSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.save_rounded, size: 22),
                    const SizedBox(width: 10),
                    Text(_isHindi ? 'सेटिंग्स सेव करें' : 'Save Settings', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          if (_hasUnsavedChanges) const SizedBox(height: 16),

          // Logout
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, size: 22),
                  const SizedBox(width: 8),
                  Text(_isHindi ? 'लॉगआउट' : 'Logout', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      ),
    );
  }

  // ===== WIDGET BUILDERS =====

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: primaryGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark)),
          ]),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildSettingLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textLight)),
    );
  }

  Widget _buildThemeOption(String value, IconData icon, String label) {
    final isSelected = _themeMode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _changeTheme(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? primaryGreen.withOpacity(0.1) : bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? primaryGreen : Colors.transparent, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: isSelected ? primaryGreen : textLight, size: 24),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? primaryGreen : textLight)),
          ]),
        ),
      ),
    );
  }

  Widget _buildLanguageOption(String value, String label, String flag) {
    final isSelected = _language == value;
    return GestureDetector(
      onTap: () async {
        HapticFeedback.selectionClick();
        setState(() => _language = value);
        // Language will be applied when save button is pressed
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primaryGreen.withOpacity(0.1) : bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? primaryGreen : Colors.transparent, width: 1.5),
        ),
        child: Row(children: [
          Text(flag, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 15, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? primaryGreen : textDark)),
          const Spacer(),
          if (isSelected) Icon(Icons.check_circle_rounded, color: primaryGreen, size: 22),
        ]),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon, required String title, required String subtitle,
    required bool value, required Color activeColor, required ValueChanged<bool> onChanged,
  }) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: value ? activeColor.withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: value ? activeColor : Colors.grey.shade500, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textDark)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ])),
      Switch(value: value, onChanged: (v) { HapticFeedback.selectionClick(); onChanged(v); }, activeColor: activeColor),
    ]);
  }

  Widget _buildChoiceChip(String value, String label, String currentValue, IconData icon, ValueChanged<String> onSelected) {
    final isSelected = currentValue == value;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onSelected(value); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? primaryGreen.withOpacity(0.1) : bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? primaryGreen : Colors.transparent, width: 1.5),
          ),
          child: Column(children: [
            Icon(icon, color: isSelected ? primaryGreen : textLight, size: 18),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? primaryGreen : textLight)),
          ]),
        ),
      ),
    );
  }

  Widget _buildNumberField(String label, double value, ValueChanged<double> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: bgColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primaryGreen, width: 1.5)),
        labelStyle: TextStyle(fontSize: 12, color: textLight),
      ),
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 14, color: textLight)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textDark)),
    ]);
  }
}
