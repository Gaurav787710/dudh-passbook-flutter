import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../utils/theme_helper.dart';

enum BillRenderMode { share, print }

class BillPreviewScreen extends StatefulWidget {
  final Farmer farmer;
  final List<MilkEntry> entries;
  final DateTime startDate;
  final DateTime endDate;
  final double totalMilk;
  final double totalAmount;
  final double totalAdvance;
  final double totalPaid;
  final double lbtAmount;
  final double netPayable;
  final String dairyName;

  const BillPreviewScreen({
    super.key,
    required this.farmer,
    required this.entries,
    required this.startDate,
    required this.endDate,
    required this.totalMilk,
    required this.totalAmount,
    required this.totalAdvance,
    this.totalPaid = 0.0,
    this.lbtAmount = 10.0,
    required this.netPayable,
    required this.dairyName,
  });

  @override
  State<BillPreviewScreen> createState() => _BillPreviewScreenState();
}

class _BillPreviewScreenState extends State<BillPreviewScreen> {
  String _billType = 'detailed'; // 'summary' or 'detailed'
  bool _isGenerating = false;
  final GlobalKey _previewKey = GlobalKey(); // Key for capturing preview
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Cached computed data (computed once, not on every build)
  late final List<Map<String, dynamic>> _cachedDailyRows;
  late final Map<String, dynamic> _cachedQualityData;
  late final Map<String, double> _cachedShiftTotals;
  late final List<MilkEntry> _cachedSortedEntries;
  late final String _cachedInvoiceNo;

