import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firestore_sync_service.dart';
import 'dashboard_screen.dart';
import 'milk_entry_screen.dart';
import 'farmers_screen.dart';
import 'payment_manager_screen.dart';
import 'more_screen.dart';
import 'entry_history_screen.dart';
import 'settings_screen.dart';

// Professional Color Palette for Dairy App - Theme Aware
class AppColors {
  static bool _isDark = false;
  static void update(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
  }
  
  static Color get primary => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  static Color get primaryDark => _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  static Color get primaryLight => _isDark ? const Color(0xFF7986CB) : const Color(0xFF81C784);
  static Color get accent => const Color(0xFF1976D2);
  static Color get background => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  static Color get surface => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  static Color get cardBg => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  static Color get textPrimary => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  static Color get textSecondary => _isDark ? Colors.white70 : const Color(0xFF666666);
  static Color get divider => _isDark ? Colors.white12 : const Color(0xFFE0E0E0);
  static Color get success => const Color(0xFF43A047);
  static Color get warning => const Color(0xFFFFA000);
  static Color get error => const Color(0xFFE53935);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _dairyName = 'Dudh Passbook';
  String _username = 'Admin';
  String _userRole = 'admin'; // 'admin' or 'staff'
  bool _isLoading = true;
  int? _dairyId;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;

  // Admin screens - Home replaced with History
  final List<Widget> _adminScreens = const [
    EntryHistoryScreen(), // Was DashboardScreen - now History
    FarmersScreen(),
    MilkEntryScreen(),
    PaymentManagerScreen(),
    MoreScreen(),
  ];

  // Staff screens (only Entry and History)
  final List<Widget> _staffScreens = const [
    MilkEntryScreen(),
    EntryHistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    // Stop real-time sync when leaving
    _syncService.stopRealtimeSync();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    _dairyId = prefs.getInt('dairyId');
    
    // Start real-time sync
    _syncService.onDataChanged = () {
      // Data changed from Firebase - child screens manage their own state,
      // no need to rebuild HomeScreen shell (bottom nav, header).
    };
    await _syncService.startRealtimeSync(_dairyId);
    
    if (!mounted) return;
    setState(() {
      _dairyName = prefs.getString('dairyName') ?? 'Dudh Passbook';
      _username = prefs.getString('userName') ?? 'Admin';
      _userRole = prefs.getString('userRole') ?? 'admin';
      _languageCode = prefs.getString('language_code') ?? 'hi';
      _isLoading = false;
      // Set default index based on role
      if (_userRole == 'staff') {
        _currentIndex = 0; // Milk Entry for staff
      } else {
        _currentIndex = 2; // Entry page for admin (default)
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    AppColors.update(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _userRole == 'staff'
                  ? _staffScreens[_currentIndex]
                  : _adminScreens[_currentIndex],
            ),
          ],
        ),
        bottomNavigationBar: _userRole == 'staff'
            ? _buildStaffBottomNav()
            : _buildAdminBottomNav(),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
          child: Row(
            children: [
              // Logo - Clickable to open Dashboard (Admin only)
              GestureDetector(
                onTap: _userRole == 'admin' ? () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
                } : null,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.water_drop_rounded, color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 10),
              // Title
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _dairyName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.8), size: 12),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _username,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions - compact
              if (_userRole == 'admin') ...[
                _buildHeaderButton(Icons.settings_rounded, 'Settings', () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }),
              ],
              if (_userRole == 'staff') ...[
                _buildHeaderButton(Icons.settings_rounded, 'Settings', () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }

  // ============ ADMIN BOTTOM NAV ============
  Widget _buildAdminBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(0, Icons.history_outlined, Icons.history_rounded, 'History'),
              _buildNavItem(1, Icons.people_outline, Icons.people_rounded, 'Farmers'),
              _buildCenterButton(),
              _buildNavItem(3, Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Payment'),
              _buildNavItem(4, Icons.more_horiz_outlined, Icons.more_horiz_rounded, 'More'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                size: 26,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    final isSelected = _currentIndex == 2;
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        setState(() => _currentIndex = 2);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primary, AppColors.primaryDark],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.local_drink_rounded : Icons.add_rounded,
              size: 22,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            const Text(
              'Entry',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ STAFF BOTTOM NAV ============
  Widget _buildStaffBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Expanded(child: _buildStaffNavButton(0, Icons.add_circle_outline_rounded, Icons.add_circle_rounded, _isHindi ? 'नई एंट्री' : 'New Entry')),
              const SizedBox(width: 16),
              Expanded(child: _buildStaffNavButton(1, Icons.history_rounded, Icons.history_rounded, _isHindi ? 'हिस्ट्री' : 'History')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStaffNavButton(int index, IconData icon, IconData activeIcon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? LinearGradient(colors: [AppColors.primary, AppColors.primaryDark])
              : null,
          color: isSelected ? null : AppColors.background,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 28,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
