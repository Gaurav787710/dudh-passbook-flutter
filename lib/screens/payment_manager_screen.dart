import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';
import 'bill_preview_screen.dart';
import '../utils/theme_helper.dart';
import '../utils/ui_helpers.dart';

class PaymentManagerScreen extends StatefulWidget {
  const PaymentManagerScreen({super.key});

  @override
  State<PaymentManagerScreen> createState() => _PaymentManagerScreenState();
}

class _PaymentManagerScreenState extends State<PaymentManagerScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;
  late TabController _tabController;
  bool _isLoading = true;
  int? _dairyId;
  String _dairyName = 'Dudh Passbook';

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Data
  List<Farmer> _farmers = [];
  List<MilkEntry> _entries = [];
  List<Payment> _payments = [];
  Map<int, Map<String, dynamic>> _cachedBills = {}; // farmerId -> bill (precomputed)
  bool _isProcessing = false; // double-tap guard for payment ops

  // Bill Tab
  Farmer? _selectedFarmer;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 10));
  DateTime _endDate = DateTime.now();
  String _selectedCycle = '';

  // Advance Tab
  final _advanceAmountController = TextEditingController();
  final _advanceNotesController = TextEditingController();
  Farmer? _advanceFarmer;

  // Bulk Tab
  List<String> _bulkSelection = [];

  // History Tab
  String _historyFilter = 'ALL';
  String _historySearch = '';

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryOrange = Color(0xFFEF6C00);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _advanceAmountController.dispose();
    _advanceNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _dairyId = prefs.getInt('dairyId');
      _dairyName = prefs.getString('dairyName') ?? 'Dudh Passbook';
      _languageCode = prefs.getString('language_code') ?? 'hi';
      _farmers = await _db.getAllFarmers(dairyId: _dairyId);
      // Load ONLY entries within billing date range to prevent OOM
      _entries = await _db.getMilkEntries(
        dairyId: _dairyId,
        startDate: _startDate,
        endDate: _endDate.add(const Duration(days: 1)), // inclusive end
      );
      // FINANCIAL SAFETY: Fetch payments from Firestore (single source of truth)
      // Falls back to local SQLite if not authenticated
      _payments = await _syncService.fetchPaymentsFromFirestore(_dairyId);
      
      // Reset selected farmers if they're no longer in the list
      if (_selectedFarmer != null && !_farmers.any((f) => f.id == _selectedFarmer!.id)) {
        _selectedFarmer = null;
      }
      if (_advanceFarmer != null && !_farmers.any((f) => f.id == _advanceFarmer!.id)) {
        _advanceFarmer = null;
      }
      // Precompute all farmer bills once (not on every build)
      _precomputeBills();
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', isError: true);
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Precompute bills for ALL farmers once (not on every build)
  void _precomputeBills() {
    _cachedBills = {};
    for (var farmer in _farmers) {
      if (farmer.id != null) {
        _cachedBills[farmer.id!] = _calculateFarmerBill(farmer.id!);
      }
    }
  }

  /// Get cached bill (falls back to live calculation if not cached)
  Map<String, dynamic> _getCachedBill(int farmerId) {
    return _cachedBills[farmerId] ?? _calculateFarmerBill(farmerId);
  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : (isSuccess ? primaryGreen : Colors.grey.shade800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // Calculate farmer bill
  Map<String, dynamic> _calculateFarmerBill(int farmerId) {
    final farmerEntries = _entries.where((e) =>
      e.farmerId == farmerId &&
      e.dateTime.isAfter(_startDate.subtract(const Duration(days: 1))) &&
      e.dateTime.isBefore(_endDate.add(const Duration(days: 1)))
    ).toList();

    final farmerPayments = _payments.where((p) => p.farmerId == farmerId).toList();
    
    // Advances are a running balance (ledger-based) — NOT period-filtered.
    // Sum ALL unpaid advances for this farmer, regardless of billing period.
    // Once a bill payment is made, advances are marked isPaid=true.
    final unpaidAdvances = _payments.where((p) =>
      p.farmerId == farmerId &&
      p.type == 'ADVANCE' &&
      p.isPaid != true
    ).toList();

    final totalMilk = double.parse(farmerEntries.fold(0.0, (s, e) => s + e.quantity).toStringAsFixed(2));
    final totalAmount = double.parse(farmerEntries.fold(0.0, (s, e) => s + e.amount).toStringAsFixed(2));
    final totalAdvance = double.parse(unpaidAdvances.fold(0.0, (s, p) => s + p.amount).toStringAsFixed(2));
    
    // Calculate already paid FOR this billing period
    // CRITICAL FIX: Match by the payment's billing period (fromDate/toDate),
    // NOT by paymentDate (when payment was physically made).
    // Payment made on Feb 12 FOR period Feb 1-10 must be deducted when viewing Feb 1-10.
    final paidInPeriod = farmerPayments.where((p) {
      if (p.type != 'PAYMENT') return false;
      // Match by billing period (fromDate/toDate) — the period this payment covers
      if (p.fromDate != null && p.toDate != null) {
        final pFrom = DateTime(p.fromDate!.year, p.fromDate!.month, p.fromDate!.day);
        final pTo = DateTime(p.toDate!.year, p.toDate!.month, p.toDate!.day);
        final sStart = DateTime(_startDate.year, _startDate.month, _startDate.day);
        final sEnd = DateTime(_endDate.year, _endDate.month, _endDate.day);
        // Overlap check: payment period intersects billing period
        return !pTo.isBefore(sStart) && !pFrom.isAfter(sEnd);
      }
      // Fallback for legacy payments without fromDate/toDate: use paymentDate
      return p.paymentDate.isAfter(_startDate.subtract(const Duration(days: 1))) &&
             p.paymentDate.isBefore(_endDate.add(const Duration(days: 1)));
    }).fold(0.0, (s, p) => s + p.amount);

    const double lbtAmount = 10.0; // LBT deduction as per website
    final netPayable = double.parse((totalAmount - totalAdvance - paidInPeriod - lbtAmount).toStringAsFixed(2));

    return {
      'entries': farmerEntries,
      'totalMilk': totalMilk,
      'totalAmount': totalAmount,
      'totalAdvance': totalAdvance,
      'paidInPeriod': paidInPeriod,
      'lbtAmount': lbtAmount,
      'netPayable': netPayable > 0 ? netPayable : 0.0,
      'unpaidAdvanceIds': unpaidAdvances.map((a) => a.id).toList(),
    };
  }

  // Set billing cycle
  void _setDateRange(String cycle) {
    final now = DateTime.now();
    final currentDay = now.day;
    DateTime start, end;

    if (cycle == '10_DAYS') {
      if (currentDay >= 21) {
        start = DateTime(now.year, now.month, 11);
        end = DateTime(now.year, now.month, 20);
      } else if (currentDay >= 11) {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month, 10);
      } else {
        final prevMonth = now.month == 1 ? 12 : now.month - 1;
        final prevYear = now.month == 1 ? now.year - 1 : now.year;
        final lastDay = DateTime(prevYear, prevMonth + 1, 0).day;
        start = DateTime(prevYear, prevMonth, 21);
        end = DateTime(prevYear, prevMonth, lastDay);
      }
    } else if (cycle == '15_DAYS') {
      if (currentDay >= 16) {
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month, 15);
      } else {
        final prevMonth = now.month == 1 ? 12 : now.month - 1;
        final prevYear = now.month == 1 ? now.year - 1 : now.year;
        final lastDay = DateTime(prevYear, prevMonth + 1, 0).day;
        start = DateTime(prevYear, prevMonth, 16);
        end = DateTime(prevYear, prevMonth, lastDay);
      }
    } else {
      // Full month
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      final lastDay = DateTime(prevYear, prevMonth + 1, 0).day;
      start = DateTime(prevYear, prevMonth, 1);
      end = DateTime(prevYear, prevMonth, lastDay);
    }

    setState(() {
      _startDate = start;
      _endDate = end;
      _selectedCycle = cycle;
    });
    // Reload entries for the new date range
    _loadData();
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: primaryGreen)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedCycle = 'CUSTOM';
      });
      // Reload entries for the new date range
      _loadData();
    }
  }

  // Process single payment
  Future<void> _processPayment() async {
    if (_isProcessing) return;
    if (_selectedFarmer == null) {
      _showSnackBar('Please select a farmer', isError: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {

    final bill = _calculateFarmerBill(_selectedFarmer!.id!);
    if ((bill['netPayable'] as num) <= 0) {
      _showSnackBar(_isHindi ? 'कोई बकाया राशि नहीं' : 'No pending amount', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.payment_rounded, color: primaryGreen),
          const SizedBox(width: 10),
          const Text('Confirm Payment'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Farmer: ${_selectedFarmer!.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Period: ${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}'),
            const Divider(height: 20),
            _buildConfirmRow('Total Milk:', '${(bill['totalMilk'] as num).toStringAsFixed(1)} Ltr'),
            _buildConfirmRow('Total Amount:', '₹${(bill['totalAmount'] as num).toStringAsFixed(0)}'),
            if ((bill['totalAdvance'] as num) > 0)
              _buildConfirmRow('Less Advance:', '-₹${(bill['totalAdvance'] as num).toStringAsFixed(0)}', isDeduction: true),
            if ((bill['paidInPeriod'] as num? ?? 0) > 0)
              _buildConfirmRow('Less Paid:', '-₹${(bill['paidInPeriod'] as num).toStringAsFixed(0)}', isDeduction: true),
            if ((bill['lbtAmount'] as num? ?? 0) > 0)
              _buildConfirmRow('Less LBT:', '-₹${(bill['lbtAmount'] as num).toStringAsFixed(0)}', isDeduction: true),
            const Divider(height: 16),
            _buildConfirmRow('Net Payable:', '₹${(bill['netPayable'] as num).toStringAsFixed(0)}', isBold: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text('Pay Now', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Network check before processing payment
      final hasNet = await hasInternetConnection();
      if (!hasNet && mounted) {
        await showNoInternetDialog(context, isHindi: _isHindi);
        return;
      }

      try {
        // Advance is a running balance (ledger). Payment.amount records
        // the full bill settlement; advanceDeduction shows how much advance
        // was consumed. netAmount = actual cash handed over.
        // After payment, mark advances isPaid so they don't deduct again.

        final double billTotal = (bill['totalAmount'] as num).toDouble();
        final double existingPaid = (bill['paidInPeriod'] as num).toDouble();
        final double lbt = (bill['lbtAmount'] as num).toDouble();
        final double advTotal = (bill['totalAdvance'] as num).toDouble();
        // Full settlement = bill minus what's already paid minus LBT
        final double settlementAmount = billTotal - existingPaid - lbt;
        final double cashPaid = (bill['netPayable'] as num).toDouble();

        final payment = Payment(
          farmerId: _selectedFarmer!.id!,
          farmerCode: _selectedFarmer!.code,
          farmerName: _selectedFarmer!.name,
          paymentDate: DateTime.now(),
          fromDate: _startDate,
          toDate: _endDate,
          type: 'PAYMENT',
          amount: settlementAmount,
          advanceDeduction: advTotal,
          netAmount: cashPaid,
          totalLiters: (bill['totalMilk'] as num).toDouble(),
          paymentMode: 'cash',
          notes: 'Bill Payment: ${DateFormat('dd/MM').format(_startDate)} to ${DateFormat('dd/MM').format(_endDate)}',
        );

        // FIREBASE-FIRST: Write to Firestore, then cache locally
        await _syncService.addPaymentFirestoreFirst(payment, _dairyId);

        // Mark advances as consumed (isPaid=true) so they don't deduct
        // from future bills. Advance stays as a separate record.
        if (advTotal > 0) {
          await _syncService.markAdvancesPaidFirestoreFirst(
            _selectedFarmer!.id!,
            _selectedFarmer!.code,
            _dairyId,
          );
        }

        _showSnackBar(_isHindi ? 'भुगतान सफल!' : 'Payment Successful!', isSuccess: true);
      } catch (e) {
        // Firestore write failed — do NOT update UI as success
        _showSnackBar(_isHindi ? 'भुगतान विफल: $e' : 'Payment failed: $e', isError: true);
        return;
      }
      await _loadData(); // Refresh from Firestore
    }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Show Bill Preview
  void _showBillPreview(Map<String, dynamic> bill) {
    if (_selectedFarmer == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          farmer: _selectedFarmer!,
          entries: List<MilkEntry>.from(bill['entries'] as List),
          startDate: _startDate,
          endDate: _endDate,
          totalMilk: (bill['totalMilk'] as num).toDouble(),
          totalAmount: (bill['totalAmount'] as num).toDouble(),
          totalAdvance: (bill['totalAdvance'] as num).toDouble(),
          totalPaid: (bill['paidInPeriod'] as num?)?.toDouble() ?? 0.0,
          lbtAmount: (bill['lbtAmount'] as num?)?.toDouble() ?? 10.0,
          netPayable: (bill['netPayable'] as num).toDouble(),
          dairyName: _dairyName,
        ),
      ),
    );
  }

  Widget _buildConfirmRow(String label, String value, {bool isBold = false, bool isDeduction = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isDeduction ? primaryOrange : (isBold ? primaryGreen : textDark),
          )),
        ],
      ),
    );
  }

  // Add Advance
  Future<void> _addAdvance() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
    if (_advanceFarmer == null) {
      _showSnackBar('Please select a farmer', isError: true);
      return;
    }
    final amount = double.tryParse(_advanceAmountController.text) ?? 0;
    if (amount <= 0) {
      _showSnackBar('Enter valid amount', isError: true);
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryOrange.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.account_balance_wallet_rounded, color: primaryOrange, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isHindi ? 'अग्रिम की पुष्टि करें' : 'Confirm Advance',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isHindi ? 'किसान' : 'Farmer', style: const TextStyle(color: Colors.grey)),
                      Text('${_advanceFarmer!.code} - ${_advanceFarmer!.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isHindi ? 'राशि' : 'Amount', style: const TextStyle(color: Colors.grey)),
                      Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryOrange)),
                    ],
                  ),
                  if (_advanceNotesController.text.isNotEmpty) ...[
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_isHindi ? 'नोट' : 'Notes', style: const TextStyle(color: Colors.grey)),
                        Flexible(child: Text(_advanceNotesController.text, style: const TextStyle(fontWeight: FontWeight.w500), textAlign: TextAlign.end)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isHindi
                  ? 'क्या आप इस किसान को अग्रिम भुगतान देना चाहते हैं?'
                  : 'Are you sure you want to give advance payment to this farmer?',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'हाँ, अग्रिम दें' : 'Yes, Add Advance'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Network check before saving advance
    final hasNet = await hasInternetConnection();
    if (!hasNet && mounted) {
      await showNoInternetDialog(context, isHindi: _isHindi);
      return;
    }

    final payment = Payment(
      farmerId: _advanceFarmer!.id!,
      farmerCode: _advanceFarmer!.code,
      farmerName: _advanceFarmer!.name,
      paymentDate: DateTime.now(),
      type: 'ADVANCE',
      amount: amount,
      netAmount: amount,
      totalLiters: 0,
      paymentMode: 'cash',
      notes: _advanceNotesController.text.isNotEmpty ? _advanceNotesController.text : 'Advance Payment',
      isPaid: false,
    );

    try {
      // FIREBASE-FIRST: Write to Firestore, then cache locally
      await _syncService.addPaymentFirestoreFirst(payment, _dairyId);
    } catch (e) {
      // Firestore write failed — do NOT show success
      if (mounted) {
        _showSnackBar(_isHindi ? 'अग्रिम विफल: $e' : 'Advance failed: $e', isError: true);
      }
      return;
    }

    // Success confirmation dialog
    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryGreen.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_circle_rounded, color: primaryGreen, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isHindi ? 'अग्रिम सफल!' : 'Advance Added!',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_isHindi ? 'किसान' : 'Farmer', style: const TextStyle(color: Colors.grey)),
                    Text('${_advanceFarmer!.code} - ${_advanceFarmer!.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_isHindi ? 'राशि' : 'Amount', style: const TextStyle(color: Colors.grey)),
                    Text('₹${amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryGreen)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              ),
              child: Text(_isHindi ? 'ठीक है' : 'OK'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    _advanceAmountController.clear();
    _advanceNotesController.clear();
    setState(() => _advanceFarmer = null);
    await _loadData(); // await to refresh cached bills immediately
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Bulk payment
  Future<void> _processBulkPayment() async {
    if (_isProcessing) return;
    if (_bulkSelection.isEmpty) {
      _showSnackBar('Select farmers first', isError: true);
      return;
    }
    setState(() => _isProcessing = true);
    try {

    final selectedData = _bulkSelection.map((id) {
      final farmer = _farmers.where((f) => f.id.toString() == id).firstOrNull;
      if (farmer == null) return null;
      final bill = _calculateFarmerBill(farmer.id!);
      return {'farmer': farmer, ...bill};
    }).whereType<Map<String, dynamic>>().where((d) => (d['netPayable'] as num) > 0).toList();

    if (selectedData.isEmpty) {
      _showSnackBar('No outstanding amount for selected farmers', isError: true);
      return;
    }

    final totalPayable = selectedData.fold(0.0, (s, d) => s + (d['netPayable'] as num).toDouble());

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.groups_rounded, color: primaryBlue),
          const SizedBox(width: 10),
          const Text('Bulk Payment'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Process payment for ${selectedData.length} farmers?'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryGreen.withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Total: ', style: TextStyle(fontSize: 18)),
                  Text('₹${totalPayable.toStringAsFixed(0)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryGreen)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            child: const Text('Process All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Network check before bulk payment
      final hasNet = await hasInternetConnection();
      if (!hasNet && mounted) {
        await showNoInternetDialog(context, isHindi: _isHindi);
        return;
      }

      try {
        // FIREBASE-FIRST: Process payments sequentially for safety (not parallel)
        for (final data in selectedData) {
          final farmer = data['farmer'] as Farmer;
          final bill = data;

          // Advance is a running balance (ledger). Record full settlement
          // in amount; advance consumed in advanceDeduction; cash in netAmount.
          final double bTotal = (bill['totalAmount'] as num).toDouble();
          final double bPaid = (bill['paidInPeriod'] as num).toDouble();
          final double bLbt = (bill['lbtAmount'] as num).toDouble();
          final double bAdv = (bill['totalAdvance'] as num).toDouble();
          final double bSettlement = bTotal - bPaid - bLbt;
          final double bCash = (bill['netPayable'] as num).toDouble();

          final payment = Payment(
            farmerId: farmer.id!,
            farmerCode: farmer.code,
            farmerName: farmer.name,
            paymentDate: DateTime.now(),
            fromDate: _startDate,
            toDate: _endDate,
            type: 'PAYMENT',
            amount: bSettlement,
            advanceDeduction: bAdv,
            netAmount: bCash,
            totalLiters: (bill['totalMilk'] as num).toDouble(),
            paymentMode: 'cash',
            notes: 'Bulk Payment: ${DateFormat('dd/MM').format(_startDate)} - ${DateFormat('dd/MM').format(_endDate)}',
          );
          await _syncService.addPaymentFirestoreFirst(payment, _dairyId);

          // Mark advances as consumed
          if (bAdv > 0) {
            await _syncService.markAdvancesPaidFirestoreFirst(
              farmer.id!,
              farmer.code,
              _dairyId,
            );
          }
        }

        _showSnackBar('${selectedData.length} payments processed!', isSuccess: true);
      } catch (e) {
        _showSnackBar(_isHindi ? 'भुगतान विफल: $e' : 'Bulk payment failed: $e', isError: true);
      }
      if (!mounted) return;
      setState(() => _bulkSelection.clear());
      await _loadData();
    }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Delete payment
  Future<void> _deletePayment(Payment p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isHindi ? 'पेमेंट हटाएं?' : 'Delete Payment?',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isHindi ? 'किसान' : 'Farmer', style: const TextStyle(color: Colors.grey)),
                      Text(p.farmerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isHindi ? 'प्रकार' : 'Type', style: const TextStyle(color: Colors.grey)),
                      Text(p.type, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_isHindi ? 'राशि' : 'Amount', style: const TextStyle(color: Colors.grey)),
                      Text('₹${p.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade600)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isHindi
                  ? '⚠️ यह बदलाव पूर्ववत नहीं किया जा सकता!'
                  : '⚠️ This action cannot be undone!',
              style: TextStyle(color: Colors.red.shade600, fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'हाँ, हटाएं' : 'Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_isProcessing) return;
      setState(() => _isProcessing = true);
      try {
      final hasNet = await hasInternetConnection();
      if (!hasNet && mounted) {
        await showNoInternetDialog(context, isHindi: _isHindi);
        return;
      }
      try {
        await _syncService.deletePaymentFirestoreFirst(p, _dairyId);
        _showSnackBar(_isHindi ? 'पेमेंट हटाया गया' : 'Payment deleted', isSuccess: true);
      } catch (e) {
        _showSnackBar(_isHindi ? 'हटाने में त्रुटि: $e' : 'Delete failed: $e', isError: true);
        return;
      }
      await _loadData();
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _editPayment(Payment p) async {
    final amountController = TextEditingController(text: p.amount.toStringAsFixed(0));
    final notesController = TextEditingController(text: p.notes ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryBlue.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.edit_rounded, color: primaryBlue, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isHindi ? 'पेमेंट एडिट करें' : 'Edit Payment',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(p.farmerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(p.type, style: TextStyle(fontSize: 11, color: p.type == 'PAYMENT' ? primaryGreen : primaryOrange, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(_isHindi ? 'राशि' : 'Amount', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: bgColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: Icon(Icons.currency_rupee_rounded, color: primaryGreen),
              ),
            ),
            const SizedBox(height: 12),
            Text(_isHindi ? 'नोट' : 'Notes', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                filled: true,
                fillColor: bgColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: Icon(Icons.notes_rounded, color: Colors.grey.shade500),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final newAmount = double.tryParse(amountController.text) ?? 0;
              if (newAmount <= 0) {
                _showSnackBar(_isHindi ? 'सही राशि दर्ज करें' : 'Enter valid amount', isError: true);
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'अपडेट करें' : 'Update'),
          ),
        ],
      ),
    );

    if (result == true) {
      if (_isProcessing) return;
      setState(() => _isProcessing = true);
      try {
      final newAmount = double.tryParse(amountController.text) ?? p.amount;
      final updatedPayment = Payment(
        id: p.id,
        farmerId: p.farmerId,
        farmerCode: p.farmerCode,
        farmerName: p.farmerName,
        paymentDate: p.paymentDate,
        fromDate: p.fromDate,
        toDate: p.toDate,
        type: p.type,
        amount: newAmount,
        advanceDeduction: p.advanceDeduction,
        netAmount: p.type == 'PAYMENT' ? (newAmount - p.advanceDeduction) : newAmount,
        totalLiters: p.totalLiters,
        paymentMode: p.paymentMode,
        notes: notesController.text.isNotEmpty ? notesController.text : p.notes,
        isPaid: p.isPaid,
      );
      await _syncService.updatePaymentFirestoreFirst(updatedPayment, _dairyId);
      _showSnackBar(_isHindi ? 'पेमेंट अपडेट हुआ' : 'Payment updated', isSuccess: true);
      await _loadData();
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
    amountController.dispose();
    notesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: Text(_isHindi ? 'पेमेंट मैनेजर' : 'Payment Manager', style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryGreen,
          indicatorWeight: 3,
          labelColor: primaryGreen,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded, size: 20), text: 'Bill'),
            Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 20), text: 'Advance'),
            Tab(icon: Icon(Icons.groups_rounded, size: 20), text: 'Bulk'),
            Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryGreen))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildBillTab(),
                _buildAdvanceTab(),
                _buildBulkTab(),
                _buildHistoryTab(),
              ],
            ),
    );
  }

  // ==================== BILL TAB ====================
  Widget _buildBillTab() {
    final bill = _selectedFarmer != null ? _getCachedBill(_selectedFarmer!.id!) : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Farmer Dropdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isHindi ? 'किसान चुनें' : 'Select Farmer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 10),
                DropdownButtonFormField<Farmer>(
                  initialValue: _selectedFarmer,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    prefixIcon: Icon(Icons.person_rounded, color: primaryGreen),
                  ),
                  hint: const Text('Choose farmer...'),
                  items: _farmers.map((f) => DropdownMenuItem(value: f, child: Text('${f.code} - ${f.name}'))).toList(),
                  onChanged: (f) => setState(() => _selectedFarmer = f),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Date Range Selection
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isHindi ? 'बिलिंग अवधि' : 'Billing Period', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 12),
                // Quick Cycle Buttons
                Row(
                  children: [
                    _buildCycleChip('10 Days', '10_DAYS'),
                    const SizedBox(width: 8),
                    _buildCycleChip('15 Days', '15_DAYS'),
                    const SizedBox(width: 8),
                    _buildCycleChip('Month', 'MONTH'),
                  ],
                ),
                const SizedBox(height: 12),
                // Custom Date
                GestureDetector(
                  onTap: _selectCustomDateRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _selectedCycle == 'CUSTOM' ? primaryGreen.withAlpha(26) : bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _selectedCycle == 'CUSTOM' ? primaryGreen : Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.date_range_rounded, color: primaryGreen, size: 20),
                        const SizedBox(width: 10),
                        Text('${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Icon(Icons.edit_calendar_rounded, color: Colors.grey.shade500, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Bill Summary
          if (_selectedFarmer != null && bill != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.summarize_rounded, color: primaryBlue),
                      const SizedBox(width: 8),
                      const Text('Bill Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const Divider(height: 20),
                  _buildSummaryRow(_isHindi ? 'कुल दूध' : 'Total Milk', '${(bill['totalMilk'] as num).toStringAsFixed(1)} Ltr'),
                  _buildSummaryRow(_isHindi ? 'कुल राशि' : 'Total Amount', '₹${(bill['totalAmount'] as num).toStringAsFixed(0)}'),
                  if ((bill['totalAdvance'] as num) > 0)
                    _buildSummaryRow(_isHindi ? 'अग्रिम कटौती' : 'Less Advance', '-₹${(bill['totalAdvance'] as num).toStringAsFixed(0)}', isDeduction: true),
                  if ((bill['paidInPeriod'] as num? ?? 0) > 0)
                    _buildSummaryRow(_isHindi ? 'भुगतान कटौती' : 'Less Paid', '-₹${(bill['paidInPeriod'] as num).toStringAsFixed(0)}', isDeduction: true),
                  if ((bill['lbtAmount'] as num? ?? 0) > 0)
                    _buildSummaryRow(_isHindi ? 'LBT कटौती' : 'Less LBT', '-₹${(bill['lbtAmount'] as num).toStringAsFixed(0)}', isDeduction: true),
                  const Divider(height: 16),
                  _buildSummaryRow(_isHindi ? 'देय राशि' : 'Net Payable', '₹${(bill['netPayable'] as num).toStringAsFixed(0)}', isBold: true, isGreen: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Preview & Pay Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showBillPreview(bill),
                    icon: Icon(Icons.visibility_rounded, color: primaryBlue),
                    label: const Text('Preview'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryBlue,
                      side: BorderSide(color: primaryBlue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (bill['netPayable'] as num) > 0 ? _processPayment : null,
                    icon: const Icon(Icons.payment_rounded, color: Colors.white),
                    label: Text('Pay ₹${(bill['netPayable'] as num).toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCycleChip(String label, String value) {
    final isActive = _selectedCycle == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setDateRange(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? primaryGreen : bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isActive ? primaryGreen : Colors.grey.shade300),
          ),
          child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: isActive ? Colors.white : textDark))),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false, bool isGreen = false, bool isDeduction = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Text(value, style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isDeduction ? primaryOrange : (isGreen ? primaryGreen : textDark),
          )),
        ],
      ),
    );
  }

  // ==================== ADVANCE TAB ====================
  Widget _buildAdvanceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 8)]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: primaryOrange.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                      child: Icon(Icons.account_balance_wallet_rounded, color: primaryOrange, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add Advance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text(_isHindi ? 'अग्रिम भुगतान जोड़ें' : 'Add Advance Payment', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Farmer Dropdown
                Text(_isHindi ? 'किसान' : 'Farmer', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Farmer>(
                  initialValue: _advanceFarmer,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  hint: const Text('Select farmer...'),
                  items: _farmers.map((f) => DropdownMenuItem(value: f, child: Text('${f.code} - ${f.name}'))).toList(),
                  onChanged: (f) => setState(() => _advanceFarmer = f),
                ),
                const SizedBox(height: 16),

                // Amount
                Text(_isHindi ? 'राशि' : 'Amount', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _advanceAmountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.currency_rupee_rounded, color: primaryOrange),
                    hintText: 'Enter amount',
                  ),
                ),
                const SizedBox(height: 16),

                // Notes
                Text(_isHindi ? 'नोट (वैकल्पिक)' : 'Notes (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: _advanceNotesController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    prefixIcon: Icon(Icons.notes_rounded, color: Colors.grey.shade500),
                    hintText: 'Add notes...',
                  ),
                ),
                const SizedBox(height: 24),

                // Add Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _addAdvance,
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                    label: Text(_isHindi ? 'अग्रिम जोड़ें' : 'Add Advance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: primaryOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Recent Advances
          Row(
            children: [
              Icon(Icons.history_rounded, color: primaryOrange, size: 20),
              const SizedBox(width: 8),
              const Text('Recent Advances', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),

          ..._payments.where((p) => p.type == 'ADVANCE').take(5).map((p) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.isPaid == true ? Colors.green.withAlpha(26) : primaryOrange.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                  child: Icon(p.isPaid == true ? Icons.check_circle_rounded : Icons.schedule_rounded, color: p.isPaid == true ? primaryGreen : primaryOrange, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.farmerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(DateFormat('dd/MM/yy').format(p.paymentDate), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Text('₹${p.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryOrange)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  // ==================== BULK TAB ====================
  Widget _buildBulkTab() {
    final bulkData = _farmers.map((f) {
      final bill = _getCachedBill(f.id!);
      return {'farmer': f, ...bill};
    }).toList();

    final totalPayable = bulkData
        .where((d) => _bulkSelection.contains((d['farmer'] as Farmer).id.toString()))
        .fold(0.0, (s, d) => s + ((d['netPayable'] as num) > 0 ? (d['netPayable'] as num).toDouble() : 0.0));

    return Column(
      children: [
        // Header with Date Range
        Container(
          color: cardColor,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              GestureDetector(
                onTap: _selectCustomDateRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.date_range_rounded, color: primaryBlue, size: 20),
                      const SizedBox(width: 10),
                      Text('${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Icon(Icons.edit_calendar_rounded, color: Colors.grey.shade500, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_bulkSelection.length == _farmers.length) {
                        setState(() => _bulkSelection.clear());
                      } else {
                        setState(() => _bulkSelection = _farmers.map((f) => f.id.toString()).toList());
                      }
                    },
                    child: Row(
                      children: [
                        Icon(
                          _bulkSelection.length == _farmers.length ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          color: primaryBlue,
                        ),
                        const SizedBox(width: 8),
                        Text('Select All (${_bulkSelection.length}/${_farmers.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('Total: ₹${totalPayable.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: primaryGreen, fontSize: 16)),
                ],
              ),
            ],
          ),
        ),

        // Farmer List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: bulkData.length,
            itemBuilder: (context, index) {
              final data = bulkData[index];
              final farmer = data['farmer'] as Farmer;
              final netPayable = (data['netPayable'] as num).toDouble();
              final isSelected = _bulkSelection.contains(farmer.id.toString());

              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    if (isSelected) {
                      _bulkSelection.remove(farmer.id.toString());
                    } else {
                      _bulkSelection.add(farmer.id.toString());
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryBlue.withAlpha(13) : cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? primaryBlue : Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: isSelected ? primaryBlue : Colors.grey.shade400),
                      const SizedBox(width: 12),
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: primaryGreen, borderRadius: BorderRadius.circular(8)),
                        child: Center(child: Text(farmer.code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(farmer.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${(data['totalMilk'] as num).toStringAsFixed(1)}L • ₹${(data['totalAmount'] as num).toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      Text(
                        netPayable > 0 ? '₹${netPayable.toStringAsFixed(0)}' : 'Paid',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: netPayable > 0 ? primaryGreen : Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Pay All Button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cardColor, boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, -2))]),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _bulkSelection.isNotEmpty ? _processBulkPayment : null,
              icon: const Icon(Icons.payment_rounded, color: Colors.white),
              label: Text('Pay ${_bulkSelection.length} Farmers • ₹${totalPayable.toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), disabledBackgroundColor: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== HISTORY TAB ====================
  Widget _buildHistoryTab() {
    var filteredPayments = _payments.where((p) {
      final matchType = _historyFilter == 'ALL' || p.type == _historyFilter;
      final matchSearch = _historySearch.isEmpty || p.farmerName.toLowerCase().contains(_historySearch.toLowerCase());
      return matchType && matchSearch;
    }).toList();

    filteredPayments.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    return Column(
      children: [
        // Filters
        Container(
          color: cardColor,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Search
              TextField(
                onChanged: (v) => setState(() => _historySearch = v),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: bgColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade500),
                  hintText: 'Search farmer...',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              // Filter Chips
              Row(
                children: [
                  _buildHistoryChip('All', 'ALL'),
                  const SizedBox(width: 8),
                  _buildHistoryChip('Payments', 'PAYMENT'),
                  const SizedBox(width: 8),
                  _buildHistoryChip('Advances', 'ADVANCE'),
                ],
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: filteredPayments.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.history_rounded, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No records found', style: TextStyle(color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredPayments.length,
                  itemBuilder: (context, index) {
                    final p = filteredPayments[index];
                    final isPayment = p.type == 'PAYMENT';
                    return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isPayment ? Colors.green.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: isPayment ? primaryGreen.withAlpha(26) : primaryOrange.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                              child: Icon(isPayment ? Icons.check_circle_rounded : Icons.account_balance_wallet_rounded, color: isPayment ? primaryGreen : primaryOrange),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.farmerName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text('${DateFormat('dd/MM/yy').format(p.paymentDate)} • ${p.type}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  if (p.notes != null && p.notes!.isNotEmpty)
                                    Text(p.notes!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${isPayment ? '+' : '-'}₹${p.amount.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isPayment ? primaryGreen : primaryOrange)),
                                if (isPayment && p.advanceDeduction > 0)
                                  Text('Adv: -₹${p.advanceDeduction.toStringAsFixed(0)}', style: TextStyle(fontSize: 10, color: primaryOrange)),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Material(
                                      color: primaryBlue.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => _editPayment(p),
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(Icons.edit_rounded, size: 16, color: primaryBlue),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Material(
                                      color: Colors.red.withAlpha(20),
                                      borderRadius: BorderRadius.circular(6),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () => _deletePayment(p),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red.shade400),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryChip(String label, String value) {
    final isActive = _historyFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _historyFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? primaryBlue : bgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: isActive ? Colors.white : textDark))),
        ),
      ),
    );
  }
}