  // Theme-aware colors for UI chrome
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF1F5F9);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get uiTextColor => _isDark ? Colors.white : slateGray;

  // Fixed colors for bill content (print-ready)
  static const Color slateGray = Color(0xFF1E293B);
  static const Color emeraldGreen = Color(0xFF059669);

  @override
  void initState() {
    super.initState();
    _cachedDailyRows = _computeDailyRows();
    _cachedQualityData = _computeQualityData();
    _cachedShiftTotals = _computeShiftTotals();
    _cachedSortedEntries = _computeSortedEntries();
    _cachedInvoiceNo = 'INV-${widget.farmer.code}-${DateFormat('yyyyMMdd').format(DateTime.now())}';
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'hi';
    });
  }

  String get _invoiceNo => _cachedInvoiceNo;

  // Cached getter - returns precomputed data
  List<Map<String, dynamic>> get _dailyRows => _cachedDailyRows;

  // Cached getter - returns precomputed data
  List<MilkEntry> get _sortedEntries => _cachedSortedEntries;

  // Compute daily rows once - groups by date AND cattleType to prevent cow/buffalo merging
  List<Map<String, dynamic>> _computeDailyRows() {
    final Map<String, Map<String, dynamic>> grouped = {};
    
    for (var entry in widget.entries) {
      final dateKey = DateFormat('yyyy-MM-dd').format(entry.dateTime);
      final cattleKey = entry.cattleType ?? 'cow';
      final groupKey = '${dateKey}_$cattleKey';
      if (!grouped.containsKey(groupKey)) {
        grouped[groupKey] = {'date': entry.dateTime, 'cattleType': cattleKey, 'morning': null, 'evening': null};
      }
      if (entry.shift == 'morning') {
        grouped[groupKey]!['morning'] = entry;
      } else {
        grouped[groupKey]!['evening'] = entry;
      }
    }
    
    final result = grouped.values.toList();
    result.sort((a, b) {
      final dateCompare = (a['date'] as DateTime).compareTo(b['date'] as DateTime);
      if (dateCompare != 0) return dateCompare;
      return (a['cattleType'] as String).compareTo(b['cattleType'] as String);
    });
    return result;
  }

  // Cached getter - returns precomputed data
  Map<String, dynamic> get _qualityData => _cachedQualityData;

  // Compute quality data once
  Map<String, dynamic> _computeQualityData() {
    if (widget.entries.isEmpty) {
      return {
        'avgFat': 0.0,
        'avgSnf': 0.0,
        'avgRate': 0.0,
        'fatScore': 0,
        'snfScore': 0,
        'consistencyScore': 0,
        'regularityScore': 0,
        'totalScore': 0,
        'grade': '-',
        'waterAdulteration': 'N/A',
        'fatAdulteration': 'N/A',
        'overallPurity': 'N/A',
      };
    }
    
    double totalFat = 0, totalSnf = 0, totalRate = 0;
    for (var e in widget.entries) {
      totalFat += e.fat;
      totalSnf += e.snf ?? 0;
      totalRate += e.rate;
    }
    
    final avgFat = totalFat / widget.entries.length;
    final avgSnf = totalSnf / widget.entries.length;
    final avgRate = totalRate / widget.entries.length;
    
    // Quality scoring (same as website)
    int fatScore = avgFat >= 4.5 ? 25 : avgFat >= 4.0 ? 20 : avgFat >= 3.5 ? 15 : 10;
    int snfScore = avgSnf >= 8.5 ? 25 : avgSnf >= 8.0 ? 20 : avgSnf >= 7.5 ? 15 : 10;
    
    // Consistency score
    double fatVariance = 0, snfVariance = 0;
    for (var e in widget.entries) {
      fatVariance += (e.fat - avgFat).abs();
      snfVariance += ((e.snf ?? 0) - avgSnf).abs();
    }
    fatVariance /= widget.entries.length;
    snfVariance /= widget.entries.length;
    
    int consistencyScore = (fatVariance < 0.3 && snfVariance < 0.3) ? 25 : (fatVariance < 0.5 && snfVariance < 0.5) ? 20 : 15;
    
    // Regularity score
    int expectedEntries = _dailyRows.length * 2;
    int actualEntries = widget.entries.length;
    int regularityScore = (actualEntries / expectedEntries) >= 0.9 ? 25 : (actualEntries / expectedEntries) >= 0.7 ? 20 : 15;
    
    int totalScore = fatScore + snfScore + consistencyScore + regularityScore;
    String grade = totalScore >= 90 ? 'A+' : totalScore >= 80 ? 'A' : totalScore >= 70 ? 'B+' : totalScore >= 60 ? 'B' : 'C';
    
    // Quality checks
    String waterAdulteration = avgSnf < 7.5 ? 'Possible' : 'Not Detected';
    String fatAdulteration = avgFat < 3.0 ? 'Possible' : 'Not Detected';
    String overallPurity = (avgFat >= 3.5 && avgSnf >= 8.0) ? 'Good' : 'Fair';
    
    return {
      'avgFat': avgFat,
      'avgSnf': avgSnf,
      'avgRate': avgRate,
      'fatScore': fatScore,
      'snfScore': snfScore,
      'consistencyScore': consistencyScore,
      'regularityScore': regularityScore,
      'totalScore': totalScore,
      'grade': grade,
      'waterAdulteration': waterAdulteration,
      'fatAdulteration': fatAdulteration,
      'overallPurity': overallPurity,
    };
  }

  // Cached getter - returns precomputed data
  Map<String, double> get _shiftTotals => _cachedShiftTotals;

  // Compute shift totals once
  Map<String, double> _computeShiftTotals() {
    double morningQty = 0, eveningQty = 0;
    double morningAmt = 0, eveningAmt = 0;
    
    for (var e in widget.entries) {
      if (e.shift == 'morning') {
        morningQty += e.quantity;
        morningAmt += e.amount;
      } else {
        eveningQty += e.quantity;
        eveningAmt += e.amount;
      }
    }
    
    return {
      'morningQty': morningQty,
      'eveningQty': eveningQty,
      'morningAmt': morningAmt,
      'eveningAmt': eveningAmt,
    };
  }

  // Compute sorted entries once (same ordering used by preview)
  List<MilkEntry> _computeSortedEntries() {
    final entries = List<MilkEntry>.from(widget.entries);
    entries.sort((a, b) {
      final dateCompare = a.dateTime.compareTo(b.dateTime);
      if (dateCompare != 0) return dateCompare;
      return a.shift == 'morning' ? -1 : 1;
    });
    return entries;
  }

  // Number to words (same as website)
  String _numberToWords(double num) {
    final ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    final tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    
    int n = num.floor();
    if (n == 0) return 'Zero';
    if (n < 0) return 'Minus ${_numberToWords(-num)}';
    
    String words = '';
    
    if ((n ~/ 10000000) > 0) {
      words += '${_numberToWords((n ~/ 10000000).toDouble())} Crore ';
      n = n % 10000000;
    }
    if ((n ~/ 100000) > 0) {
      words += '${_numberToWords((n ~/ 100000).toDouble())} Lakh ';
      n = n % 100000;
    }
    if ((n ~/ 1000) > 0) {
      words += '${_numberToWords((n ~/ 1000).toDouble())} Thousand ';
      n = n % 1000;
    }
    if ((n ~/ 100) > 0) {
      words += '${_numberToWords((n ~/ 100).toDouble())} Hundred ';
      n = n % 100;
    }
    if (n > 0) {
      if (n < 20) {
        words += ones[n];
      } else {
        words += tens[n ~/ 10];
        if (n % 10 > 0) words += ' ${ones[n % 10]}';
      }
    }
    return words.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: uiTextColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Invoice Preview', style: TextStyle(color: uiTextColor, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
            child: const Text('A4 Print Ready', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ),
        ],
      ),
      body: Column(
        children: [
          // Template Selector - Same as website
          Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('Bill Format: ', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey, fontSize: 13)),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTemplateBtn('📊 Summary', 'summary'),
                      _buildTemplateBtn('📋 Detailed', 'detailed'),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  _billType == 'summary' ? 'Morning/Eve' : 'Morning/Eve',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),

          // Bill Preview - Scrollable with RepaintBoundary for screenshot
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: RepaintBoundary(
                  key: _previewKey,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 20, spreadRadius: 2)],
                    ),
                    child: _billType == 'detailed' ? _buildDetailedBill() : _buildSummaryBill(),
                  ),
                ),
              ),
            ),
          ),

          // Action Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _printBill,
                    icon: _isGenerating 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Print Invoice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: slateGray,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isGenerating ? null : _shareBill,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emeraldGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateBtn(String label, String value) {
    final isActive = _billType == value;
    return GestureDetector(
      onTap: () => setState(() => _billType = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? slateGray : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isActive ? Colors.white : Colors.grey.shade600)),
      ),
    );
  }

  // ==================== SUMMARY BILL (Website Style) ====================
  Widget _buildSummaryBill() {
    final quality = _qualityData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header - Same as website PrintBillContent
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: slateGray, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left - Dairy Name
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.dairyName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: slateGray)),
                  const Text('Milk Collection & Distribution Center', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              // Right - Invoice
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('INVOICE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1, color: slateGray)),
                  Text('#$_invoiceNo', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text('Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Farmer & Period Info - Same as website
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left - Bill To
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BILL TO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text(widget.farmer.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: slateGray)),
                        if (widget.farmer.fatherName != null && widget.farmer.fatherName!.isNotEmpty)
                          Text('S/O ${widget.farmer.fatherName ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text('Code: ${widget.farmer.code}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            Text('•', style: TextStyle(color: Colors.grey.shade400)),
                            Text(widget.farmer.mobile, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            Text('•', style: TextStyle(color: Colors.grey.shade400)),
                            Text(widget.farmer.cattleType == 'buffalo' ? 'Buffalo' : 'Cow', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right - Billing Period
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('BILLING PERIOD', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text('${DateFormat('dd/MM/yyyy').format(widget.startDate)} - ${DateFormat('dd/MM/yyyy').format(widget.endDate)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text('${_dailyRows.length} Days • ${widget.entries.length} Entries', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Summary Cards Row - Same as website
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    _buildSummaryCard('Total Milk', widget.totalMilk.toStringAsFixed(1), 'L'),
                    _buildSummaryCardDivider(),
                    _buildSummaryCard('Avg Fat', (quality['avgFat'] as num).toStringAsFixed(2), '%'),
                    _buildSummaryCardDivider(),
                    _buildSummaryCard('Avg SNF', (quality['avgSnf'] as num).toStringAsFixed(2), '%'),
                    _buildSummaryCardDivider(),
                    _buildSummaryCard('Avg Rate', '₹${(quality['avgRate'] as num).toStringAsFixed(2)}', '/L'),
                    _buildSummaryCardDivider(),
                    _buildQualityScoreCard(quality['totalScore'] as int? ?? 0, quality['grade'] as String? ?? '-'),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Quality Check Row - Same as website
              Row(
                children: [
                  _buildQualityCheck('Water', quality['waterAdulteration'] as String? ?? 'N/A'),
                  const SizedBox(width: 16),
                  _buildQualityCheck('Fat', quality['fatAdulteration'] as String? ?? 'N/A'),
                  const SizedBox(width: 16),
                  _buildQualityCheck('Purity', quality['overallPurity'] as String? ?? 'N/A'),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      'Fat ${quality['fatScore'] ?? 0}/25 • SNF ${quality['snfScore'] ?? 0}/25 • Consistency ${quality['consistencyScore'] ?? 0}/25 • Regularity ${quality['regularityScore'] ?? 0}/25',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Daily Collection Table - Summary style
              Text('DAILY COLLECTION', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              _buildSummaryTable(),
              const SizedBox(height: 16),

              // Payment Summary - Right aligned same as website
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        _buildPaymentRow('Gross Amount', '₹${widget.totalAmount.toStringAsFixed(0)}', isBold: true),
                        _buildPaymentRow('Less: Advance', '- ₹${widget.totalAdvance.toStringAsFixed(0)}', isDeduction: true),
                        if (widget.totalPaid > 0)
                          _buildPaymentRow('Less: Paid', '- ₹${widget.totalPaid.toStringAsFixed(0)}', isDeduction: true),
                        if (widget.lbtAmount > 0)
                          _buildPaymentRow('Less: LBT Amount', '- ₹${widget.lbtAmount.toStringAsFixed(0)}', isDeduction: true),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: slateGray, width: 2)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('NET PAYABLE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              Text('₹${widget.netPayable.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Amount in Words - Same as website
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'Amount in Words: Rupees ${_numberToWords(widget.netPayable)} Only',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),

              // Signatures - Same as website
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Container(width: 100, height: 1, color: Colors.grey.shade400),
                      const SizedBox(height: 4),
                      Text('Farmer Signature', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                  Column(
                    children: [
                      Container(width: 100, height: 1, color: Colors.grey.shade400),
                      const SizedBox(height: 4),
                      Text('Authorized Signature', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Footer - Same as website
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Text(
            'Computer generated invoice • ${widget.dairyName} • Powered by Dudh Passbook',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ==================== DETAILED BILL (Website Style) ====================
  Widget _buildDetailedBill() {
    final shiftTotals = _shiftTotals;
    final sortedEntries = _sortedEntries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header - Centered style for detailed bill
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: slateGray, width: 2)),
          ),
          child: Column(
            children: [
              Text(widget.dairyName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: slateGray)),
              const Text('Milk Collection & Distribution Center', style: TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 4),
              Text('Invoice No: $_invoiceNo | Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Farmer Details Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FARMER DETAILS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _buildInfoItem('Name', widget.farmer.name, isBold: true),
                        if (widget.farmer.fatherName != null && widget.farmer.fatherName!.isNotEmpty)
                          _buildInfoItem('S/O', widget.farmer.fatherName ?? ''),
                        _buildInfoItem('Code', widget.farmer.code, isBold: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _buildInfoItem('Mobile', widget.farmer.mobile),
                        _buildInfoItem('Cattle', widget.farmer.cattleType == 'buffalo' ? 'Buffalo' : 'Cow'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Billing Period
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'Billing Period: ${DateFormat('dd/MM/yyyy').format(widget.startDate)} to ${DateFormat('dd/MM/yyyy').format(widget.endDate)} (${widget.entries.length} Entries)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),

              // Detailed Table - All entries with Type & Rate
              Text('DAILY MILK COLLECTION DETAILS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
              const SizedBox(height: 6),
              _buildDetailedTable(sortedEntries),
              const SizedBox(height: 12),

              // Summary Section - Grid like website
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Milk Summary
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MILK SUMMARY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                          const SizedBox(height: 8),
                          _buildSummaryItem('Morning Total:', '${shiftTotals['morningQty']!.toStringAsFixed(1)} L'),
                          _buildSummaryItem('Evening Total:', '${shiftTotals['eveningQty']!.toStringAsFixed(1)} L'),
                          const Divider(height: 12),
                          _buildSummaryItem('Grand Total:', '${widget.totalMilk.toStringAsFixed(1)} L', isBold: true),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Payment Summary
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PAYMENT SUMMARY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                          const SizedBox(height: 8),
                          _buildSummaryItem('Gross Amount:', '₹${widget.totalAmount.toStringAsFixed(0)}'),
                          _buildSummaryItem('Less: Advance:', '- ₹${widget.totalAdvance.toStringAsFixed(0)}', isGrey: true),
                          if (widget.totalPaid > 0)
                            _buildSummaryItem('Less: Paid:', '- ₹${widget.totalPaid.toStringAsFixed(0)}', isGrey: true),
                          if (widget.lbtAmount > 0)
                            _buildSummaryItem('Less: LBT:', '- ₹${widget.lbtAmount.toStringAsFixed(0)}', isGrey: true),
                          const Divider(height: 12),
                          _buildSummaryItem('Net Payable:', '₹${widget.netPayable.toStringAsFixed(0)}', isBold: true),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Amount in Words
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  'Amount in Words: Rupees ${_numberToWords(widget.netPayable)} Only',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // Signatures
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Container(width: 100, height: 1, color: Colors.grey.shade400),
                      const SizedBox(height: 4),
                      Text('Farmer Signature', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                  Column(
                    children: [
                      Container(width: 100, height: 1, color: Colors.grey.shade400),
                      const SizedBox(height: 4),
                      Text('Authorized Signature', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Footer
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
          child: Text(
            'Computer generated invoice • ${widget.dairyName} • Powered by Dudh Passbook',
            style: TextStyle(fontSize: 8, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ==================== HELPER WIDGETS ====================
  Widget _buildSummaryCard(String label, String value, String unit) {
    return Expanded(
      child: Column(
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: slateGray),
              children: [
                TextSpan(text: value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextSpan(text: unit, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCardDivider() {
    return Container(width: 1, height: 40, color: Colors.grey.shade300);
  }

  Widget _buildQualityScoreCard(int score, String grade) {
    return Expanded(
      child: Column(
        children: [
          Text('QUALITY', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$score', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: slateGray)),
                const Text('/100', style: TextStyle(fontSize: 10, color: slateGray)),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: slateGray, borderRadius: BorderRadius.circular(4)),
                  child: Text(grade, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCheck(String label, String value) {
    return Row(
      children: [
        Text('$label:', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSummaryTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                _tableHeader('Date', flex: 2),
                _tableHeader('Fat%'),
                _tableHeader('SNF%'),
                _tableHeader('Morning'),
                _tableHeader('Evening'),
                _tableHeader('Total(L)'),
                _tableHeader('Amount', flex: 2),
              ],
            ),
          ),
          // Rows
          ..._dailyRows.map((row) {
            final m = row['morning'] as MilkEntry?;
            final e = row['evening'] as MilkEntry?;
            final totalQty = (m?.quantity ?? 0) + (e?.quantity ?? 0);
            final totalAmt = (m?.amount ?? 0) + (e?.amount ?? 0);
            double avgFat = 0, avgSnf = 0;
            int count = 0;
            if (m != null) { avgFat += m.fat; avgSnf += m.snf ?? 0; count++; }
            if (e != null) { avgFat += e.fat; avgSnf += e.snf ?? 0; count++; }

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
              child: Row(
                children: [
                  _tableCell(DateFormat('dd/MM').format(row['date'] as DateTime), flex: 2),
                  _tableCell(count > 0 ? (avgFat / count).toStringAsFixed(1) : '-'),
                  _tableCell(count > 0 ? (avgSnf / count).toStringAsFixed(1) : '-'),
                  _tableCell(m?.quantity.toStringAsFixed(1) ?? '-'),
                  _tableCell(e?.quantity.toStringAsFixed(1) ?? '-'),
                  _tableCell(totalQty.toStringAsFixed(1), isBold: true),
                  _tableCell(totalAmt.toStringAsFixed(0), flex: 2, isBold: true),
                ],
              ),
            );
          }),
          // Total Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
              border: Border(top: BorderSide(color: Colors.grey.shade300, width: 2)),
            ),
            child: Row(
              children: [
                _tableCell('TOTAL', flex: 5, isBold: true),
                _tableCell('${widget.totalMilk.toStringAsFixed(1)} L', isBold: true),
                _tableCell('₹${widget.totalAmount.toStringAsFixed(0)}', flex: 2, isBold: true, color: emeraldGreen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedTable(List<MilkEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: Row(
              children: [
                _tableHeader('Date', flex: 2),
                _tableHeader('Shift'),
                _tableHeader('Type'),
                _tableHeader('Qty(L)'),
                _tableHeader('Fat%'),
                _tableHeader('SNF%'),
                _tableHeader('Rate'),
                _tableHeader('Amount'),
              ],
            ),
          ),
          // Rows
          ...entries.map((e) {
            final isMorning = e.shift == 'morning';
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              decoration: BoxDecoration(
                color: isMorning ? const Color(0xFFEFF6FF) : const Color(0xFFFFF7ED),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  _tableCell(DateFormat('dd/MM').format(e.dateTime), flex: 2),
                  _tableCell(isMorning ? (_isHindi ? 'सुबह' : 'Morning') : (_isHindi ? 'शाम' : 'Evening'), color: isMorning ? Colors.blue.shade700 : Colors.orange.shade700),
                  _tableCell(e.cattleType == 'buffalo' ? (_isHindi ? 'भैंस' : 'Buffalo') : (_isHindi ? 'गाय' : 'Cow')),
                  _tableCell(e.quantity.toStringAsFixed(1)),
                  _tableCell(e.fat.toStringAsFixed(1)),
                  _tableCell((e.snf ?? 0).toStringAsFixed(1)),
                  _tableCell(e.rate.toStringAsFixed(1)),
                  _tableCell('₹${e.amount.toStringAsFixed(0)}', isBold: true),
                ],
              ),
            );
          }),
          // Total Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
            ),
            child: Row(
              children: [
                _tableCell('TOTAL', flex: 3, isBold: true),
                _tableCell('${widget.totalMilk.toStringAsFixed(1)} L', isBold: true),
                _tableCell('-', flex: 3),
                _tableCell('₹${widget.totalAmount.toStringAsFixed(0)}', isBold: true, color: emeraldGreen),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700), textAlign: TextAlign.center),
    );
  }

  Widget _tableCell(String text, {int flex = 1, bool isBold = false, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? slateGray), textAlign: TextAlign.center),
    );
  }

  Widget _buildPaymentRow(String label, String value, {bool isBold = false, bool isDeduction = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: isDeduction ? Colors.grey.shade500 : slateGray)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isDeduction ? Colors.grey.shade500 : slateGray)),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {bool isBold = false}) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value, {bool isBold = false, bool isGrey = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: isGrey ? Colors.grey.shade500 : slateGray)),
          Text(value, style: TextStyle(fontSize: isBold ? 13 : 11, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: isGrey ? Colors.grey.shade500 : slateGray)),
        ],
      ),
    );
  }

  // ==================== PDF GENERATION (Website-like) ====================
  Future<Uint8List> _generatePdf({
    BillRenderMode renderMode = BillRenderMode.share,
    required List<MilkEntry> previewEntries,
    required Map<String, double> shiftTotals,
  }) async {
    final pdf = pw.Document();
    
    // Load fonts - NotoSans for English/symbols, Devanagari for Hindi
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final hindiFontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    final boldTtf = pw.Font.ttf(boldFontData);
    final hindiTtf = pw.Font.ttf(hindiFontData);

    final entryCount = previewEntries.length;
    final isPrintMode = renderMode == BillRenderMode.print;
    final forceSinglePage = isPrintMode && entryCount <= 40;
    final density = !isPrintMode
        ? 1.0
        : entryCount <= 20
            ? 1.0
            : entryCount <= 30
                ? 0.92
                : entryCount <= 40
                    ? 0.85
                    : 0.8;
    double scaled(double base, {double min = 6}) {
      if (!isPrintMode) return base;
      final value = base * density;
      return value < min ? min : value;
    }
    final tableFontSize = scaled(8, min: 6.5);
    final headerFontSize = scaled(8, min: 6.5);
    final sectionLabelSize = scaled(8, min: 6.5);
    final detailTextSize = scaled(9, min: 7);
    final subtitleSize = scaled(9, min: 7);
    final titleSize = scaled(20, min: 14);
    final billingSize = scaled(10, min: 7.5);
    final footerSize = scaled(7, min: 6);
    final cellPaddingV = isPrintMode ? 3.0 : 5.0;
    final cellPaddingH = isPrintMode ? 3.0 : 4.0;
    final sectionGap = isPrintMode ? 8.0 : 10.0;
    final blockGap = isPrintMode ? 4.0 : 6.0;
    final summaryGap = isPrintMode ? 8.0 : 12.0;
    final signGap = isPrintMode ? 18.0 : 25.0;
    final pageMargin = isPrintMode ? 18.0 : 25.0;
    final columnWidths = isPrintMode
        ? <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.6),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(1.1),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(0.9),
            5: const pw.FlexColumnWidth(0.9),
            6: const pw.FlexColumnWidth(1.1),
            7: const pw.FlexColumnWidth(1.3),
          }
        : <int, pw.TableColumnWidth>{
            0: const pw.FlexColumnWidth(1.8),
            1: const pw.FlexColumnWidth(1.4),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.2),
            4: const pw.FlexColumnWidth(1.0),
            5: const pw.FlexColumnWidth(1.0),
            6: const pw.FlexColumnWidth(1.2),
            7: const pw.FlexColumnWidth(1.4),
          };

    debugPrint(
      'PDF renderMode=$renderMode entryCount=$entryCount forceSinglePage=$forceSinglePage '
      'density=$density pageMargin=$pageMargin tableFontSize=$tableFontSize',
    );

    // Use preview totals to keep PDF in sync with UI
    final morningTotal = shiftTotals['morningQty'] ?? 0;
    final eveningTotal = shiftTotals['eveningQty'] ?? 0;

    // Create table rows - each entry gets its own row (matches preview exactly)
    final List<pw.TableRow> tableRows = [];
    
    // Header Row - 8 columns matching preview: Date, Shift, Type, Qty, Fat, SNF, Rate, Amount
    tableRows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _pdfCell('Date', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Shift', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Type', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Qty(L)', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Fat%', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('SNF%', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Rate', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('Amount', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
      ],
    ));

    // Data Rows - one row per entry, exactly like preview
    for (var entry in previewEntries) {
      tableRows.add(pw.TableRow(
        children: [
          _pdfCell(DateFormat('dd/MM').format(entry.dateTime), ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell(entry.shift == 'morning' ? 'Morning' : 'Evening', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell(entry.cattleType == 'buffalo' ? 'Buffalo' : 'Cow', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell(entry.quantity.toStringAsFixed(1), ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell(entry.fat.toStringAsFixed(1), ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell((entry.snf ?? 0).toStringAsFixed(1), ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell(entry.rate.toStringAsFixed(1), ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
          _pdfCell('₹${entry.amount.toStringAsFixed(0)}', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        ],
      ));
    }

    // Total Row
    tableRows.add(pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey100),
      children: [
        _pdfCell('TOTAL', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('${widget.totalMilk.toStringAsFixed(1)} L', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('-', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('-', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('-', ttf: ttf, fontSize: tableFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
        _pdfCell('₹${widget.totalAmount.toStringAsFixed(0)}', isHeader: true, ttf: boldTtf, fontSize: headerFontSize, paddingVertical: cellPaddingV, paddingHorizontal: cellPaddingH),
      ],
    ));

    final content = <pw.Widget>[
      // ===== HEADER - Dairy Name & Invoice Info (Website Style: Centered) =====
      pw.Center(
        child: pw.Column(
          children: [
            pw.Text(widget.dairyName, style: pw.TextStyle(fontSize: titleSize, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('Milk Collection & Distribution Center', style: pw.TextStyle(fontSize: subtitleSize, color: PdfColors.grey600)),
            pw.Text('Invoice: $_invoiceNo | Date: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: pw.TextStyle(fontSize: scaled(8, min: 6.5), color: PdfColors.grey500)),
          ],
        ),
      ),
      pw.SizedBox(height: blockGap),
      pw.Divider(thickness: 0.5, color: PdfColors.grey400),
      pw.SizedBox(height: blockGap),

      // ===== FARMER DETAILS (Website Style: Grey header + details below) =====
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(vertical: isPrintMode ? 3 : 4, horizontal: 8),
        color: PdfColors.grey100,
        child: pw.Text('FARMER DETAILS', style: pw.TextStyle(fontSize: sectionLabelSize, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      ),
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(vertical: isPrintMode ? 4 : 6, horizontal: 8),
        child: pw.Wrap(
          spacing: 20,
          runSpacing: 4,
          children: [
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Name: ', style: pw.TextStyle(fontSize: detailTextSize, color: PdfColors.grey600)),
              pw.TextSpan(text: widget.farmer.name, style: pw.TextStyle(fontSize: detailTextSize, fontWeight: pw.FontWeight.bold)),
            ])),
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'S/O: ', style: pw.TextStyle(fontSize: detailTextSize, color: PdfColors.grey600)),
              pw.TextSpan(text: widget.farmer.fatherName ?? 'N/A', style: pw.TextStyle(fontSize: detailTextSize)),
            ])),
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Code: ', style: pw.TextStyle(fontSize: detailTextSize, color: PdfColors.grey600)),
              pw.TextSpan(text: widget.farmer.code, style: pw.TextStyle(fontSize: detailTextSize, fontWeight: pw.FontWeight.bold)),
            ])),
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Mobile: ', style: pw.TextStyle(fontSize: detailTextSize, color: PdfColors.grey600)),
              pw.TextSpan(text: widget.farmer.mobile, style: pw.TextStyle(fontSize: detailTextSize)),
            ])),
            pw.RichText(text: pw.TextSpan(children: [
              pw.TextSpan(text: 'Cattle: ', style: pw.TextStyle(fontSize: detailTextSize, color: PdfColors.grey600)),
              pw.TextSpan(text: widget.farmer.cattleType == 'buffalo' ? 'buffalo' : 'cow', style: pw.TextStyle(fontSize: detailTextSize)),
            ])),
          ],
        ),
      ),
      pw.SizedBox(height: sectionGap),

      // ===== BILLING PERIOD (Website Style: Centered, Bold) =====
      pw.Center(
        child: pw.Text(
          'Billing Period: ${DateFormat('dd/MM/yyyy').format(widget.startDate)} to ${DateFormat('dd/MM/yyyy').format(widget.endDate)}',
          style: pw.TextStyle(fontSize: billingSize, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: sectionGap),

      // ===== DAILY MILK COLLECTION DETAILS (Website Style) =====
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(vertical: isPrintMode ? 3 : 4, horizontal: 8),
        color: PdfColors.grey100,
        child: pw.Text('DAILY MILK COLLECTION DETAILS', style: pw.TextStyle(fontSize: sectionLabelSize, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
      ),
      pw.SizedBox(height: isPrintMode ? 2 : 4),
      
      // Table (Website Style: clean borders, centered text)
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: columnWidths,
        children: tableRows,
      ),
      pw.SizedBox(height: summaryGap),

      // ===== BOTTOM SUMMARY - Two Columns (Website Style) =====
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Left: MILK SUMMARY
          pw.Expanded(
            child: pw.Container(
              padding: pw.EdgeInsets.all(isPrintMode ? 6 : 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MILK SUMMARY', style: pw.TextStyle(fontSize: sectionLabelSize, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.SizedBox(height: isPrintMode ? 6 : 8),
                  _pdfRow('Morning Total:', '${morningTotal.toStringAsFixed(1)} L', ttf, boldTtf, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  _pdfRow('Evening Total:', '${eveningTotal.toStringAsFixed(1)} L', ttf, boldTtf, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                  _pdfRow('Grand Total:', '${widget.totalMilk.toStringAsFixed(1)} L', ttf, boldTtf, isBold: true, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: isPrintMode ? 8 : 12),
          // Right: PAYMENT SUMMARY
          pw.Expanded(
            child: pw.Container(
              padding: pw.EdgeInsets.all(isPrintMode ? 6 : 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PAYMENT SUMMARY', style: pw.TextStyle(fontSize: sectionLabelSize, fontWeight: pw.FontWeight.bold, color: PdfColors.grey600)),
                  pw.SizedBox(height: isPrintMode ? 6 : 8),
                  _pdfRow('Gross Amount:', '₹${widget.totalAmount.toStringAsFixed(0)}', ttf, boldTtf, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  _pdfRow('Less: Advance:', '- ₹${widget.totalAdvance.toStringAsFixed(0)}', ttf, boldTtf, isGrey: true, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  _pdfRow('Less: Paid:', '- ₹${widget.totalPaid.toStringAsFixed(0)}', ttf, boldTtf, isGrey: true, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  _pdfRow('Less: LBT:', '- ₹${widget.lbtAmount.toStringAsFixed(0)}', ttf, boldTtf, isGrey: true, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                  _pdfRow('Net Payable:', '₹${widget.netPayable.toStringAsFixed(0)}', ttf, boldTtf, isBold: true, fontSize: scaled(9, min: 7), paddingVertical: isPrintMode ? 1.5 : 2),
                ],
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: summaryGap),

      // ===== AMOUNT IN WORDS (Website Style: Yellow/Amber background) =====
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(vertical: isPrintMode ? 6 : 8, horizontal: 12),
        decoration: pw.BoxDecoration(
          color: PdfColors.amber50,
          border: pw.Border.all(color: PdfColors.amber200, width: 0.5),
        ),
        child: pw.Text(
          'Amount in Words: Rupees ${_numberToWords(widget.netPayable)} Only',
          style: pw.TextStyle(fontSize: scaled(9, min: 7), fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
      pw.SizedBox(height: signGap),

      // ===== SIGNATURE SECTION (Website Style) =====
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Farmer Signature', style: pw.TextStyle(fontSize: scaled(8, min: 6.5), color: PdfColors.grey500)),
              pw.SizedBox(height: signGap),
              pw.Container(width: 100, height: 0.5, color: PdfColors.grey400),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Authorized Signature', style: pw.TextStyle(fontSize: scaled(8, min: 6.5), color: PdfColors.grey500)),
              pw.SizedBox(height: signGap),
              pw.Container(width: 100, height: 0.5, color: PdfColors.grey400),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: isPrintMode ? 10 : 15),

      // ===== FOOTER (Website Style) =====
      pw.Divider(thickness: 0.5, color: PdfColors.grey300),
      pw.SizedBox(height: 4),
      pw.Center(
        child: pw.Text(
          'Computer generated invoice - ${widget.dairyName} - Powered by Dudh Passbook',
          style: pw.TextStyle(fontSize: footerSize, color: PdfColors.grey400),
        ),
      ),
    ];

    if (forceSinglePage) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(pageMargin),
          theme: pw.ThemeData.withFont(base: ttf, bold: boldTtf, fontFallback: [hindiTtf]),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            mainAxisSize: pw.MainAxisSize.min,
            children: content,
          ),
        ),
      );
    } else {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(pageMargin),
          theme: pw.ThemeData.withFont(base: ttf, bold: boldTtf, fontFallback: [hindiTtf]),
          build: (context) => content,
        ),
      );
    }

    return pdf.save();
  }

  // Helper: PDF Table Cell (Website style)
  pw.Widget _pdfCell(
    String text, {
    bool isHeader = false,
    required pw.Font ttf,
    double? fontSize,
    double? paddingVertical,
    double? paddingHorizontal,
  }) {
    final resolvedFontSize = fontSize ?? (isHeader ? 8 : 8);
    final resolvedPaddingV = paddingVertical ?? 5;
    final resolvedPaddingH = paddingHorizontal ?? 4;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: resolvedPaddingV, horizontal: resolvedPaddingH),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: ttf,
          fontSize: resolvedFontSize,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  // Helper: PDF Summary Row (Website style)
  pw.Widget _pdfRow(
    String label,
    String value,
    pw.Font ttf,
    pw.Font boldTtf, {
    bool isBold = false,
    bool isGrey = false,
    double? fontSize,
    double? paddingVertical,
  }) {
    final resolvedFontSize = fontSize ?? 9;
    final resolvedPaddingV = paddingVertical ?? 2;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: resolvedPaddingV),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: ttf, fontSize: resolvedFontSize, color: isGrey ? PdfColors.grey500 : PdfColors.black)),
          pw.Text(value, style: pw.TextStyle(font: isBold ? boldTtf : ttf, fontSize: resolvedFontSize, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  // Print Bill - Uses website-like generated PDF
  Future<void> _printBill() async {
    setState(() => _isGenerating = true);
    try {
      debugPrint('Print requested: entryCount=${_sortedEntries.length}');
      final pdfData = await _generatePdf(
        renderMode: BillRenderMode.print,
        previewEntries: _sortedEntries,
        shiftTotals: _shiftTotals,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => pdfData,
        name: 'Invoice_${widget.farmer.code}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error printing: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (!mounted) return;
    setState(() => _isGenerating = false);
  }

  // Share Bill as PDF - Uses website-like generated PDF
  Future<void> _shareBill() async {
    setState(() => _isGenerating = true);
    try {
      debugPrint('Share requested: entryCount=${_sortedEntries.length}');
      final pdfData = await _generatePdf(
        renderMode: BillRenderMode.share,
        previewEntries: _sortedEntries,
        shiftTotals: _shiftTotals,
      );
      final tempDir = await getTemporaryDirectory();
      final fileName = 'Invoice_${widget.farmer.code}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfData);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Bill Invoice for ${widget.farmer.name} - ${widget.dairyName}',
        subject: 'Milk Bill Invoice',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (!mounted) return;
    setState(() => _isGenerating = false);
  }
}
