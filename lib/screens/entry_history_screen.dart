import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/milk_entry.dart';
import '../services/firestore_sync_service.dart';
import '../utils/theme_helper.dart';
import '../utils/rate_calculator.dart';
import '../utils/ui_helpers.dart';

/// Sorting options for entry list
enum EntrySortOption {
  farmerCode,
  farmerName,
  newestFirst,
  oldestFirst,
  quantityHigh,
}

extension EntrySortLabel on EntrySortOption {
  String get label {
    switch (this) {
      case EntrySortOption.farmerCode:
        return 'Farmer Code';
      case EntrySortOption.farmerName:
        return 'Farmer Name (A-Z)';
      case EntrySortOption.newestFirst:
        return 'Newest First';
      case EntrySortOption.oldestFirst:
        return 'Oldest First';
      case EntrySortOption.quantityHigh:
        return 'Quantity (High→Low)';
    }
  }

  IconData get icon {
    switch (this) {
      case EntrySortOption.farmerCode:
        return Icons.tag_rounded;
      case EntrySortOption.farmerName:
        return Icons.sort_by_alpha_rounded;
      case EntrySortOption.newestFirst:
        return Icons.arrow_downward_rounded;
      case EntrySortOption.oldestFirst:
        return Icons.arrow_upward_rounded;
      case EntrySortOption.quantityHigh:
        return Icons.water_drop_rounded;
    }
  }
}

/// Centralized sorting function — shared between Admin & Staff
List<MilkEntry> sortEntries(List<MilkEntry> entries, EntrySortOption sort) {
  final sorted = List<MilkEntry>.from(entries);
  switch (sort) {
    case EntrySortOption.farmerCode:
      sorted.sort((a, b) => a.farmerCode.compareTo(b.farmerCode));
      break;
    case EntrySortOption.farmerName:
      sorted.sort((a, b) => a.farmerName.toLowerCase().compareTo(b.farmerName.toLowerCase()));
      break;
    case EntrySortOption.newestFirst:
      sorted.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      break;
    case EntrySortOption.oldestFirst:
      sorted.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      break;
    case EntrySortOption.quantityHigh:
      sorted.sort((a, b) => b.quantity.compareTo(a.quantity));
      break;
  }
  return sorted;
}

class EntryHistoryScreen extends StatefulWidget {
  final int? initialFarmerId;
  final String? initialFarmerName;

  const EntryHistoryScreen({
    super.key,
    this.initialFarmerId,
    this.initialFarmerName,
  });

  @override
  State<EntryHistoryScreen> createState() => _EntryHistoryScreenState();
}

