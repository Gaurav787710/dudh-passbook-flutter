import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import '../utils/localization.dart';
import '../utils/ui_helpers.dart';
import 'farmers_screen.dart';
import 'milk_entry_screen.dart';
import 'billing_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Map<String, dynamic> _todaysSummary = {};
  List<Map<String, dynamic>> _last7DaysData = [];
  bool _isLoading = true;
  bool _isLoggingOut = false;
  String _username = '';
  bool _isDemo = false;
  String _languageCode = 'hi';

  // Professional Colors
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color bgColor = Color(0xFFF5F7FA);
  
  // Helper to get translated text
  String _tr(String key) {
    return AppLocalizations(Locale(_languageCode)).translate(key);
  }
  
  bool get _isHindi => _languageCode == 'hi';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _username = prefs.getString('userName') ?? 'Admin';
      _isDemo = prefs.getBool('isDemo') ?? false;
      _languageCode = prefs.getString('language_code') ?? 'hi';

      // Load demo data if in demo mode
      if (_isDemo) {
        try {
          final farmers = await _db.getAllFarmers();
          if (farmers.isEmpty) {
            await _db.insertDemoData();
          }
        } catch (e) {
          debugPrint('[DashboardScreen] demo data error: $e');
        }
      }

      // Load local data FIRST (instant), then sync in background (non-blocking)
      final dairyIdForStats = prefs.getInt('dairyId');
      try {
        _todaysSummary = await _db.getDashboardStats(dairyId: dairyIdForStats);
        _last7DaysData = await _db.getLast7DaysData();
      } catch (e) {
        _todaysSummary = {
          'totalFarmers': 0,
          'todaysMilk': 0.0,
          'morningMilk': 0.0,
          'eveningMilk': 0.0,
          'todaysAmount': 0.0,
          'avg7DayMilk': 0.0,
          'farmersCollectedToday': 0,
          'farmersPaid10Days': 0,
        };
        _last7DaysData = [];
      }
    } catch (e) {
      debugPrint('[DashboardScreen] loadData error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    // Background sync — does NOT block UI
    if (!_isDemo) {
      try {
        final syncService = FirestoreSyncService.instance;
        if (syncService.isAuthenticated) {
          final prefs2 = await SharedPreferences.getInstance();
          final dairyId = prefs2.getInt('dairyId');
          await syncService.fullSync(localDairyId: dairyId);
          // Refresh data after sync completes in background
          if (mounted) {
            final newSummary = await _db.getDashboardStats(dairyId: dairyId);
            final newChart = await _db.getLast7DaysData();
            if (mounted) {
              setState(() {
                _todaysSummary = newSummary;
                _last7DaysData = newChart;
              });
            }
          }
        }
      } catch (e) {
        debugPrint('[DashboardScreen] background sync error: $e');
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    try {
      // Centralized secure logout: stops listeners, signs out auth,
      // resets SQLite DB, clears prefs (preserves UI), clears Firestore cache.
      await FirestoreSyncService.instance.performSecureLogout();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isHindi ? 'डैशबोर्ड' : 'Dashboard',
          style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isDemo)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade400,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'DEMO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: _isHindi ? 'रिफ्रेश' : 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: _isHindi ? 'लॉगआउट' : 'Logout',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: _buildDrawer(),
      body: _isLoading
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: _loadData,
              color: primaryGreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 20),
                  _buildQuickActionsBar(),
                  const SizedBox(height: 24),
                  _buildCircularSummaryCards(),
                  const SizedBox(height: 20),
                  _buildMiniTrendChart(),
                  const SizedBox(height: 20),
                  _buildLast7DaysChart(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryGreen, primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: primaryGreen.withOpacity(0.1),
                    child: Icon(
                      Icons.person_rounded,
                      size: 36,
                      color: primaryGreen,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Admin',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  Icons.dashboard_rounded,
                  _isHindi ? 'डैशबोर्ड' : 'Dashboard',
                  true,
                  () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  Icons.people_rounded,
                  _isHindi ? 'किसान' : 'Farmers',
                  false,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FarmersScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  Icons.water_drop_rounded,
                  _isHindi ? 'दूध एंट्री' : 'Milk Entry',
                  false,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MilkEntryScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  Icons.receipt_long_rounded,
                  _isHindi ? 'बिलिंग' : 'Billing',
                  false,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BillingScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  Icons.bar_chart_rounded,
                  _isHindi ? 'रिपोर्ट्स' : 'Reports',
                  false,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ReportsScreen(),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  Icons.settings_rounded,
                  _isHindi ? 'सेटिंग्स' : 'Settings',
                  false,
                  () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(),
                _buildDrawerItem(
                  Icons.logout_rounded,
                  _isHindi ? 'लॉगआउट' : 'Logout',
                  false,
                  _logout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
    IconData icon,
    String title,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? primaryGreen : Colors.grey.shade600,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? primaryGreen : Colors.grey.shade800,
        ),
      ),
      selected: isSelected,
      selectedTileColor: primaryGreen.withOpacity(0.1),
      onTap: onTap,
    );
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return '${days[now.weekday % 7]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Today',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A1A),
                letterSpacing: -0.5,
              ),
            ),
            Text(
              _getFormattedDate(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline_rounded, size: 18, color: primaryGreen),
              const SizedBox(width: 6),
              Text(
                _username,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildQuickActionItem(
            'Farmer',
            'किसान',
            Icons.person_add_rounded,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FarmersScreen()),
            ),
          ),
          _buildQuickActionItem(
            'Entry',
            'एंट्री',
            Icons.add_circle_rounded,
            primaryGreen,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MilkEntryScreen()),
            ),
          ),
          _buildQuickActionItem(
            'Billing',
            'बिलिंग',
            Icons.receipt_long_rounded,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BillingScreen()),
            ),
          ),
          _buildQuickActionItem(
            'Reports',
            'रिपोर्ट',
            Icons.analytics_rounded,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem(
    String label,
    String labelHindi,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final displayLabel = _isHindi ? labelHindi : label;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              displayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularSummaryCards() {
    final double todaysMilk =
        (_todaysSummary['todaysMilk'] as num?)?.toDouble() ?? 0;
    final double morningMilk =
        (_todaysSummary['morningMilk'] as num?)?.toDouble() ?? 0;
    final double eveningMilk =
        (_todaysSummary['eveningMilk'] as num?)?.toDouble() ?? 0;
    final double todaysAmount =
        (_todaysSummary['todaysAmount'] as num?)?.toDouble() ?? 0;
    final int totalFarmers =
        (_todaysSummary['totalFarmers'] as num?)?.toInt() ?? 0;
    final int farmersCollectedToday =
        (_todaysSummary['farmersCollectedToday'] as num?)?.toInt() ?? 0;
    final double avg7DayMilk =
        (_todaysSummary['avg7DayMilk'] as num?)?.toDouble() ?? 0;
    final int farmersPaid10Days =
        (_todaysSummary['farmersPaid10Days'] as num?)?.toInt() ?? 0;

    // Calculate percentages based on 7-day average
    final double milkPercent = avg7DayMilk > 0 ? (todaysMilk / avg7DayMilk) : 0;
    final double farmerCollectionPercent = totalFarmers > 0
        ? (farmersCollectedToday / totalFarmers)
        : 0;
    final double paymentPercent = totalFarmers > 0
        ? (farmersPaid10Days / totalFarmers)
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tr('todays_progress'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            // Total Milk Card - shows progress vs 7-day average
            Expanded(
              child: _buildClickableProgressCard(
                'Total Milk',
                'कुल दूध',
                '${todaysMilk.toStringAsFixed(1)}L',
                milkPercent,
                Colors.teal,
                Icons.water_drop_rounded,
                () => _showMilkDetailsPopup(
                  todaysMilk,
                  morningMilk,
                  eveningMilk,
                  avg7DayMilk,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Farmers Card - shows collection progress
            Expanded(
              child: _buildClickableProgressCard(
                'Farmers',
                'किसान',
                '$farmersCollectedToday/$totalFarmers',
                farmerCollectionPercent,
                Colors.blue,
                Icons.people_rounded,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FarmersScreen()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Today's Amount Card
            Expanded(
              child: _buildClickableProgressCard(
                'Amount',
                'राशि',
                '₹${todaysAmount.toStringAsFixed(0)}',
                milkPercent, // Use same as milk since amount correlates
                Colors.green,
                Icons.currency_rupee_rounded,
                () => _showAmountDetailsPopup(todaysAmount),
              ),
            ),
            const SizedBox(width: 12),
            // Payment Status Card - 10 days
            Expanded(
              child: _buildClickableProgressCard(
                'Paid',
                'भुगतान',
                '$farmersPaid10Days/$totalFarmers',
                paymentPercent,
                Colors.orange,
                Icons.payment_rounded,
                () => _showPaymentDetailsPopup(farmersPaid10Days, totalFarmers),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClickableProgressCard(
    String title,
    String titleHindi,
    String value,
    double progress,
    Color color,
    IconData icon,
    VoidCallback onTap,
  ) {
    final clampedProgress = progress.clamp(0.0, 1.0);
    final percentage = (clampedProgress * 100).toInt();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Google Health style ring
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background ring
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 8,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        color.withOpacity(0.12),
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Progress ring
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      value: clampedProgress,
                      strokeWidth: 8,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Center content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(height: 2),
                      Text(
                        '$percentage%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isHindi ? titleHindi : title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showMilkDetailsPopup(
    double total,
    double morning,
    double evening,
    double avg7Day,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                color: Colors.teal,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(_tr('milk_collection_title'), style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow(
              _tr('morning'),
              '${morning.toStringAsFixed(1)} L',
              Colors.orange,
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              _tr('evening'),
              '${evening.toStringAsFixed(1)} L',
              Colors.indigo,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              _isHindi ? 'आज कुल' : 'Total Today',
              '${total.toStringAsFixed(1)} L',
              Colors.teal,
            ),
            const SizedBox(height: 12),
            _buildDetailRow(
              _isHindi ? '7 दिन औसत' : '7-Day Avg',
              '${avg7Day.toStringAsFixed(1)} L',
              Colors.grey,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: total >= avg7Day
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    total >= avg7Day ? Icons.trending_up : Icons.trending_down,
                    color: total >= avg7Day ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    avg7Day > 0
                        ? '${((total / avg7Day - 1) * 100).abs().toStringAsFixed(1)}% ${total >= avg7Day ? _tr('above_average') : _tr('below_average')}'
                        : _tr('no_previous_data'),
                    style: TextStyle(
                      color: total >= avg7Day ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_tr('close')),
          ),
        ],
      ),
    );
  }

  void _showAmountDetailsPopup(double amount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.currency_rupee_rounded,
                color: Colors.green,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(_tr('todays_amount'), style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '₹${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _tr('total_payable_today'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_tr('close')),
          ),
          ElevatedButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute(builder: (_) => const BillingScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(_tr('go_to_billing')),
          ),
        ],
      ),
    );
  }

  void _showPaymentDetailsPopup(int paidFarmers, int totalFarmers) {
    final unpaidFarmers = totalFarmers - paidFarmers;
    final paymentPercent = totalFarmers > 0
        ? (paidFarmers / totalFarmers * 100)
        : 0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.payment_rounded,
                color: Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(_tr('payment_status'), style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tr('last_10_days'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _buildDetailRow(_tr('paid_farmers'), '$paidFarmers', Colors.green),
            const SizedBox(height: 12),
            _buildDetailRow(_tr('pending'), '$unpaidFarmers', Colors.red),
            const Divider(height: 24),
            _buildDetailRow(_isHindi ? 'कुल किसान' : 'Total Farmers', '$totalFarmers', Colors.blue),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: paymentPercent >= 80
                    ? Colors.green.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    paymentPercent >= 80 ? Icons.check_circle : Icons.warning,
                    color: paymentPercent >= 80 ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${paymentPercent.toStringAsFixed(0)}% ${_tr('farmers_paid')}',
                    style: TextStyle(
                      color: paymentPercent >= 80
                          ? Colors.green
                          : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_tr('close')),
          ),
          ElevatedButton(
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.push(
                MaterialPageRoute(builder: (_) => const BillingScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(_tr('go_to_billing')),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniTrendChart() {
    // Calculate trend percentage
    double todayMilk = (_todaysSummary['todaysMilk'] as num?)?.toDouble() ?? 0;
    double yesterdayMilk = 0;
    if (_last7DaysData.length >= 2) {
      yesterdayMilk =
          (_last7DaysData[_last7DaysData.length - 2]['totalLiters'] as num?)
              ?.toDouble() ??
          0;
    }
    double trendPercent = yesterdayMilk > 0
        ? ((todayMilk - yesterdayMilk) / yesterdayMilk * 100)
        : 0;
    bool isUp = trendPercent >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isHindi ? 'संग्रह रुझान' : 'Collection Trend',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${todayMilk.toStringAsFixed(1)} L',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isUp
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUp
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            size: 14,
                            color: isUp ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${trendPercent.abs().toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isUp ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isHindi ? 'कल की तुलना में' : 'vs yesterday',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 60,
              child: _last7DaysData.isEmpty
                  ? Center(
                      child: Text(
                        _isHindi ? 'कोई डेटा नहीं' : 'No data',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        minX: 0,
                        maxX: (_last7DaysData.length - 1).toDouble(),
                        minY: 0,
                        maxY: _getMaxY(),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _last7DaysData.asMap().entries.map((e) {
                              return FlSpot(
                                e.key.toDouble(),
                                (e.value['totalLiters'] as num?)?.toDouble() ??
                                    0,
                              );
                            }).toList(),
                            isCurved: true,
                            curveSmoothness: 0.3,
                            color: primaryGreen,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: index == _last7DaysData.length - 1
                                      ? 4
                                      : 0,
                                  color: primaryGreen,
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              gradient: LinearGradient(
                                colors: [
                                  primaryGreen.withOpacity(0.2),
                                  primaryGreen.withOpacity(0.02),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Old methods removed - now using _buildQuickActionsBar and _buildCircularSummaryCards

  Widget _buildLast7DaysChart() {
    if (_last7DaysData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              _isHindi ? 'अभी कोई डेटा नहीं है' : 'No data available yet',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // Calculate weekly stats
    double totalWeekMilk = 0;
    double totalWeekAmount = 0;
    double maxDayMilk = 0;

    for (var data in _last7DaysData) {
      final liters = (data['totalLiters'] as num?)?.toDouble() ?? 0;
      final amount = (data['totalAmount'] as num?)?.toDouble() ?? 0;
      totalWeekMilk += liters;
      totalWeekAmount += amount;
      if (liters > maxDayMilk) {
        maxDayMilk = liters;
      }
    }

    final avgDailyMilk = _last7DaysData.isNotEmpty
        ? totalWeekMilk / _last7DaysData.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isHindi ? '7 दिन की प्रगति' : '7 Day Progress',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isHindi ? '${totalWeekMilk.toStringAsFixed(0)}L कुल' : '${totalWeekMilk.toStringAsFixed(0)}L Total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: primaryGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatChip(
                _isHindi ? 'औसत: ${avgDailyMilk.toStringAsFixed(1)}L/दिन' : 'Avg: ${avgDailyMilk.toStringAsFixed(1)}L/day',
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildStatChip(
                '₹${totalWeekAmount.toStringAsFixed(0)}',
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _getMaxY(),
                barGroups: _buildBarGroups(),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _last7DaysData.length) {
                          final date = _last7DaysData[index]['date'] as String?;
                          if (date != null && date.length >= 5) {
                            // Show day name
                            final parts = date.split('-');
                            if (parts.length >= 3) {
                              final day = int.tryParse(parts[2]) ?? 0;
                              final month = int.tryParse(parts[1]) ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '$day/${month}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              );
                            }
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}L',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey.shade600,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _getMaxY() / 4,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(color: Colors.grey.shade200, strokeWidth: 1);
                  },
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.grey.shade800,
                    tooltipRoundedRadius: 8,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toStringAsFixed(1)}L',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

  double _getMaxY() {
    double max = 10;
    for (var data in _last7DaysData) {
      final total = (data['totalLiters'] as num?)?.toDouble() ?? 0;
      if (total > max) max = total;
    }
    return max * 1.2;
  }

  List<BarChartGroupData> _buildBarGroups() {
    return _last7DaysData.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final total = (data['totalLiters'] as num?)?.toDouble() ?? 0;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: total,
            color: primaryGreen,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: _getMaxY(),
              color: Colors.grey.shade100,
            ),
          ),
        ],
      );
    }).toList();
  }
}
