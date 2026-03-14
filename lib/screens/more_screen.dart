import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import 'staff_management_screen.dart';
import 'settings_screen.dart';
import 'rate_chart_screen.dart';
import 'reports_screen.dart';
import 'login_screen.dart';
import 'backup_screen.dart';
import 'profile_screen.dart';
import '../utils/theme_helper.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _userName = '';
  String _userRole = '';
  int _staffCount = 0;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark => _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final dairyId = prefs.getInt('dairyId');
    final staffCount = await DatabaseHelper.instance.getStaffCount(dairyId: dairyId);
    
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('userName') ?? 'User';
      _userRole = prefs.getString('userRole') ?? 'admin';
      _staffCount = staffCount;
      _languageCode = prefs.getString('language_code') ?? 'hi';
    });
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red.shade600),
            const SizedBox(width: 10),
            const Text('Logout'),
          ],
        ),
        content: Text(_isHindi ? 'क्या आप लॉगआउट करना चाहते हैं?' : 'Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _isLoggingOut = true;
      try {
      // Centralized secure logout
      await FirestoreSyncService.instance.performSecureLogout();
      
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
      } finally {
        _isLoggingOut = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _userRole == 'admin';
    
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'More',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              Text(
                'Settings & Management',
                style: TextStyle(
                  fontSize: 14,
                  color: textLight,
                ),
              ),
              const SizedBox(height: 24),
              
              // Account Item
              _buildMenuItem(
                icon: Icons.account_circle_rounded,
                title: _isHindi ? 'अकाउंट' : 'Account',
                subtitle: _userName.isNotEmpty ? _userName : (_isHindi ? 'प्रोफाइल देखें' : 'View Profile'),
                iconColor: primaryGreen,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ).then((_) => _loadUserData());
                },
              ),
              const SizedBox(height: 12),
              
              // Menu Items
              Text(
                'MENU',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textLight,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              
              // Settings
              _buildMenuItem(
                icon: Icons.settings_rounded,
                title: 'Settings',
                subtitle: 'App settings & preferences',
                iconColor: Colors.blue,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              
              // Staff Management (Admin only)
              if (isAdmin) ...[
                _buildMenuItem(
                  icon: Icons.people_rounded,
                  title: 'Staff Management',
                  subtitle: '$_staffCount staff members',
                  iconColor: Colors.purple,
                  onTap: () async {
                    HapticFeedback.selectionClick();
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StaffManagementScreen()),
                    );
                    _loadUserData(); // Refresh staff count
                  },
                ),
              ],
              
              // Rate Chart (Admin only)
              if (isAdmin) ...[
                _buildMenuItem(
                  icon: Icons.table_chart_rounded,
                  title: 'Rate Chart',
                  subtitle: 'Milk rate configuration',
                  iconColor: Colors.orange,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RateChartScreen()),
                    );
                  },
                ),
              ],
              
              // Backup & Restore (Admin only)
              if (isAdmin) ...[
                _buildMenuItem(
                  icon: Icons.backup_rounded,
                  title: 'Backup & Restore',
                  subtitle: 'Data backup management',
                  iconColor: Colors.teal,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupScreen()),
                    );
                  },
                ),
              ],
              
              // Reports (Admin only)
              if (isAdmin) ...[
                _buildMenuItem(
                  icon: Icons.analytics_rounded,
                  title: 'Reports',
                  subtitle: 'View detailed reports',
                  iconColor: Colors.indigo,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportsScreen()),
                    );
                  },
                ),
              ],
              
              const SizedBox(height: 24),
              
              // About Section
              Text(
                'ABOUT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textLight,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              
              _buildMenuItem(
                icon: Icons.info_outline_rounded,
                title: 'About App',
                subtitle: 'Version 1.0.0',
                iconColor: Colors.grey,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _showAboutDialog();
                },
              ),
              
              _buildMenuItem(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                subtitle: 'Get help with the app',
                iconColor: Colors.cyan,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Contact: support@dudhpassbook.com'),
                      backgroundColor: primaryGreen,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 24),
              
              // Logout Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    _logout();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Logout',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: textLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.agriculture_rounded, size: 40, color: primaryGreen),
            ),
            const SizedBox(height: 20),
            Text(
              'Dudh Passbook',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Professional dairy management solution for modern dairy farms.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}
