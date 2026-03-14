import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/milk_entry.dart';
import '../utils/theme_helper.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  DateTimeRange? _selectedRange;
  String? _selectedFarmerCode;
  List<MilkEntry> _entries = [];
  bool _isLoading = false;
  int? _dairyId;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  static const Color accentBlue = Color(0xFF1976D2);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    // Default to current month
    final now = DateTime.now();
    _selectedRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadUserAndEntries();
  }

  Future<void> _loadUserAndEntries() async {
    final prefs = await SharedPreferences.getInstance();
    _dairyId = prefs.getInt('dairyId');
    _languageCode = prefs.getString('language_code') ?? 'hi';
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (_selectedRange == null) return;
    
    setState(() => _isLoading = true);
    try {
      _entries = await _db.getMilkEntriesForBilling(
        startDate: _selectedRange!.start,
        endDate: _selectedRange!.end,
        farmerCode: _selectedFarmerCode,
        dairyId: _dairyId,
      );
    } catch (e) {
      _entries = [];
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedRange = picked);
      _loadEntries();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalLiters = _entries.fold<double>(0, (sum, e) => sum + e.quantity);
    final totalAmount = _entries.fold<double>(0, (sum, e) => sum + e.amount);
    final avgRate = totalLiters > 0 ? totalAmount / totalLiters : 0.0;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          // Date Range Selector
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: _selectDateRange,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_rounded, color: primaryGreen, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isHindi ? 'तारीख' : 'Date Range',
                                style: TextStyle(fontSize: 12, color: textLight),
                              ),
                              Text(
                                _selectedRange != null
                                    ? '${_formatDate(_selectedRange!.start)} - ${_formatDate(_selectedRange!.end)}'
                                    : 'Select dates',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_drop_down_rounded, color: Colors.grey.shade600),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Summary Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _buildSummaryCard('Entries', '${_entries.length}', Icons.format_list_numbered_rounded, accentBlue)),
                const SizedBox(width: 10),
                Expanded(child: _buildSummaryCard('Liters', '${totalLiters.toStringAsFixed(1)}L', Icons.water_drop_rounded, primaryGreen)),
                const SizedBox(width: 10),
                Expanded(child: _buildSummaryCard('Amount', '₹${totalAmount.toStringAsFixed(0)}', Icons.currency_rupee_rounded, const Color(0xFFFF9800))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: accentBlue,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Entries',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                ),
                const Spacer(),
                if (avgRate > 0)
                  Text(
                    'Avg: ₹${avgRate.toStringAsFixed(2)}/L',
                    style: TextStyle(fontSize: 12, color: textLight),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Entries List
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryGreen))
                : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              _isHindi ? 'कोई एंट्री नहीं मिली' : 'No entries found',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) => _buildEntryCard(_entries[index]),
                      ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(MilkEntry entry) {
    final isMorning = entry.shift == 'morning';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isMorning ? Colors.orange.shade50 : Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
              color: isMorning ? Colors.orange : Colors.indigo,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.farmerName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: textDark,
                  ),
                ),
                Text(
                  '${_formatDate(entry.dateTime)} • ${entry.quantity}L • Fat: ${entry.fat}%',
                  style: TextStyle(fontSize: 12, color: textLight),
                ),
              ],
            ),
          ),
          Text(
            '₹${entry.amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
