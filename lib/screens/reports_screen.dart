import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../models/milk_entry.dart';
import '../models/farmer.dart';
import '../models/payment.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _db = DatabaseHelper.instance;
  bool _isLoading = true;
  int? _dairyId;
  String _dairyName = 'Dudh Passbook';

  // Data
  List<MilkEntry> _allEntries = [];
  List<Farmer> _allFarmers = [];
  List<Payment> _allPayments = [];
  Map<int, double> _pendingAmounts = {}; // farmerId -> pending amount (SQL computed)
  bool _isExporting = false; // Double-tap guard for exports

  // Cached computations (recalculated in _recomputeSummaries, NOT in build)
  List<Map<String, dynamic>> _cachedFarmerSummaries = [];
  double _cachedTotalMilk = 0.0;
  double _cachedTotalAmount = 0.0;
  double _cachedTotalPending = 0.0;

  // Main Filters
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // View Mode
  bool _showFarmerDetail = false;
  Farmer? _selectedFarmer;
  List<MilkEntry> _detailFarmerEntries = []; // loaded for selected farmer only
  List<Payment> _detailFarmerPayments = []; // loaded for selected farmer only

  // Detail View Filters
  String _detailDateFilter = 'all';
  DateTime? _detailCustomStart;
  DateTime? _detailCustomEnd;

  // Language
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme-aware colors
  bool get _isDark =>
      mounted && context.mounted
          ? Theme.of(context).brightness == Brightness.dark
          : false;
  Color get primaryGreen =>
      _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark =>
      _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get primaryOrange =>
      _isDark ? const Color(0xFFFF8A65) : const Color(0xFFEF6C00);
  Color get bgColor =>
      _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor =>
      _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark =>
      _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight =>
      _isDark ? Colors.white70 : const Color(0xFF666666);
  Color get dividerColor =>
      _isDark ? Colors.white12 : Colors.grey.shade200;
  Color get chipBg =>
      _isDark ? Colors.white10 : Colors.grey.shade100;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _dairyId = prefs.getInt('dairyId');
      _dairyName = prefs.getString('dairyName') ?? 'Dudh Passbook';
      _languageCode = prefs.getString('language_code') ?? 'hi';

      _allFarmers = await _db.getAllFarmers(dairyId: _dairyId);
      // Load ONLY entries within the selected date range to prevent OOM
      _allEntries = await _db.getMilkEntries(
        dairyId: _dairyId,
        startDate: _startDate,
        endDate: _endDate.add(const Duration(days: 1)), // inclusive end
      );
      _allPayments = await _db.getPayments(dairyId: _dairyId);
      // Compute pending amounts efficiently via SQL (no full history load)
      _pendingAmounts = await _db.getPendingAmountsForAllFarmers(dairyId: _dairyId);
      // Cache heavy computations once (NOT on every build)
      _recomputeSummaries();
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', isError: true);
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ========== COMPUTED DATA ==========

  // Entries are already date-bounded from the DB query
  List<MilkEntry> get _filteredEntries => _allEntries;

  /// Recompute summaries — called ONCE after data load, NOT on every build()
  void _recomputeSummaries() {
    final Map<int, Map<String, dynamic>> summaryMap = {};

    for (var entry in _filteredEntries) {
      if (!summaryMap.containsKey(entry.farmerId)) {
        final farmer = _allFarmers.firstWhere(
          (f) => f.id == entry.farmerId,
          orElse: () => Farmer(
              code: entry.farmerCode,
              name: entry.farmerName,
              mobile: '',
              cattleType: 'buffalo'),
        );
        summaryMap[entry.farmerId] = {
          'farmer': farmer,
          'code': entry.farmerCode,
          'name': entry.farmerName,
          'milk': 0.0,
          'amount': 0.0,
          'entries': 0,
          'pending': 0.0,
          'avgFat': 0.0,
          'avgRate': 0.0,
        };
      }
      summaryMap[entry.farmerId]!['milk'] += entry.quantity;
      summaryMap[entry.farmerId]!['amount'] += entry.amount;
      summaryMap[entry.farmerId]!['entries'] += 1;
    }

    // Calculate pending & averages
    for (var farmerId in summaryMap.keys) {
      final filteredEntries =
          _filteredEntries.where((e) => e.farmerId == farmerId).toList();
      summaryMap[farmerId]!['pending'] = _pendingAmounts[farmerId] ?? 0.0;

      if (filteredEntries.isNotEmpty) {
        summaryMap[farmerId]!['avgFat'] =
            filteredEntries.fold(0.0, (s, e) => s + e.fat) /
                filteredEntries.length;
        summaryMap[farmerId]!['avgRate'] =
            filteredEntries.fold(0.0, (s, e) => s + e.rate) /
                filteredEntries.length;
      }
    }

    var result = summaryMap.values.toList();
    result.sort((a, b) =>
        (int.tryParse(a['code']) ?? 0).compareTo(int.tryParse(b['code']) ?? 0));

    _cachedFarmerSummaries = result;
    _cachedTotalMilk = _filteredEntries.fold(0.0, (s, e) => s + e.quantity);
    _cachedTotalAmount = _filteredEntries.fold(0.0, (s, e) => s + e.amount);
    _cachedTotalPending = result.fold(0.0, (s, f) => s + (f['pending'] as double));
  }

  /// Lightweight search filter applied to cached summaries (safe to call in build)
  List<Map<String, dynamic>> get _farmerSummaries {
    if (_searchQuery.isEmpty) return _cachedFarmerSummaries;
    return _cachedFarmerSummaries.where((s) {
      return (s['name'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (s['code'] as String).contains(_searchQuery);
    }).toList();
  }

  double get _totalMilk => _cachedTotalMilk;
  double get _totalAmount => _cachedTotalAmount;
  double get _totalPending => _cachedTotalPending;

  // ========== DATE PICKERS ==========

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: primaryGreen),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      // Reload data for the new date range from DB
      _loadData();
    }
  }

  Future<void> _showFarmerLedger(Farmer farmer) async {
    // Load entries for this specific farmer from DB (safe for memory — single farmer)
    final entries = await _db.getMilkEntries(
      farmerId: farmer.id,
      dairyId: _dairyId,
    );
    final payments = await _db.getPayments(
      farmerId: farmer.id,
      dairyId: _dairyId,
    );
    if (!mounted) return;
    setState(() {
      _selectedFarmer = farmer;
      _showFarmerDetail = true;
      _detailFarmerEntries = entries;
      _detailFarmerPayments = payments;
      _detailDateFilter = 'all';
      _detailCustomStart = null;
      _detailCustomEnd = null;
    });
  }

  void _backToList() {
    setState(() {
      _showFarmerDetail = false;
      _selectedFarmer = null;
    });
  }

  List<MilkEntry> _getDetailEntries() {
    if (_selectedFarmer == null) return [];
    var entries = List<MilkEntry>.from(_detailFarmerEntries);

    final now = DateTime.now();
    DateTime? filterStart;

    switch (_detailDateFilter) {
      case '7days':
        filterStart = now.subtract(const Duration(days: 7));
        break;
      case '30days':
        filterStart = now.subtract(const Duration(days: 30));
        break;
      case '3months':
        filterStart = DateTime(now.year, now.month - 3, 1);
        break;
      case 'custom':
        if (_detailCustomStart != null && _detailCustomEnd != null) {
          entries = entries
              .where((e) =>
                  e.dateTime.isAfter(
                      _detailCustomStart!.subtract(const Duration(days: 1))) &&
                  e.dateTime.isBefore(
                      _detailCustomEnd!.add(const Duration(days: 1))))
              .toList();
        }
        break;
    }

    if (filterStart != null) {
      entries =
          entries.where((e) => e.dateTime.isAfter(filterStart!)).toList();
    }

    entries.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return entries;
  }

  List<Payment> _getDetailPayments() {
    if (_selectedFarmer == null) return [];
    var payments = List<Payment>.from(_detailFarmerPayments);

    final now = DateTime.now();
    DateTime? filterStart;

    switch (_detailDateFilter) {
      case '7days':
        filterStart = now.subtract(const Duration(days: 7));
        break;
      case '30days':
        filterStart = now.subtract(const Duration(days: 30));
        break;
      case '3months':
        filterStart = DateTime(now.year, now.month - 3, 1);
        break;
      case 'custom':
        if (_detailCustomStart != null && _detailCustomEnd != null) {
          payments = payments
              .where((p) =>
                  p.paymentDate.isAfter(
                      _detailCustomStart!.subtract(const Duration(days: 1))) &&
                  p.paymentDate.isBefore(
                      _detailCustomEnd!.add(const Duration(days: 1))))
              .toList();
        }
        break;
    }

    if (filterStart != null) {
      payments =
          payments.where((p) => p.paymentDate.isAfter(filterStart!)).toList();
    }

    payments.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return payments;
  }

  Future<void> _selectDetailDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _detailCustomStart != null && _detailCustomEnd != null
          ? DateTimeRange(start: _detailCustomStart!, end: _detailCustomEnd!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 30)),
              end: DateTime.now()),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: primaryGreen)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _detailDateFilter = 'custom';
        _detailCustomStart = picked.start;
        _detailCustomEnd = picked.end;
      });
    }
  }

  // ========== EXPORT METHODS ==========

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isHindi ? 'रिपोर्ट डाउनलोड करें' : 'Download Report',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                  style: TextStyle(fontSize: 13, color: textLight),
                ),
                const SizedBox(height: 24),

                // Excel Export
                _buildExportOption(
                  icon: Icons.table_chart_rounded,
                  color: const Color(0xFF217346),
                  title: _isHindi ? 'Excel फ़ाइल (.xlsx)' : 'Excel File (.xlsx)',
                  subtitle: _isHindi
                      ? 'सभी किसानों की दूध एंट्री और पेमेंट डेटा'
                      : 'All farmers milk entry & payment data',
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportToExcel();
                  },
                ),
                const SizedBox(height: 12),

                // PDF Export
                _buildExportOption(
                  icon: Icons.picture_as_pdf_rounded,
                  color: const Color(0xFFD32F2F),
                  title: _isHindi ? 'PDF फ़ाइल (.pdf)' : 'PDF File (.pdf)',
                  subtitle: _isHindi
                      ? 'प्रिंट-रेडी समरी रिपोर्ट'
                      : 'Print-ready summary report',
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportToPdf();
                  },
                ),
                const SizedBox(height: 12),

                // PDF Preview / Print
                _buildExportOption(
                  icon: Icons.print_rounded,
                  color: Colors.blue.shade700,
                  title: _isHindi ? 'प्रिंट / प्रीव्यू' : 'Print / Preview',
                  subtitle: _isHindi
                      ? 'PDF प्रीव्यू देखें और प्रिंट करें'
                      : 'Preview PDF and print directly',
                  onTap: () {
                    Navigator.pop(ctx);
                    _printPdf();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(_isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
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
                    style: TextStyle(fontSize: 12, color: textLight),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }

  // ========== EXCEL EXPORT ==========
  Future<void> _exportToExcel() async {
    if (_isExporting) return;
    _isExporting = true;
    try {
      _showSnackBar(
          _isHindi ? 'Excel फ़ाइल बन रही है...' : 'Generating Excel file...',
          isError: false);

      final excel = xl.Excel.createExcel();
      final dateRange =
          '${DateFormat('dd-MM-yyyy').format(_startDate)} to ${DateFormat('dd-MM-yyyy').format(_endDate)}';

      // ===== Sheet 1: Farmer Summary =====
      final summarySheet = excel['Farmer Summary'];
      excel.setDefaultSheet('Farmer Summary');

      // Header row
      summarySheet.appendRow([
        xl.TextCellValue(_dairyName),
      ]);
      summarySheet.appendRow([
        xl.TextCellValue('Report Period: $dateRange'),
      ]);
      summarySheet.appendRow([]); // Empty row

      // Column headers
      summarySheet.appendRow([
        xl.TextCellValue('Code'),
        xl.TextCellValue('Farmer Name'),
        xl.TextCellValue('Entries'),
        xl.TextCellValue('Total Milk (Ltr)'),
        xl.TextCellValue('Avg FAT %'),
        xl.TextCellValue('Avg Rate (₹)'),
        xl.TextCellValue('Total Amount (₹)'),
        xl.TextCellValue('Pending (₹)'),
      ]);

      // Data rows
      for (var s in _farmerSummaries) {
        summarySheet.appendRow([
          xl.TextCellValue(s['code'] as String),
          xl.TextCellValue(s['name'] as String),
          xl.IntCellValue(s['entries'] as int),
          xl.DoubleCellValue(
              double.parse((s['milk'] as double).toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse((s['avgFat'] as double).toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse((s['avgRate'] as double).toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse((s['amount'] as double).toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse((s['pending'] as double).toStringAsFixed(2))),
        ]);
      }

      // Total row
      summarySheet.appendRow([
        xl.TextCellValue(''),
        xl.TextCellValue('TOTAL'),
        xl.IntCellValue(_filteredEntries.length),
        xl.DoubleCellValue(
            double.parse(_totalMilk.toStringAsFixed(2))),
        xl.TextCellValue(''),
        xl.TextCellValue(''),
        xl.DoubleCellValue(
            double.parse(_totalAmount.toStringAsFixed(2))),
        xl.DoubleCellValue(
            double.parse(_totalPending.toStringAsFixed(2))),
      ]);

      // ===== Sheet 2: All Entries =====
      final entriesSheet = excel['Milk Entries'];
      entriesSheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Shift'),
        xl.TextCellValue('Code'),
        xl.TextCellValue('Farmer Name'),
        xl.TextCellValue('Cattle'),
        xl.TextCellValue('Qty (Ltr)'),
        xl.TextCellValue('FAT %'),
        xl.TextCellValue('SNF %'),
        xl.TextCellValue('Rate (₹)'),
        xl.TextCellValue('Amount (₹)'),
      ]);

      final sortedEntries = List<MilkEntry>.from(_filteredEntries)
        ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

      for (var e in sortedEntries) {
        entriesSheet.appendRow([
          xl.TextCellValue(DateFormat('dd/MM/yyyy').format(e.dateTime)),
          xl.TextCellValue(e.shift == 'morning' ? 'Morning' : 'Evening'),
          xl.TextCellValue(e.farmerCode),
          xl.TextCellValue(e.farmerName),
          xl.TextCellValue(e.cattleType == 'buffalo' ? 'Buffalo' : 'Cow'),
          xl.DoubleCellValue(
              double.parse(e.quantity.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(e.fat.toStringAsFixed(2))),
          xl.DoubleCellValue(e.snf != null
              ? double.parse(e.snf!.toStringAsFixed(2))
              : 0.0),
          xl.DoubleCellValue(
              double.parse(e.rate.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(e.amount.toStringAsFixed(2))),
        ]);
      }

      // ===== Sheet 3: Payments =====
      final paymentsSheet = excel['Payments'];
      paymentsSheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Code'),
        xl.TextCellValue('Farmer Name'),
        xl.TextCellValue('Type'),
        xl.TextCellValue('Total Liters'),
        xl.TextCellValue('Amount (₹)'),
        xl.TextCellValue('Advance Ded. (₹)'),
        xl.TextCellValue('Net Amount (₹)'),
        xl.TextCellValue('Mode'),
      ]);

      final sortedPayments = List<Payment>.from(_allPayments)
        ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

      for (var p in sortedPayments) {
        paymentsSheet.appendRow([
          xl.TextCellValue(DateFormat('dd/MM/yyyy').format(p.paymentDate)),
          xl.TextCellValue(p.farmerCode),
          xl.TextCellValue(p.farmerName),
          xl.TextCellValue(p.type),
          xl.DoubleCellValue(
              double.parse(p.totalLiters.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(p.amount.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(p.advanceDeduction.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(p.netAmount.toStringAsFixed(2))),
          xl.TextCellValue(p.paymentMode.toUpperCase()),
        ]);
      }

      // Remove default sheet if exists
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Save file
      final bytes = excel.save();
      if (bytes == null) {
        _showSnackBar('Failed to generate Excel', isError: true);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'DairyReport_${DateFormat('ddMMyy').format(_startDate)}_${DateFormat('ddMMyy').format(_endDate)}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;

      // Share file
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$_dairyName - Report',
        text:
            'Dairy Report: ${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
      );

      _showSnackBar(
          _isHindi ? '✅ Excel फ़ाइल तैयार!' : '✅ Excel file ready!',
          isError: false);
    } catch (e) {
      _showSnackBar('Excel Error: $e', isError: true);
    } finally {
      _isExporting = false;
    }
  }

  // ========== PDF EXPORT ==========
  Future<pw.Document> _buildPdfDocument() async {
    final pdf = pw.Document();
    final dateRange =
        '${DateFormat('dd/MM/yyyy').format(_startDate)} - ${DateFormat('dd/MM/yyyy').format(_endDate)}';

    // Load font
    final fontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    pw.Font? hindiFont;
    pw.Font? hindiBoldFont;
    try {
      hindiFont = pw.Font.ttf(fontData);
      hindiBoldFont = pw.Font.ttf(boldFontData);
    } catch (_) {
      hindiFont = null;
      hindiBoldFont = null;
    }

    final fontFallbackList = hindiFont != null ? [hindiFont] : <pw.Font>[];

    final headerStyle = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      font: hindiBoldFont,
      fontFallback: fontFallbackList,
    );
    final cellStyle = pw.TextStyle(
      fontSize: 7,
      font: hindiFont,
      fontFallback: fontFallbackList,
    );
    final titleStyle = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      font: hindiBoldFont,
      fontFallback: fontFallbackList,
    );
    final subtitleStyle = pw.TextStyle(
      fontSize: 9,
      color: PdfColors.grey600,
      font: hindiFont,
      fontFallback: fontFallbackList,
    );

    final summaries = _farmerSummaries;

    // Page 1: Summary
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(_dairyName, style: titleStyle),
                pw.Text(dateRange, style: subtitleStyle),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(color: PdfColors.green800, thickness: 1.5),
            pw.SizedBox(height: 8),
            // Stats row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfStatBox('Farmers', '${summaries.length}', headerStyle, cellStyle),
                _pdfStatBox('Entries', '${_filteredEntries.length}', headerStyle, cellStyle),
                _pdfStatBox('Total Milk', '${_totalMilk.toStringAsFixed(1)} Ltr', headerStyle, cellStyle),
                _pdfStatBox('Total Amount', '₹${_totalAmount.toStringAsFixed(0)}', headerStyle, cellStyle),
                _pdfStatBox('Pending', '₹${_totalPending.toStringAsFixed(0)}', headerStyle, cellStyle),
              ],
            ),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          ],
        ),
        build: (context) {
          return [
            pw.Text('Farmer Summary', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: hindiBoldFont)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: headerStyle,
              cellStyle: cellStyle,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.green50),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              headers: [
                '#',
                'Farmer',
                'Entries',
                'Milk (Ltr)',
                'Avg FAT',
                'Amount',
                'Pending'
              ],
              data: [
                ...summaries.map((s) => [
                      s['code'],
                      s['name'],
                      '${s['entries']}',
                      (s['milk'] as double).toStringAsFixed(1),
                      '${(s['avgFat'] as double).toStringAsFixed(1)}%',
                      '₹${(s['amount'] as double).toStringAsFixed(0)}',
                      '₹${(s['pending'] as double).toStringAsFixed(0)}',
                    ]),
                // Total row
                [
                  '',
                  'TOTAL',
                  '${_filteredEntries.length}',
                  _totalMilk.toStringAsFixed(1),
                  '',
                  '₹${_totalAmount.toStringAsFixed(0)}',
                  '₹${_totalPending.toStringAsFixed(0)}',
                ],
              ],
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  pw.Widget _pdfStatBox(
      String label, String value, pw.TextStyle headerStyle, pw.TextStyle cellStyle) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(value, style: headerStyle),
          pw.SizedBox(height: 2),
          pw.Text(label, style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
        ],
      ),
    );
  }

  Future<void> _exportToPdf() async {
    if (_isExporting) return;
    _isExporting = true;
    try {
      _showSnackBar(
          _isHindi ? 'PDF फ़ाइल बन रही है...' : 'Generating PDF file...',
          isError: false);

      final pdf = await _buildPdfDocument();
      final bytes = await pdf.save();

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'DairyReport_${DateFormat('ddMMyy').format(_startDate)}_${DateFormat('ddMMyy').format(_endDate)}.pdf';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$_dairyName - Report',
        text:
            'Dairy Report: ${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
      );

      _showSnackBar(
          _isHindi ? '✅ PDF फ़ाइल तैयार!' : '✅ PDF file ready!',
          isError: false);
    } catch (e) {
      _showSnackBar('PDF Error: $e', isError: true);
    } finally {
      _isExporting = false;
    }
  }

  Future<void> _printPdf() async {
    try {
      final pdf = await _buildPdfDocument();
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: '$_dairyName Report',
      );
    } catch (e) {
      _showSnackBar('Print Error: $e', isError: true);
    }
  }

  // ========== FARMER DETAIL EXPORT ==========
  void _showFarmerExportMenu() {
    if (_selectedFarmer == null) return;
    final farmer = _selectedFarmer!;
    final entries = _getDetailEntries();
    final payments = _getDetailPayments();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '${farmer.name} - ${_isHindi ? 'रिपोर्ट डाउनलोड' : 'Download Report'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 20),
                _buildExportOption(
                  icon: Icons.table_chart_rounded,
                  color: const Color(0xFF217346),
                  title: 'Excel (.xlsx)',
                  subtitle: '${entries.length} entries, ${payments.length} payments',
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportFarmerExcel(farmer, entries, payments);
                  },
                ),
                const SizedBox(height: 12),
                _buildExportOption(
                  icon: Icons.picture_as_pdf_rounded,
                  color: const Color(0xFFD32F2F),
                  title: 'PDF (.pdf)',
                  subtitle: _isHindi
                      ? 'किसान लेजर रिपोर्ट'
                      : 'Farmer ledger report',
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportFarmerPdf(farmer, entries, payments);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportFarmerExcel(
      Farmer farmer, List<MilkEntry> entries, List<Payment> payments) async {
    if (_isExporting) return;
    _isExporting = true;
    try {
      _showSnackBar(
          _isHindi ? 'Excel बन रही है...' : 'Generating Excel...',
          isError: false);

      final excel = xl.Excel.createExcel();

      // Entries Sheet
      final entrySheet = excel['Entries'];
      excel.setDefaultSheet('Entries');
      entrySheet.appendRow([
        xl.TextCellValue('${farmer.name} (${farmer.code}) - Milk Entries'),
      ]);
      entrySheet.appendRow([]);
      entrySheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Shift'),
        xl.TextCellValue('Cattle'),
        xl.TextCellValue('Qty (Ltr)'),
        xl.TextCellValue('FAT %'),
        xl.TextCellValue('SNF %'),
        xl.TextCellValue('Rate'),
        xl.TextCellValue('Amount'),
      ]);
      for (var e in entries) {
        entrySheet.appendRow([
          xl.TextCellValue(DateFormat('dd/MM/yyyy').format(e.dateTime)),
          xl.TextCellValue(e.shift == 'morning' ? 'Morning' : 'Evening'),
          xl.TextCellValue(e.cattleType == 'buffalo' ? 'Buffalo' : 'Cow'),
          xl.DoubleCellValue(double.parse(e.quantity.toStringAsFixed(2))),
          xl.DoubleCellValue(double.parse(e.fat.toStringAsFixed(2))),
          xl.DoubleCellValue(
              e.snf != null ? double.parse(e.snf!.toStringAsFixed(2)) : 0.0),
          xl.DoubleCellValue(double.parse(e.rate.toStringAsFixed(2))),
          xl.DoubleCellValue(double.parse(e.amount.toStringAsFixed(2))),
        ]);
      }

      // Payments Sheet
      final paySheet = excel['Payments'];
      paySheet.appendRow([
        xl.TextCellValue('${farmer.name} (${farmer.code}) - Payments'),
      ]);
      paySheet.appendRow([]);
      paySheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Type'),
        xl.TextCellValue('Liters'),
        xl.TextCellValue('Amount'),
        xl.TextCellValue('Advance Ded.'),
        xl.TextCellValue('Net Amount'),
        xl.TextCellValue('Mode'),
      ]);
      for (var p in payments) {
        paySheet.appendRow([
          xl.TextCellValue(DateFormat('dd/MM/yyyy').format(p.paymentDate)),
          xl.TextCellValue(p.type),
          xl.DoubleCellValue(double.parse(p.totalLiters.toStringAsFixed(2))),
          xl.DoubleCellValue(double.parse(p.amount.toStringAsFixed(2))),
          xl.DoubleCellValue(
              double.parse(p.advanceDeduction.toStringAsFixed(2))),
          xl.DoubleCellValue(double.parse(p.netAmount.toStringAsFixed(2))),
          xl.TextCellValue(p.paymentMode.toUpperCase()),
        ]);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final bytes = excel.save();
      if (bytes == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final file =
          File('${dir.path}/${farmer.name}_${farmer.code}_Report.xlsx');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: '${farmer.name} Report');
      _showSnackBar('✅ Excel ready!', isError: false);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      _isExporting = false;
    }
  }

  Future<void> _exportFarmerPdf(
      Farmer farmer, List<MilkEntry> entries, List<Payment> payments) async {
    if (_isExporting) return;
    _isExporting = true;
    try {
      _showSnackBar(
          _isHindi ? 'PDF बन रही है...' : 'Generating PDF...',
          isError: false);

      final pdf = pw.Document();
      final totalMilk = entries.fold(0.0, (s, e) => s + e.quantity);
      final totalAmount = entries.fold(0.0, (s, e) => s + e.amount);
      final totalPaid = payments.fold(0.0, (s, p) => s + p.netAmount);

      final fontData =
          await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
      final boldFontData =
          await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
      pw.Font? hindiFont;
      pw.Font? hindiBoldFont;
      try {
        hindiFont = pw.Font.ttf(fontData);
        hindiBoldFont = pw.Font.ttf(boldFontData);
      } catch (_) {
        hindiFont = null;
        hindiBoldFont = null;
      }

      final hStyle = pw.TextStyle(
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        font: hindiBoldFont,
      );
      final cStyle = pw.TextStyle(fontSize: 7, font: hindiFont);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_dairyName,
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      font: hindiBoldFont)),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                      '${farmer.name} (${farmer.code}) | ${farmer.mobile}',
                      style: pw.TextStyle(fontSize: 10, font: hindiFont)),
                  pw.Text(
                      'Milk: ${totalMilk.toStringAsFixed(1)}L | Amount: ₹${totalAmount.toStringAsFixed(0)} | Paid: ₹${totalPaid.toStringAsFixed(0)}',
                      style: pw.TextStyle(fontSize: 8, font: hindiFont)),
                ],
              ),
              pw.Divider(color: PdfColors.green800),
              pw.SizedBox(height: 4),
            ],
          ),
          build: (context) {
            final widgets = <pw.Widget>[];

            if (entries.isNotEmpty) {
              widgets.add(pw.Text('Milk Entries',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      font: hindiBoldFont)));
              widgets.add(pw.SizedBox(height: 6));
              widgets.add(
                pw.TableHelper.fromTextArray(
                  headerStyle: hStyle,
                  cellStyle: cStyle,
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.green50),
                  headers: [
                    'Date',
                    'Shift',
                    'Type',
                    'Qty',
                    'FAT',
                    'SNF',
                    'Rate',
                    'Amount'
                  ],
                  data: entries
                      .map((e) => [
                            DateFormat('dd/MM/yy').format(e.dateTime),
                            e.shift == 'morning' ? 'M' : 'E',
                            e.cattleType == 'buffalo' ? 'B' : 'C',
                            e.quantity.toStringAsFixed(1),
                            '${e.fat.toStringAsFixed(1)}%',
                            e.snf != null
                                ? '${e.snf!.toStringAsFixed(1)}%'
                                : '-',
                            '₹${e.rate.toStringAsFixed(1)}',
                            '₹${e.amount.toStringAsFixed(0)}',
                          ])
                      .toList(),
                ),
              );
            }

            if (payments.isNotEmpty) {
              widgets.add(pw.SizedBox(height: 16));
              widgets.add(pw.Text('Payments',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      font: hindiBoldFont)));
              widgets.add(pw.SizedBox(height: 6));
              widgets.add(
                pw.TableHelper.fromTextArray(
                  headerStyle: hStyle,
                  cellStyle: cStyle,
                  headerDecoration:
                      const pw.BoxDecoration(color: PdfColors.green50),
                  headers: [
                    'Date',
                    'Type',
                    'Liters',
                    'Amount',
                    'Adv. Ded.',
                    'Net Amount',
                    'Mode'
                  ],
                  data: payments
                      .map((p) => [
                            DateFormat('dd/MM/yy').format(p.paymentDate),
                            p.type,
                            p.totalLiters.toStringAsFixed(1),
                            '₹${p.amount.toStringAsFixed(0)}',
                            '₹${p.advanceDeduction.toStringAsFixed(0)}',
                            '₹${p.netAmount.toStringAsFixed(0)}',
                            p.paymentMode.toUpperCase(),
                          ])
                      .toList(),
                ),
              );
            }

            return widgets;
          },
        ),
      );

      final bytes = await pdf.save();
      final dir = await getApplicationDocumentsDirectory();
      final file =
          File('${dir.path}/${farmer.name}_${farmer.code}_Ledger.pdf');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      await Share.shareXFiles([XFile(file.path)],
          subject: '${farmer.name} Ledger');
      _showSnackBar('✅ PDF ready!', isError: false);
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      _isExporting = false;
    }
  }

  // ========== BUILD UI ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: primaryGreen),
            )
          : _showFarmerDetail
              ? _buildFarmerDetailView()
              : _buildFarmerListView(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: cardColor,
      surfaceTintColor: cardColor,
      elevation: 0,
      shadowColor: Colors.black12,
      leading: IconButton(
        icon: Icon(
          _showFarmerDetail
              ? Icons.arrow_back_rounded
              : Icons.close_rounded,
          color: textDark,
        ),
        onPressed:
            _showFarmerDetail ? _backToList : () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _showFarmerDetail
                ? _selectedFarmer?.name ?? ''
                : (_isHindi ? 'रिपोर्ट' : 'Reports'),
            style: TextStyle(
              color: textDark,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          if (_showFarmerDetail && _selectedFarmer != null)
            Text(
              'Code: ${_selectedFarmer!.code} | ${_selectedFarmer!.mobile}',
              style: TextStyle(fontSize: 11, color: textLight),
            ),
        ],
      ),
      actions: [
        if (_showFarmerDetail)
          IconButton(
            icon: Icon(Icons.file_download_rounded, color: primaryGreen),
            tooltip: 'Export',
            onPressed: _showFarmerExportMenu,
          )
        else ...[
          IconButton(
            icon: Icon(Icons.file_download_rounded, color: primaryGreen),
            tooltip: 'Export',
            onPressed: _showExportMenu,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: textLight),
            onPressed: _loadData,
          ),
        ],
      ],
    );
  }

  // ========== FARMER LIST VIEW ==========

  Widget _buildFarmerListView() {
    return Column(
      children: [
        // Filter & Search Bar
        Container(
          color: cardColor,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  // Date Range Picker
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectDateRange,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: dividerColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.date_range_rounded,
                                color: primaryGreen, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yy').format(_endDate)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: textDark,
                                ),
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                color: textLight, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Search
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: dividerColor),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v),
                        style: TextStyle(fontSize: 13, color: textDark),
                        decoration: InputDecoration(
                          hintText: _isHindi ? 'खोजें...' : 'Search...',
                          hintStyle: TextStyle(
                              color: textLight, fontSize: 13),
                          prefixIcon: Icon(Icons.search_rounded,
                              color: textLight, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(
                                        () => _searchQuery = '');
                                  },
                                  child: Icon(Icons.close_rounded,
                                      color: textLight, size: 16),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Stats Cards
        _buildStatsRow(),

        // Table Header
        Container(
          color: _isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              SizedBox(width: 36, child: Text('#', style: _headerStyle)),
              Expanded(
                  flex: 3,
                  child: Text(
                      _isHindi ? 'किसान' : 'Farmer',
                      style: _headerStyle)),
              Expanded(
                  flex: 2,
                  child: Text(
                      _isHindi ? 'दूध' : 'Milk',
                      style: _headerStyle,
                      textAlign: TextAlign.right)),
              Expanded(
                  flex: 2,
                  child: Text(
                      _isHindi ? 'राशि' : 'Amount',
                      style: _headerStyle,
                      textAlign: TextAlign.right)),
              Expanded(
                  flex: 2,
                  child: Text(
                      _isHindi ? 'बकाया' : 'Pending',
                      style: _headerStyle,
                      textAlign: TextAlign.right)),
              const SizedBox(width: 24),
            ],
          ),
        ),

        // Farmer List
        Expanded(
          child: _farmerSummaries.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  itemCount: _farmerSummaries.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: dividerColor),
                  itemBuilder: (context, index) {
                    final s = _farmerSummaries[index];
                    final pending = s['pending'] as double;
                    return InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _showFarmerLedger(s['farmer'] as Farmer);
                      },
                      child: Container(
                        color: cardColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            // Farmer code badge
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    primaryGreen,
                                    primaryDark,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  s['code'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s['name'],
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: textDark,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${s['entries']} ${_isHindi ? 'एंट्री' : 'entries'}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: textLight),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${(s['milk'] as double).toStringAsFixed(1)}L',
                                style: TextStyle(
                                    fontSize: 13, color: textDark),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '₹${(s['amount'] as double).toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '₹${pending.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: pending > 0
                                      ? primaryOrange
                                      : primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: textLight, size: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Grand Total Footer
        _buildTotalFooter(),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Container(
      color: _isDark ? Colors.white.withOpacity(0.03) : Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _buildStatChip(
            Icons.people_rounded,
            '${_farmerSummaries.length}',
            _isHindi ? 'किसान' : 'Farmers',
            Colors.blue,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            Icons.water_drop_rounded,
            '${_totalMilk.toStringAsFixed(0)}L',
            _isHindi ? 'दूध' : 'Milk',
            Colors.teal,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            Icons.currency_rupee_rounded,
            '₹${_totalAmount.toStringAsFixed(0)}',
            _isHindi ? 'राशि' : 'Amount',
            primaryGreen,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            Icons.pending_actions_rounded,
            '₹${_totalPending.toStringAsFixed(0)}',
            _isHindi ? 'बकाया' : 'Pending',
            primaryOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(_isDark ? 0.1 : 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalFooter() {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? primaryGreen.withOpacity(0.1) : primaryGreen.withOpacity(0.05),
        border: Border(top: BorderSide(color: primaryGreen.withOpacity(0.2))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SizedBox(width: 36),
          Expanded(
            flex: 3,
            child: Text(
              'TOTAL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: textDark,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${_totalMilk.toStringAsFixed(0)}L',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: textDark),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${_totalAmount.toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: primaryGreen),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${_totalPending.toStringAsFixed(0)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: primaryOrange),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined,
              size: 56, color: textLight.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(
            _isHindi ? 'कोई डेटा नहीं मिला' : 'No data found',
            style: TextStyle(
              color: textLight,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isHindi
                ? 'तारीख बदलें या खोज हटाएं'
                : 'Change date range or clear search',
            style: TextStyle(fontSize: 12, color: textLight),
          ),
        ],
      ),
    );
  }

  TextStyle get _headerStyle => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: textLight,
        letterSpacing: 0.3,
      );

  // ========== FARMER DETAIL VIEW ==========

  Widget _buildFarmerDetailView() {
    if (_selectedFarmer == null) return const SizedBox();

    final entries = _getDetailEntries();
    final payments = _getDetailPayments();
    final totalMilk = entries.fold(0.0, (s, e) => s + e.quantity);
    final totalAmount = entries.fold(0.0, (s, e) => s + e.amount);
    final totalPaid = payments.fold(0.0, (s, p) => s + p.netAmount);
    final balance = totalAmount - totalPaid;

    return Column(
      children: [
        // Farmer Info & Filter Bar
        Container(
          color: cardColor,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              // Farmer Info Row
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [primaryGreen, primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        _selectedFarmer!.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFarmer!.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.phone_rounded,
                                size: 12, color: textLight),
                            const SizedBox(width: 4),
                            Text(
                              _selectedFarmer!.mobile,
                              style:
                                  TextStyle(fontSize: 12, color: textLight),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              _selectedFarmer!.cattleType == 'buffalo'
                                  ? Icons.pets_rounded
                                  : Icons.pets_rounded,
                              size: 12,
                              color: textLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedFarmer!.cattleType == 'buffalo'
                                  ? (_isHindi ? 'भैंस' : 'Buffalo')
                                  : (_isHindi ? 'गाय' : 'Cow'),
                              style:
                                  TextStyle(fontSize: 12, color: textLight),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(_isHindi ? 'सभी' : 'All', 'all'),
                    _buildFilterChip(
                        _isHindi ? '7 दिन' : '7 Days', '7days'),
                    _buildFilterChip(
                        _isHindi ? '30 दिन' : '30 Days', '30days'),
                    _buildFilterChip(
                        _isHindi ? '3 महीने' : '3 Months', '3months'),
                    GestureDetector(
                      onTap: _selectDetailDateRange,
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _detailDateFilter == 'custom'
                              ? primaryGreen
                              : chipBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 14,
                                color: _detailDateFilter == 'custom'
                                    ? Colors.white
                                    : textLight),
                            const SizedBox(width: 4),
                            Text(
                              _detailDateFilter == 'custom' &&
                                      _detailCustomStart != null
                                  ? '${DateFormat('dd/MM').format(_detailCustomStart!)} - ${DateFormat('dd/MM').format(_detailCustomEnd!)}'
                                  : (_isHindi ? 'कस्टम' : 'Custom'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _detailDateFilter == 'custom'
                                    ? Colors.white
                                    : textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Stats Row
              Row(
                children: [
                  _buildMiniStat(
                      _isHindi ? 'एंट्री' : 'Entries', '${entries.length}'),
                  _buildMiniStat(
                      _isHindi ? 'दूध' : 'Milk',
                      '${totalMilk.toStringAsFixed(0)}L'),
                  _buildMiniStat(
                      _isHindi ? 'राशि' : 'Amount',
                      '₹${totalAmount.toStringAsFixed(0)}'),
                  _buildMiniStat(
                      _isHindi ? 'भुगतान' : 'Paid',
                      '₹${totalPaid.toStringAsFixed(0)}'),
                  _buildMiniStat(
                      _isHindi ? 'शेष' : 'Balance',
                      '₹${balance.toStringAsFixed(0)}',
                      color: balance > 0 ? primaryOrange : primaryGreen),
                ],
              ),
            ],
          ),
        ),

        // Tabs
        Expanded(
          child: Column(
            children: [
              Container(
                color: cardColor,
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: primaryGreen,
                  indicatorWeight: 3,
                  labelColor: primaryGreen,
                  unselectedLabelColor: textLight,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    Tab(
                        text:
                            '${_isHindi ? 'एंट्री' : 'Entries'} (${entries.length})'),
                    Tab(
                        text:
                            '${_isHindi ? 'भुगतान' : 'Payments'} (${payments.length})'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildEntriesTab(entries),
                    _buildPaymentsTab(payments),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isActive = _detailDateFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _detailDateFilter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? primaryGreen : chipBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : textDark,
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color ?? textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: textLight),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesTab(List<MilkEntry> entries) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded,
                size: 48, color: textLight.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text(
              _isHindi ? 'कोई एंट्री नहीं' : 'No entries',
              style: TextStyle(color: textLight),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: dividerColor),
      itemBuilder: (context, index) {
        final e = entries[index];
        return Container(
          color: cardColor,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Date & Shift
              SizedBox(
                width: 50,
                child: Column(
                  children: [
                    Text(
                      DateFormat('dd').format(e.dateTime),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(e.dateTime),
                      style: TextStyle(
                          fontSize: 10, color: textLight),
                    ),
                    Icon(
                      e.shift == 'morning'
                          ? Icons.wb_sunny_rounded
                          : Icons.nights_stay_rounded,
                      size: 14,
                      color: e.shift == 'morning'
                          ? Colors.orange
                          : Colors.indigo,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          e.cattleType == 'buffalo' ? '🐃' : '🐄',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${e.quantity.toStringAsFixed(1)} Ltr',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: textDark,
                          ),
                        ),
                        if (e.isPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Pending',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.amber.shade800),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'FAT ${e.fat.toStringAsFixed(1)}% ${e.snf != null ? '• SNF ${e.snf!.toStringAsFixed(1)}%' : ''} • Rate ₹${e.rate.toStringAsFixed(2)}',
                      style:
                          TextStyle(fontSize: 11, color: textLight),
                    ),
                  ],
                ),
              ),
              // Amount
              Text(
                '₹${e.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentsTab(List<Payment> payments) {
    if (payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments_rounded,
                size: 48, color: textLight.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text(
              _isHindi ? 'कोई भुगतान नहीं' : 'No payments',
              style: TextStyle(color: textLight),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: payments.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: dividerColor),
      itemBuilder: (context, index) {
        final p = payments[index];
        final isAdvance = p.type == 'ADVANCE';
        return Container(
          color: isAdvance
              ? Colors.orange.shade50.withOpacity(_isDark ? 0.1 : 1)
              : Colors.green.shade50.withOpacity(_isDark ? 0.1 : 1),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Date
              SizedBox(
                width: 50,
                child: Column(
                  children: [
                    Text(
                      DateFormat('dd').format(p.paymentDate),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    Text(
                      DateFormat('MMM').format(p.paymentDate),
                      style: TextStyle(
                          fontSize: 10, color: textLight),
                    ),
                    Text(
                      DateFormat('yy').format(p.paymentDate),
                      style: TextStyle(
                          fontSize: 10, color: textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isAdvance
                              ? Icons.arrow_upward_rounded
                              : Icons.check_circle_rounded,
                          size: 16,
                          color:
                              isAdvance ? primaryOrange : primaryGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAdvance
                              ? (_isHindi ? 'एडवांस' : 'Advance')
                              : (_isHindi ? 'भुगतान' : 'Payment'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: isAdvance
                                ? primaryOrange
                                : primaryGreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.totalLiters.toStringAsFixed(1)}L • ${p.paymentMode.toUpperCase()}',
                      style:
                          TextStyle(fontSize: 11, color: textLight),
                    ),
                    if (p.advanceDeduction > 0)
                      Text(
                        '${_isHindi ? 'एडवांस कटौती' : 'Adv Deducted'}: ₹${p.advanceDeduction.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 10, color: primaryOrange),
                      ),
                  ],
                ),
              ),
              // Amount
              Text(
                '${isAdvance ? '-' : '+'}₹${p.netAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isAdvance ? primaryOrange : primaryGreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