class _EntryHistoryScreenState extends State<EntryHistoryScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;
  List<MilkEntry> _entries = [];
  List<MilkEntry> _pendingEntries = [];
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _farmerList = [];
  bool _isLoading = true;
  String _selectedFilter = 'today';
  String _userRole = 'staff';
  int? _userId;
  int? _dairyId;
  int? _selectedStaffId;
  int? _selectedFarmerId; // New: Filter by farmer
  DateTime _selectedDate = DateTime.now();
  late TabController _tabController;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Cached totals (avoid recomputing in build)
  double _cachedTotalLiters = 0;
  double _cachedTotalAmount = 0;
  bool _isProcessing = false; // Double-tap guard for edit/delete/complete

  // Sort state
  EntrySortOption _currentSort = EntrySortOption.newestFirst;

  // Rate calculator (shared utility)
  final RateCalculator _rateCalc = RateCalculator();

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark => _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get accentBlue => const Color(0xFF1976D2);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // If initial farmer filter is set, use 'all' filter and pre-select farmer
    if (widget.initialFarmerId != null) {
      _selectedFilter = 'all';
      _selectedFarmerId = widget.initialFarmerId;
    }
    _loadUserAndEntries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndEntries() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole') ?? 'staff';
    _userId = prefs.getInt('userId');
    _dairyId = prefs.getInt('dairyId');
    _languageCode = prefs.getString('language_code') ?? 'hi';

    // Load rate settings into shared calculator
    await _rateCalc.loadSettings(prefs);

    if (_userRole == 'admin') {
      await _loadStaffList();
    }

    await _loadFarmerList();
    await _loadEntries();
    await _loadPendingEntries();
  }

  Future<void> _loadFarmerList() async {
    try {
      final farmers = await _db.getAllFarmers(dairyId: _dairyId);
      _farmerList = farmers
          .map((f) => {'id': f.id, 'name': f.name, 'code': f.code})
          .toList();
    } catch (e) {
      _farmerList = [];
    }
  }

  Future<void> _loadStaffList() async {
    try {
      final allUsers = await _db.getAllUsers(dairyId: _dairyId);
      _staffList = allUsers.where((u) => u['role'] == 'staff').toList();
    } catch (e) {
      _staffList = [];
    }
  }

  Future<void> _loadPendingEntries() async {
    try {
      int? filterUserId;
      if (_userRole == 'staff') {
        filterUserId = _userId;
      } else if (_selectedStaffId != null) {
        filterUserId = _selectedStaffId;
      }

      _pendingEntries = await _db.getPendingEntries(
        createdByUserId: filterUserId,
        dairyId: _dairyId,
      );

      // Filter by farmer if selected
      if (_selectedFarmerId != null) {
        _pendingEntries = _pendingEntries
            .where((e) => e.farmerId == _selectedFarmerId)
            .toList();
      }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _pendingEntries = [];
    }
  }

  // Calculate rate based on formula from shared RateCalculator
  double _calculateRateFromFormula(String cattleType, double fat, double? snf) {
    return _rateCalc.calculateRate(cattleType, fat, snf);
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);

    try {
      DateTime? startDate;
      DateTime? endDate = DateTime.now();

      if (_selectedFilter == 'today') {
        startDate = DateTime(endDate.year, endDate.month, endDate.day);
      } else if (_selectedFilter == 'week') {
        startDate = endDate.subtract(const Duration(days: 7));
      } else if (_selectedFilter == 'date') {
        startDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        endDate = startDate.add(const Duration(days: 1));
      } else {
        startDate = DateTime(2020);
      }

      int? filterUserId;
      if (_userRole == 'staff') {
        filterUserId = _userId;
      } else if (_selectedStaffId != null) {
        filterUserId = _selectedStaffId;
      }

      _entries = await _db.getMilkEntriesForBilling(
        startDate: startDate,
        endDate: endDate,
        createdByUserId: filterUserId,
        dairyId: _dairyId,
      );

      _entries = _entries.where((e) => !e.isPending).toList();

      // Filter by farmer if selected
      if (_selectedFarmerId != null) {
        _entries = _entries
            .where((e) => e.farmerId == _selectedFarmerId)
            .toList();
      }
    } catch (e) {
      _entries = [];
    }

    // Cache totals once after loading
    _cachedTotalLiters = _entries.fold<double>(0, (sum, e) => sum + e.quantity);
    _cachedTotalAmount = _entries.fold<double>(0, (sum, e) => sum + e.amount);

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedFilter = 'date';
      });
      _loadEntries();
    }
  }

  bool _canEditDelete(MilkEntry entry) {
    if (_userRole == 'admin') return true;
    final difference = DateTime.now().difference(entry.dateTime);
    return difference.inMinutes < 2;
  }

  Future<void> _deleteEntry(MilkEntry entry) async {
    if (!_canEditDelete(entry)) {
      _showSnackBar('2 मिनट के बाद delete नहीं कर सकते', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.delete_rounded,
                color: Colors.red.shade600,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Delete Entry?', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.farmerName} - ${entry.quantity}L'),
            Text(
              'Amount: ₹${entry.amount.toStringAsFixed(0)}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            const Text(
              '',
              style: TextStyle(fontSize: 13),
            ),
            Text(
              _isHindi ? 'क्या आप इस एंट्री को डिलीट करना चाहते हैं?' : 'Do you want to delete this entry?',
              style: const TextStyle(fontSize: 13),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _syncService.deleteMilkEntryWithSync(entry, _dairyId);
      _showSnackBar('Entry deleted successfully');
      _loadEntries();
      _loadPendingEntries();
    }
  }

  Future<void> _editEntry(MilkEntry entry) async {
    if (!_canEditDelete(entry)) {
      _showSnackBar(_isHindi ? '2 मिनट के बाद edit नहीं कर सकते' : 'Cannot edit after 2 minutes', isError: true);
      return;
    }

    // Confirmation dialog before edit
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.edit_rounded, color: Colors.orange.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isHindi ? 'एंट्री एडिट करें?' : 'Edit Entry?',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          _isHindi
              ? 'क्या आप वाकई इस एंट्री को एडिट करना चाहते हैं?\n\n${entry.farmerName} - ${entry.quantity}L'
              : 'Are you sure you want to edit this entry?\n\n${entry.farmerName} - ${entry.quantity}L',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'हाँ, एडिट करें' : 'Yes, Edit'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final quantityController = TextEditingController(
      text: entry.quantity.toString(),
    );
    final fatController = TextEditingController(text: entry.fat.toString());
    final snfController = TextEditingController(
      text: entry.snf?.toString() ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.edit_rounded, color: primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit Entry',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.farmerName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      entry.farmerCode,
                      style: TextStyle(color: textLight),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantity (L)',
                  prefixIcon: const Icon(Icons.water_drop_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: bgColor,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: fatController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'FAT %',
                        prefixIcon: const Icon(Icons.percent),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: bgColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: snfController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'SNF %',
                        prefixIcon: const Icon(Icons.science_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: bgColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final quantity = double.tryParse(
                          quantityController.text,
                        );
                        final fat = double.tryParse(fatController.text);
                        if (quantity == null || fat == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter valid values'),
                            ),
                          );
                          return;
                        }

                        double rate = entry.rate;
                        final farmer = await _db.getFarmerByCode(
                          entry.farmerCode,
                          dairyId: _dairyId,
                        );
                        if (farmer != null &&
                            farmer.useFixedRate &&
                            farmer.fixedRate != null) {
                          rate = farmer.fixedRate!;
                        } else {
                          // Use formula-based rate calculation
                          rate = _calculateRateFromFormula(
                            entry.cattleType,
                            fat,
                            double.tryParse(snfController.text),
                          );
                        }

                        final updatedEntry = MilkEntry(
                          id: entry.id,
                          farmerId: entry.farmerId,
                          farmerCode: entry.farmerCode,
                          farmerName: entry.farmerName,
                          dateTime: entry.dateTime,
                          shift: entry.shift,
                          quantity: quantity,
                          fat: fat,
                          snf: double.tryParse(snfController.text),
                          rate: rate,
                          amount: quantity * rate,
                          cattleType: entry.cattleType,
                          isPending: false,
                          createdByUserId: entry.createdByUserId,
                          createdByUserName: entry.createdByUserName,
                          dairyId: entry.dairyId,
                          syncId: entry.syncId, // BUG FIX: preserve syncId for Firestore update
                        );

                        await _syncService.updateMilkEntryWithSync(
                          updatedEntry,
                          _dairyId,
                        );
                        Navigator.pop(dialogCtx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      _showSnackBar('Entry updated successfully');
      _loadEntries();
    }
  }

  Future<void> _completePendingEntry(MilkEntry entry) async {
    if (_isProcessing) return;
    final fatController = TextEditingController();
    final snfController = TextEditingController();
    double calculatedRate = 0.0;
    double calculatedAmount = 0.0;

    final result = await showDialog<Map<String, double>?>(
      context: context,
      builder: (dialogCtx2) => StatefulBuilder(
        builder: (dialogCtx2, setDialogState) {
          void calculatePreview() {
            final fat = double.tryParse(fatController.text) ?? 0.0;
            final snf =
                double.tryParse(snfController.text) ??
                (entry.cattleType.toLowerCase() == 'cow'
                    ? _rateCalc.cowDefaultSnf
                    : 9.0);

            if (fat > 0) {
              calculatedRate = _calculateRateFromFormula(
                entry.cattleType,
                fat,
                snf,
              );
              calculatedAmount = entry.quantity * calculatedRate;
            } else {
              calculatedRate = 0.0;
              calculatedAmount = 0.0;
            }
            setDialogState(() {});
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryGreen.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.science_rounded,
                      color: primaryGreen,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Complete Entry',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'FAT और SNF add करें',
                    style: TextStyle(fontSize: 13, color: textLight),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.farmerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${entry.farmerCode} • ${entry.cattleType}',
                              style: TextStyle(
                                fontSize: 12,
                                color: textLight,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${entry.quantity} L',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: primaryGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: fatController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    onChanged: (_) => calculatePreview(),
                    decoration: InputDecoration(
                      labelText: 'FAT %',
                      prefixIcon: const Icon(Icons.percent_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: bgColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: snfController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => calculatePreview(),
                    decoration: InputDecoration(
                      labelText: 'SNF % (Optional)',
                      prefixIcon: const Icon(Icons.science_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: bgColor,
                    ),
                  ),

                  // Rate and Amount Preview
                  if (calculatedRate > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: primaryGreen.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Rate',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textLight,
                                ),
                              ),
                              Text(
                                '₹${calculatedRate.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 30,
                            color: primaryGreen.withOpacity(0.3),
                          ),
                          Column(
                            children: [
                              Text(
                                'Amount',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: textLight,
                                ),
                              ),
                              Text(
                                '₹${calculatedAmount.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1B5E20),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogCtx2),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            final fat = double.tryParse(fatController.text);
                            if (fat == null || fat <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter valid FAT %'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(dialogCtx2, {
                              'fat': fat,
                              'snf': double.tryParse(snfController.text) ??
                                (entry.cattleType.toLowerCase() == 'cow'
                                    ? _rateCalc.cowDefaultSnf
                                    : 9.0),
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Complete',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );

    if (result != null) {
      _isProcessing = true;
      try {
      // Network check — pending entry completion requires Firestore sync
      final hasNet = await hasInternetConnection();
      if (!hasNet && mounted) {
        await showNoInternetDialog(context, isHindi: _isHindi);
        return;
      }
      try {
        double rate = 0.0;
        final farmer = await _db.getFarmerByCode(
          entry.farmerCode,
          dairyId: _dairyId,
        );
        if (farmer != null && farmer.useFixedRate && farmer.fixedRate != null) {
          rate = farmer.fixedRate!;
        } else {
          // Use formula-based rate calculation
          rate = _calculateRateFromFormula(
            entry.cattleType,
            result['fat']!,
            result['snf'],
          );
        }

        final updatedEntry = MilkEntry(
          id: entry.id,
          farmerId: entry.farmerId,
          farmerCode: entry.farmerCode,
          farmerName: entry.farmerName,
          dateTime: entry.dateTime,
          shift: entry.shift,
          quantity: entry.quantity,
          fat: result['fat']!,
          snf: result['snf'],
          rate: rate,
          amount: entry.quantity * rate,
          cattleType: entry.cattleType,
          isPending: false,
          createdByUserId: entry.createdByUserId,
          createdByUserName: entry.createdByUserName,
          dairyId: entry.dairyId,
          syncId: entry.syncId, // BUG FIX: preserve syncId so Firestore update finds the right doc
        );

        await _syncService.updateMilkEntryWithSync(updatedEntry, _dairyId);
        if (!mounted) return;
        _showSnackBar(
          'Entry completed! ₹${updatedEntry.amount.toStringAsFixed(0)}',
        );
        _loadPendingEntries();
        _loadEntries();
      } catch (e) {
        _showSnackBar('Error: $e', isError: true);
      }
      } finally {
        _isProcessing = false;
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalLiters = _cachedTotalLiters;
    final totalAmount = _cachedTotalAmount;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: widget.initialFarmerId != null
          ? AppBar(
              backgroundColor: cardColor,
              elevation: 0.5,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: textDark),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.initialFarmerName ?? (_isHindi ? 'एंट्री इतिहास' : 'Entry History'),
                style: TextStyle(color: textDark, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            )
          : null,
      body: Column(
        children: [
          // Tabs: Completed / Pending
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: textLight,
              indicator: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              padding: const EdgeInsets.all(4),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'Completed',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.pending_actions, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Pending (${_pendingEntries.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Filters Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _buildMiniFilterTab('today', 'Today'),
                        _buildMiniFilterTab('week', '7 Days'),
                        _buildMiniFilterTab('all', 'All'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _selectDate,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _selectedFilter == 'date'
                          ? primaryGreen
                          : cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      color: _selectedFilter == 'date'
                          ? Colors.white
                          : primaryGreen,
                      size: 22,
                    ),
                  ),
                ),
                if (_userRole == 'admin' && _staffList.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedStaffId,
                        hint: const Text(
                          'Staff',
                          style: TextStyle(fontSize: 13),
                        ),
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: primaryGreen,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Staff',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          ..._staffList.map(
                            (staff) => DropdownMenuItem<int?>(
                              value: staff['id'],
                              child: Text(
                                staff['name'] ?? '',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedStaffId = value);
                          _loadEntries();
                          _loadPendingEntries();
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Farmer Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_search_rounded,
                    color: primaryGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedFarmerId,
                        isExpanded: true,
                        hint: Text(
                          _isHindi ? 'सभी किसान' : 'All Farmers',
                          style: const TextStyle(fontSize: 13),
                        ),
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: primaryGreen,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'All Farmers',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          ..._farmerList.map(
                            (farmer) => DropdownMenuItem<int?>(
                              value: farmer['id'],
                              child: Text(
                                '${farmer['code']} - ${farmer['name']}',
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedFarmerId = value);
                          _loadEntries();
                          _loadPendingEntries();
                        },
                      ),
                    ),
                  ),
                  if (_selectedFarmerId != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      color: Colors.grey,
                      onPressed: () {
                        setState(() => _selectedFarmerId = null);
                        _loadEntries();
                        _loadPendingEntries();
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Summary Cards - Compact
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCompactStat(
                    Icons.format_list_numbered_rounded,
                    '${_entries.length}',
                    'Entries',
                    accentBlue,
                  ),
                  Container(width: 1, height: 24, color: Colors.grey.shade200),
                  _buildCompactStat(
                    Icons.water_drop_rounded,
                    '${totalLiters.toStringAsFixed(1)}L',
                    'Liters',
                    primaryGreen,
                  ),
                  Container(width: 1, height: 24, color: Colors.grey.shade200),
                  _buildCompactStat(
                    Icons.currency_rupee_rounded,
                    '₹${totalAmount.toStringAsFixed(0)}',
                    'Amount',
                    const Color(0xFFFF9800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Sort By Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.sort_rounded, size: 18, color: primaryGreen),
                  const SizedBox(width: 8),
                  Text(
                    _isHindi ? 'क्रम:' : 'Sort:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textLight),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<EntrySortOption>(
                        value: _currentSort,
                        isExpanded: true,
                        icon: Icon(Icons.arrow_drop_down, color: primaryGreen),
                        style: TextStyle(fontSize: 13, color: textDark),
                        items: EntrySortOption.values.map((opt) {
                          return DropdownMenuItem<EntrySortOption>(
                            value: opt,
                            child: Row(
                              children: [
                                Icon(opt.icon, size: 16, color: primaryGreen),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(opt.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: textDark)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _currentSort = val);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Completed Entries Tab
                _isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: primaryGreen),
                      )
                    : _entries.isEmpty
                    ? _buildEmptyState(
                        _isHindi ? 'कोई पूर्ण एंट्री नहीं' : 'No completed entries',
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _loadEntries();
                          await _loadPendingEntries();
                        },
                        color: primaryGreen,
                        child: Builder(
                          builder: (context) {
                            final sorted = sortEntries(_entries, _currentSort);
                            return ListView.builder(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
                              itemCount: sorted.length,
                              itemBuilder: (context, index) => _buildEntryCard(
                                sorted[index],
                                isPending: false,
                              ),
                            );
                          },
                        ),
                      ),
                // Pending Entries Tab
                _pendingEntries.isEmpty
                    ? _buildEmptyState(
                        _isHindi ? 'कोई पेंडिंग एंट्री नहीं' : 'No pending entries',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPendingEntries,
                        color: primaryGreen,
                        child: Builder(
                          builder: (context) {
                            final sorted = sortEntries(_pendingEntries, _currentSort);
                            return ListView.builder(
                              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
                              itemCount: sorted.length,
                              itemBuilder: (context, index) => _buildEntryCard(
                                sorted[index],
                                isPending: true,
                              ),
                            );
                          },
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFilterTab(String value, String label) {
    final isSelected = _selectedFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedFilter = value);
          _loadEntries();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : textLight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStat(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 9, color: textLight)),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              Icons.inbox_rounded,
              size: 50,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(MilkEntry entry, {required bool isPending}) {
    final isMorning = entry.shift == 'morning';
    final canEdit = _canEditDelete(entry);

    final card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: isPending
            ? Border.all(color: Colors.orange.shade300, width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Farmer Code Badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isPending
                    ? Colors.orange.shade50
                    : (isMorning
                          ? Colors.amber.shade50
                          : Colors.indigo.shade50),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isPending
                      ? Colors.orange.shade200
                      : (isMorning
                            ? Colors.amber.shade200
                            : Colors.indigo.shade200),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  entry.farmerCode,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isPending
                        ? Colors.orange.shade700
                        : (isMorning ? Colors.amber.shade800 : Colors.indigo),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Entry Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.farmerName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPending) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PENDING',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isMorning ? Icons.wb_sunny : Icons.nights_stay,
                        size: 11,
                        color: isMorning ? Colors.amber : Colors.indigo,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _formatDate(entry.dateTime),
                        style: TextStyle(fontSize: 10, color: textLight),
                      ),
                      Text(
                        ' • ',
                        style: TextStyle(fontSize: 10, color: textLight),
                      ),
                      Text(
                        '${entry.quantity}L',
                        style: TextStyle(
                          fontSize: 10,
                          color: textLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!isPending) ...[
                        Text(
                          ' • ',
                          style: TextStyle(fontSize: 10, color: textLight),
                        ),
                        Text(
                          'F:${entry.fat}%',
                          style: TextStyle(
                            fontSize: 10,
                            color: textLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (entry.createdByUserName != null && _userRole == 'admin')
                    Text(
                      'By: ${entry.createdByUserName}',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            // Amount and Actions Column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isPending ? 'Pending' : '₹${entry.amount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isPending ? Colors.orange.shade700 : primaryGreen,
                  ),
                ),
                const SizedBox(height: 4),
                // Action Buttons Row
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPending)
                      _buildActionButton(
                        icon: Icons.check_circle_outline,
                        color: primaryGreen,
                        onTap: () => _completePendingEntry(entry),
                        tooltip: 'Complete',
                      ),
                    if (canEdit && !isPending)
                      _buildActionButton(
                        icon: Icons.edit_outlined,
                        color: accentBlue,
                        onTap: () => _editEntry(entry),
                        tooltip: 'Edit',
                      ),
                    if (canEdit)
                      _buildActionButton(
                        icon: Icons.delete_outline,
                        color: Colors.red.shade600,
                        onTap: () => _deleteEntry(entry),
                        tooltip: 'Delete',
                      ),
                    if (!canEdit && !isPending && _userRole == 'staff')
                      Text(
                        '2m',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    // PART 2: Wrap entire pending card in InkWell for tap-to-complete
    if (isPending) {
      return InkWell(
        onTap: () => _completePendingEntry(entry),
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.orange.withOpacity(0.1),
        highlightColor: Colors.orange.withOpacity(0.05),
        child: card,
      );
    }

    return card;
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final entryDate = DateTime(date.year, date.month, date.day);

    String timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    if (entryDate == today) {
      return 'Today $timeStr';
    } else if (entryDate == yesterday) {
      return 'Yesterday $timeStr';
    } else {
      return '${date.day}/${date.month} $timeStr';
    }
  }
}
