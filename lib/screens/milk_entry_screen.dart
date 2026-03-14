import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../utils/theme_helper.dart';
import '../utils/rate_calculator.dart';
import '../utils/ui_helpers.dart';

class MilkEntryScreen extends StatefulWidget {
  const MilkEntryScreen({super.key});

  @override
  State<MilkEntryScreen> createState() => _MilkEntryScreenState();
}

class _MilkEntryScreenState extends State<MilkEntryScreen> with WidgetsBindingObserver {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _snfController = TextEditingController();

  Farmer? _selectedFarmer;
  List<Farmer> _allFarmers = [];
  String _shift = DateTime.now().hour < 14 ? 'morning' : 'evening';
  DateTime _selectedDate =
      DateTime.now(); // Entry date (can be changed for backdated entries)
  String _selectedCattleType = 'buffalo'; // Can be changed by user
  double _calculatedRate = 0.0;
  double _totalAmount = 0.0;
  bool _isLoading = false;
  bool _isSaving = false; // Double-tap guard
  bool _quickEntryMode = false; // Quick Entry Mode - pending FAT/SNF
  String _fixedRateEntryBehavior = 'pending'; // 'pending' or 'complete'
  List<MilkEntry> _todaysEntries = [];
  String _userRole = 'admin';
  int? _userId;
  int? _dairyId;

  // Rate calculator (shared utility)
  final RateCalculator _rateCalc = RateCalculator();
  // Debouncer for farmer code field — 1 second delay so user can finish typing multi-digit codes
  final Debouncer _codeDebouncer = Debouncer(delay: const Duration(milliseconds: 1000));

  // Warning message for FAT/cattle type mismatch
  String? _fatWarning;
  // Warning message for SNF range
  String? _snfWarning;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Professional Colors
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
    WidgetsBinding.instance.addObserver(this);
    _loadUserAndEntries();
    _codeController.addListener(_onCodeChangedDebounced);
    _quantityController.addListener(_calculateAmount);
    _fatController.addListener(_calculateAmount);
    _snfController.addListener(
      _calculateAmount,
    ); // Added SNF listener for real-time update
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadSettings();
    }
  }

  /// Reload only settings (lightweight, called when screen regains focus)
  Future<void> _reloadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _quickEntryMode = prefs.getBool('quickEntryMode') ?? false;
      _fixedRateEntryBehavior = prefs.getString('fixedRateEntryBehavior') ?? 'pending';
    });
  }

  Future<void> _loadUserAndEntries() async {
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('userRole') ?? 'admin';
    _userId = prefs.getInt('userId');
    _dairyId = prefs.getInt('dairyId');
    _quickEntryMode = prefs.getBool('quickEntryMode') ?? false;
    _fixedRateEntryBehavior = prefs.getString('fixedRateEntryBehavior') ?? 'pending';
    _languageCode = prefs.getString('language_code') ?? 'hi';

    // Load rate settings into shared calculator
    await _rateCalc.loadSettings(prefs);

    _loadTodaysEntries();
    _loadAllFarmers();
    _loadPendingEntries();
  }

  Future<void> _loadAllFarmers() async {
    try {
      _allFarmers = await _db.getAllFarmers(dairyId: _dairyId);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      _allFarmers = [];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeDebouncer.dispose();
    _codeController.dispose();
    _quantityController.dispose();
    _fatController.dispose();
    _snfController.dispose();
    super.dispose();
  }

  Future<void> _loadTodaysEntries() async {
    try {
      // Filter by dairyId to show only this dairy's entries
      // Staff can only see their own entries, Admin sees all dairy entries
      // BUG FIX: Use _selectedDate instead of DateTime.now() so backdated entries show correctly
      final entries = await _db.getMilkEntries(
        date: _selectedDate,
        createdByUserId: _userRole == 'staff' ? _userId : null,
        dairyId: _dairyId,
      );
      if (!mounted) return;
      setState(
        () => _todaysEntries = entries.where((e) => !e.isPending).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _todaysEntries = []);
    }
  }

  Future<void> _loadPendingEntries() async {
    try {
      await _db.getPendingEntries(
        createdByUserId: _userRole == 'staff' ? _userId : null,
        dairyId: _dairyId,
      );
      // Pending entries loaded
    } catch (e) {
      // No pending entries
    }
  }

  /// Debounced version — prevents DB query on every keystroke
  void _onCodeChangedDebounced() {
    _codeDebouncer.run(() => _onCodeChanged());
  }

  Future<void> _onCodeChanged() async {
    final code = _codeController.text.trim();
    if (code.isNotEmpty) {
      // Filter by dairyId to find only this dairy's farmers
      final farmer = await _db.getFarmerByCode(code, dairyId: _dairyId);
      // Guard: if user changed the code while we were querying, skip this result
      if (_codeController.text.trim() != code) return;
      if (!mounted) return;
      setState(() {
        _selectedFarmer = farmer;
        if (farmer != null) {
          _selectedCattleType =
              farmer.cattleType; // Set default to farmer's cattle type
        }
      });
      if (farmer != null) {
        _calculateAmount();
        // Check if this farmer has pending entries and show alert
        _checkFarmerPendingEntries(farmer);
      }
    } else {
      setState(() => _selectedFarmer = null);
    }
  }

  Future<void> _checkFarmerPendingEntries(Farmer farmer) async {
    try {
      final pendingEntries = await _db.getPendingEntries(
        dairyId: _dairyId,
      );
      final farmerPending = pendingEntries.where((e) => e.farmerId == farmer.id).toList();
      if (farmerPending.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
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
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isHindi ? 'पेंडिंग एंट्री!' : 'Pending Entry!',
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_rounded, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${farmer.name} (${farmer.code})',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isHindi
                      ? 'इस किसान की ${farmerPending.length} एंट्री पहले से पेंडिंग में है।\n\nक्या आप फिर भी नई एंट्री करना चाहते हैं?'
                      : 'This farmer already has ${farmerPending.length} entry pending.\n\nDo you still want to create a new entry?',
                  style: TextStyle(color: textLight, height: 1.5, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  _isHindi ? 'नहीं' : 'No',
                  style: TextStyle(color: textLight),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_isHindi ? 'हाँ, एंट्री करें' : 'Yes, Continue'),
              ),
            ],
          ),
        );

        if (proceed != true && mounted) {
          setState(() {
            _selectedFarmer = null;
            _codeController.clear();
          });
        }
      }
    } catch (e) {
    }
  }

  Future<void> _calculateAmount() async {
    if (_selectedFarmer == null) return;

    final quantity = double.tryParse(_quantityController.text) ?? 0.0;
    final fat = double.tryParse(_fatController.text) ?? 0.0;
    final snfText = _snfController.text.trim();
    final snfEntered = snfText.isNotEmpty && double.tryParse(snfText) != null;
    final snf =
        double.tryParse(snfText) ??
        (_selectedCattleType == 'cow' ? _rateCalc.cowDefaultSnf : 9.0);

    // Check for FAT/cattle type mismatch and set warning
    _checkFatWarning(fat);
    // Check SNF range warning
    _checkSnfWarning(double.tryParse(_snfController.text.trim()));

    // Check if farmer has a fixed rate for the selected milk type
    final fixedRateForType = _selectedFarmer!.getFixedRateForType(_selectedCattleType);
    final hasFixedRate = fixedRateForType != null;

    // Fixed rate path: only need quantity
    if (hasFixedRate) {
      if (quantity == 0) {
        setState(() { _calculatedRate = 0.0; _totalAmount = 0.0; });
        return;
      }
      // If FAT is provided, still use it for potential display but rate stays fixed
      double rate = fixedRateForType;
      setState(() {
        _calculatedRate = double.parse(rate.toStringAsFixed(2));
        _totalAmount = double.parse((quantity * rate).toStringAsFixed(2));
      });
      return;
    }

    // Formula-based rate path: need quantity + fat (+ snf)
    if (quantity == 0 || fat == 0) {
      setState(() { _calculatedRate = 0.0; _totalAmount = 0.0; });
      return;
    }

    // Wait for SNF to be entered for accurate rate calculation
    // (SNF affects the rate based on quality conditions)
    if (!snfEntered && !_quickEntryMode) {
      setState(() { _calculatedRate = 0.0; _totalAmount = 0.0; });
      return;
    }

    double rate = _calculateRateFromFormula(fat, snf);

    setState(() {
      _calculatedRate = double.parse(rate.toStringAsFixed(2));
      _totalAmount = double.parse((quantity * rate).toStringAsFixed(2));
    });
  }

  /// Check if FAT value matches the selected cattle type and show warning
  void _checkFatWarning(double fat) {
    if (fat <= 0) {
      setState(() => _fatWarning = null);
      return;
    }

    // General range warning takes priority
    if (fat > 15.0) {
      setState(() {
        _fatWarning = _isHindi
            ? '⚠️ FAT $fat% सामान्य सीमा (0-15%) से बाहर है / FAT $fat% is outside normal range (0-15%)'
            : '⚠️ FAT $fat% is outside normal range (0-15%)';
      });
    } else if (_selectedCattleType == 'buffalo' && fat < 5.1) {
      setState(() {
        _fatWarning = _isHindi
            ? '⚠️ FAT $fat% बहुत कम है भैंस के लिए! पशु प्रकार जांचें।'
            : '⚠️ FAT $fat% is too low for Buffalo milk. Check cattle type.';
      });
    } else if (_selectedCattleType == 'cow' && fat > 5.0) {
      setState(() {
        _fatWarning = _isHindi
            ? '⚠️ FAT $fat% बहुत ज्यादा है गाय के लिए! पशु प्रकार जांचें।'
            : '⚠️ FAT $fat% is too high for Cow milk. Check cattle type.';
      });
    } else {
      setState(() => _fatWarning = null);
    }
  }

  /// Check if SNF value is within normal range and show warning
  void _checkSnfWarning(double? snf) {
    if (snf == null || snf <= 0) {
      setState(() => _snfWarning = null);
      return;
    }

    if (snf < 5.0 || snf > 12.0) {
      setState(() {
        _snfWarning = _isHindi
            ? '⚠️ SNF $snf% सामान्य सीमा (5-12%) से बाहर है / SNF $snf% is outside normal range (5-12%)'
            : '⚠️ SNF $snf% is outside normal range (5-12%)';
      });
    } else {
      setState(() => _snfWarning = null);
    }
  }

  /// Calculate rate using shared RateCalculator utility
  double _calculateRateFromFormula(double fat, double snf) {
    return _rateCalc.calculateRate(_selectedCattleType, fat, snf);
  }

  Future<void> _submitEntry() async {
    if (_isSaving) return; // Prevent double-tap
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFarmer == null) {
      _showSnackBar('Please enter valid farmer code', isError: true);
      return;
    }

    // === INPUT VALIDATION ===
    final quantity = double.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      _showSnackBar(_isHindi ? 'सही लीटर दर्ज करें' : 'Enter valid quantity', isError: true);
      return;
    }
    if (quantity > 200) {
      _showSnackBar(_isHindi ? 'लीटर 200 से ज्यादा नहीं हो सकता' : 'Quantity cannot exceed 200 liters', isError: true);
      return;
    }

    // Re-read settings from prefs (ensures latest value after settings change)
    final _latestPrefs = await SharedPreferences.getInstance();
    final latestFixedRateBehavior = _latestPrefs.getString('fixedRateEntryBehavior') ?? 'pending';
    _fixedRateEntryBehavior = latestFixedRateBehavior; // Update cached value
    _quickEntryMode = _latestPrefs.getBool('quickEntryMode') ?? false; // Also refresh

    // Check if farmer has fixed rate for this cattle type (FAT/SNF become optional)
    final fixedRateForType = _selectedFarmer!.getFixedRateForType(_selectedCattleType);
    final hasFixedRate = fixedRateForType != null;
    final bool isFatEmpty = _fatController.text.trim().isEmpty;
    final bool isFixedRateQuantityOnly = hasFixedRate && isFatEmpty;

    // Check if Quick Entry Mode - FAT is optional (only when NO fixed rate)
    final bool isPendingEntry = _quickEntryMode && isFatEmpty && !hasFixedRate;

    // Determine if this entry should be pending or complete
    // Priority: fixedRate behavior > quickEntryMode > normal
    final bool shouldBePending;
    if (isFixedRateQuantityOnly) {
      // Farmer has fixed rate and FAT is empty — use the setting
      shouldBePending = latestFixedRateBehavior == 'pending';
    } else if (isPendingEntry) {
      shouldBePending = true; // Quick entry mode (no fixed rate) always pending
    } else {
      shouldBePending = false;
    }

    if (!isPendingEntry && !isFixedRateQuantityOnly) {
      // Normal entry — FAT is required when no fixed rate
      final fat = double.tryParse(_fatController.text);
      if (fat == null || fat <= 0 || fat > 15) {
        _showSnackBar(_isHindi ? 'FAT 0.1 से 15 के बीच होना चाहिए' : 'FAT must be between 0.1 and 15', isError: true);
        return;
      }
      if (_calculatedRate <= 0 || _totalAmount <= 0) {
        _showSnackBar(_isHindi ? 'रेट/राशि 0 है, कृपया जांचें' : 'Rate/Amount is 0, please check', isError: true);
        return;
      }
    }

    // For fixed-rate-complete, validate that rate/amount were calculated
    if (isFixedRateQuantityOnly && !shouldBePending) {
      if (_calculatedRate <= 0 || _totalAmount <= 0) {
        _showSnackBar(_isHindi ? 'रेट/राशि 0 है, कृपया जांचें' : 'Rate/Amount is 0, please check', isError: true);
        return;
      }
    }

    // === DUPLICATE ENTRY CHECK (includes cattleType) ===
    final existingEntries = await _db.getMilkEntries(
      date: _selectedDate,
      shift: _shift,
      farmerId: _selectedFarmer!.id!,
      dairyId: _dairyId,
    );
    // Filter by cattleType to allow cow + buffalo entries on same shift
    final sameCattleEntries = existingEntries.where(
      (e) => e.cattleType == _selectedCattleType,
    ).toList();
    if (sameCattleEntries.isNotEmpty) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(_isHindi ? 'डुप्लीकेट एंट्री!' : 'Duplicate Entry!'),
          ]),
          content: Text(
            _isHindi
                ? '${_selectedFarmer!.name} की ${_shift == "morning" ? "सुबह" : "शाम"} की एंट्री पहले से है। फिर भी जोड़ें?'
                : '${_selectedFarmer!.name} already has a ${_shift} entry for this date. Add anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_isHindi ? 'नहीं' : 'No')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(_isHindi ? 'हाँ, जोड़ें' : 'Yes, Add', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (overwrite != true) return;
    }

    if (!shouldBePending) {
      // Normal or fixed-rate-complete entry - show confirmation dialog before saving
      final confirmed = await _showConfirmationDialog();
      if (!confirmed) return;
    } else {
      // Pending entry (quick entry or fixed-rate-pending) - confirm pending
      final confirmed = await _showPendingConfirmationDialog();
      if (!confirmed) return;
    }

    setState(() {
      _isLoading = true;
      _isSaving = true;
    });

    try {
      // Get logged in user info
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId');
      final userName = prefs.getString('userName');
      final dairyId = prefs.getInt('dairyId');

      // Use selected date with current time for the entry
      final entryDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        DateTime.now().hour,
        DateTime.now().minute,
        DateTime.now().second,
      );

      final entry = MilkEntry(
        farmerId: _selectedFarmer!.id!,
        farmerCode: _selectedFarmer!.code,
        farmerName: _selectedFarmer!.name,
        dateTime: entryDateTime,
        shift: _shift,
        quantity: double.parse(_quantityController.text),
        fat: shouldBePending ? 0.0 : (_fatController.text.isNotEmpty ? double.parse(_fatController.text) : 0.0),
        snf: shouldBePending ? null : double.tryParse(_snfController.text),
        rate: shouldBePending ? 0.0 : _calculatedRate,
        amount: shouldBePending ? 0.0 : _totalAmount,
        cattleType: _selectedCattleType,
        isPending: shouldBePending,
        createdByUserId: userId,
        createdByUserName: userName,
        dairyId: dairyId,
      );

      await _syncService.addMilkEntryWithSync(entry, dairyId);

      // Show success popup
      if (shouldBePending) {
        await _showPendingSuccessDialog();
      } else {
        await _showSuccessDialog();
      }

      if (!mounted) return;
      _clearForm();
      _loadTodaysEntries();
      _loadPendingEntries();
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSaving = false;
        });
      }
    }
  }

  Future<bool> _showPendingConfirmationDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.pending_actions_rounded,
                      color: Colors.orange.shade700,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Save as Pending?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
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
                            Text(
                              'Farmer',
                              style: TextStyle(color: textLight),
                            ),
                            Text(
                              _selectedFarmer!.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Quantity',
                              style: TextStyle(color: textLight),
                            ),
                            Text(
                              '${_quantityController.text} L',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'FAT/SNF',
                              style: TextStyle(color: textLight),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Pending',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(color: Colors.grey.shade400),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: textLight),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Save Pending',
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
        ) ??
        false;
  }

  Future<void> _showPendingSuccessDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.pending_actions_rounded,
                color: Colors.orange.shade700,
                size: 50,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pending Entry Saved!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_quantityController.text} L',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'FAT/SNF बाद में add करें',
              style: TextStyle(fontSize: 13, color: textLight),
            ),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _showConfirmationDialog() async {
    // Colors for milk types
    const buffaloColor = Color(0xFF5C6BC0); // Indigo
    const cowColor = Color(0xFFFF9800); // Orange
    final milkColor = _selectedCattleType == 'buffalo'
        ? buffaloColor
        : cowColor;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              padding: const EdgeInsets.all(0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with gradient
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryGreen, primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Confirm Entry',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Body
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Farmer Info Row
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: primaryGreen,
                                radius: 22,
                                child: Text(
                                  _selectedFarmer!.code,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedFarmer!.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textDark,
                                      ),
                                    ),
                                    if (_selectedFarmer!.fatherName != null)
                                      Text(
                                        'S/o ${_selectedFarmer!.fatherName}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: textLight,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: milkColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _selectedCattleType == 'cow'
                                      ? '🐄 Cow'
                                      : '🐃 Buffalo',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Details Grid
                        Row(
                          children: [
                            _buildDetailBox(
                              'Shift',
                              _shift == 'morning' ? '🌅 Morning' : '🌙 Evening',
                              Colors.blue.shade100,
                              Colors.blue.shade700,
                            ),
                            const SizedBox(width: 10),
                            _buildDetailBox(
                              'Liters',
                              '${_quantityController.text} L',
                              Colors.teal.shade100,
                              Colors.teal.shade700,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildDetailBox(
                              'Fat',
                              '${_fatController.text}%',
                              Colors.orange.shade100,
                              Colors.orange.shade700,
                            ),
                            const SizedBox(width: 10),
                            _buildDetailBox(
                              'Rate',
                              '₹${_calculatedRate.toStringAsFixed(2)}',
                              Colors.purple.shade100,
                              Colors.purple.shade700,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Total Amount
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primaryGreen.withOpacity(0.1),
                                primaryGreen.withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: primaryGreen.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _isHindi ? 'कुल राशि' : 'Total Amount',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${_totalAmount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Buttons
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _isHindi ? 'बदलें' : 'Edit',
                              style: TextStyle(
                                color: textLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle_outline, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  _isHindi ? 'पुष्टि' : 'Confirm',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  Widget _buildDetailBox(
    String label,
    String value,
    Color bgColor,
    Color textColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.7)),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_rounded,
                color: primaryGreen,
                size: 60,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Entry Saved!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${_totalAmount.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: primaryGreen,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isHindi ? 'एंट्री सेव हो गई!' : 'Entry saved successfully!',
              style: TextStyle(fontSize: 14, color: textLight),
            ),
          ],
        ),
      ),
    );

    // Auto close after 1 second
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) Navigator.pop(context);
  }

  void _clearForm() {
    _codeController.clear();
    _quantityController.clear();
    _fatController.clear();
    _snfController.clear();
    setState(() {
      _selectedFarmer = null;
      _calculatedRate = 0.0;
      _totalAmount = 0.0;
      _selectedDate = DateTime.now(); // Reset to today after entry
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
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
    return Scaffold(
      backgroundColor: bgColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Shift Selection Card
            _buildDateShiftCard(),
            const SizedBox(height: 16),

            // Entry Form Card
            _buildFormCard(),
            const SizedBox(height: 16),

            // Today's Summary
            _buildTodaySummary(),
            const SizedBox(height: 16),

            // Recent Entries
            _buildRecentEntries(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildDateShiftCard() {
    final isToday =
        _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;
    final dateStr = isToday
        ? (_isHindi ? 'आज' : 'Today')
        : '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}';

    return Container(
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
          // Date Selection Row
          Row(
            children: [
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isToday
                        ? primaryGreen.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: isToday ? primaryGreen : Colors.orange,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: _pickDate,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entry Date',
                        style: TextStyle(
                          fontSize: 12,
                          color: isToday ? textLight : Colors.orange.shade700,
                        ),
                      ),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isToday ? textDark : Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Date Picker Button
              ElevatedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Change'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isToday ? bgColor : Colors.orange.shade100,
                  foregroundColor: isToday ? textDark : Colors.orange.shade800,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          if (!isToday) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isHindi ? 'पुरानी तारीख की एंट्री' : 'Backdated entry',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 24),
          // Shift Selection Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _shift == 'morning'
                      ? Icons.wb_sunny_rounded
                      : Icons.nights_stay_rounded,
                  color: primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift',
                      style: TextStyle(fontSize: 12, color: textLight),
                    ),
                    Text(
                      _shift == 'morning' ? (_isHindi ? 'सुबह' : 'Morning') : (_isHindi ? 'शाम' : 'Evening'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textDark,
                      ),
                    ),
                  ],
                ),
              ),
              // Toggle Shift
              Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildShiftButton('morning', 'AM', Icons.wb_sunny_outlined),
                    _buildShiftButton(
                      'evening',
                      'PM',
                      Icons.nights_stay_outlined,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(
        const Duration(days: 30),
      ), // Allow up to 30 days back
      lastDate: DateTime.now(), // No future dates
      helpText: _isHindi ? 'तारीख चुनें' : 'Select Entry Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: primaryGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: textDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadTodaysEntries(); // Reload entries for the new date
      HapticFeedback.selectionClick();
    }
  }

  Widget _buildShiftButton(String shift, String label, IconData icon) {
    final isSelected = _shift == shift;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _shift = shift);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : textLight),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: primaryGreen,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isHindi ? 'दूध एंट्री' : 'Milk Entry',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Farmer Code with Dropdown aligned
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _codeController,
                    label: _isHindi ? 'किसान कोड' : 'Farmer Code',
                    hint: 'Enter code',
                    icon: Icons.qr_code_rounded,
                    suffix: _selectedFarmer != null
                        ? const Icon(
                            Icons.check_circle,
                            color: Color(0xFF4CAF50),
                            size: 22,
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                // Dropdown button aligned with text field
                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primaryGreen.withOpacity(0.3)),
                  ),
                  child: PopupMenuButton<Farmer>(
                    icon: Icon(
                      Icons.person_search_rounded,
                      color: primaryGreen,
                      size: 26,
                    ),
                    tooltip: 'Select Farmer',
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    offset: const Offset(0, 50),
                    onSelected: (farmer) {
                      _codeController.text = farmer.code;
                      setState(() {
                        _selectedFarmer = farmer;
                        _selectedCattleType = farmer.cattleType;
                      });
                      _calculateAmount();
                    },
                    itemBuilder: (context) => _allFarmers.map((farmer) {
                      return PopupMenuItem<Farmer>(
                        value: farmer,
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: primaryGreen,
                              radius: 16,
                              child: Text(
                                farmer.code,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    farmer.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (farmer.fatherName != null)
                                    Text(
                                      'S/o ${farmer.fatherName}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Icon(
                              farmer.cattleType == 'cow'
                                  ? Icons.pets
                                  : Icons.water_drop,
                              size: 16,
                              color: Colors.grey.shade500,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            // Farmer Info Card
            if (_selectedFarmer != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      primaryGreen.withOpacity(0.08),
                      primaryGreen.withOpacity(0.03),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: primaryGreen.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: primaryGreen,
                          radius: 20,
                          child: Text(
                            _selectedFarmer!.name.isNotEmpty ? _selectedFarmer!.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedFarmer!.name,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textDark,
                                ),
                              ),
                              if (_selectedFarmer!.fatherName != null)
                                Text(
                                  'S/o ${_selectedFarmer!.fatherName}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: textLight,
                                  ),
                                ),
                              Text(
                                _selectedFarmer!.mobile,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Milk Type Selector with different colors
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // Buffalo - Indigo Color
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedCattleType = 'buffalo');
                                _calculateAmount();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedCattleType == 'buffalo'
                                      ? const Color(0xFF5C6BC0)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _selectedCattleType == 'buffalo'
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF5C6BC0,
                                            ).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('🐃', style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isHindi ? 'भैंस' : 'Buffalo',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedCattleType == 'buffalo'
                                            ? Colors.white
                                            : textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Cow - Orange Color
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedCattleType = 'cow');
                                _calculateAmount();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedCattleType == 'cow'
                                      ? const Color(0xFFFF9800)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _selectedCattleType == 'cow'
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFF9800,
                                            ).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('🐄', style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Text(
                                      _isHindi ? 'गाय' : 'Cow',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _selectedCattleType == 'cow'
                                            ? Colors.white
                                            : textLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Quick Entry Mode Indicator
            if (_quickEntryMode) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.flash_on_rounded,
                      color: Colors.orange.shade700,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Entry Mode Active',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'FAT/SNF optional - बाद में add करें',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Quantity & Fat in Row
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _quantityController,
                    label: 'Liters',
                    hint: '0.0',
                    icon: Icons.water_drop_outlined,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _fatController,
                    label: _quickEntryMode ? 'Fat % (Optional)' : 'Fat %',
                    hint: '0.0',
                    icon: Icons.percent_rounded,
                    keyboardType: TextInputType.number,
                    isRequired:
                        !_quickEntryMode, // Optional in Quick Entry Mode
                  ),
                ),
              ],
            ),

            // FAT Warning for cattle type mismatch
            if (_fatWarning != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fatWarning!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // SNF
            _buildTextField(
              controller: _snfController,
              label: 'SNF % (Optional)',
              hint: '0.0',
              icon: Icons.science_outlined,
              keyboardType: TextInputType.number,
              isRequired: false,
            ),

            // SNF Warning for out-of-range value
            if (_snfWarning != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _snfWarning!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Amount Display
            if (_totalAmount > 0) _buildAmountCard(),
            if (_totalAmount > 0) const SizedBox(height: 20),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: (_isLoading || _isSaving) ? null : _submitEntry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_rounded, size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Save Entry',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    bool isRequired = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: textLight,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 16, color: textDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: primaryGreen, size: 22),
            suffixIcon: suffix,
            filled: true,
            fillColor: bgColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryGreen, width: 1.5),
            ),
          ),
          validator: isRequired
              ? (value) => value == null || value.isEmpty ? 'Required' : null
              : null,
        ),
      ],
    );
  }

  Widget _buildAmountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryGreen, primaryDark]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rate: ₹${_calculatedRate.toStringAsFixed(2)}/L',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Total Amount',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
          Text(
            '₹${_totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodaySummary() {
    final totalLiters = _todaysEntries.fold<double>(
      0,
      (sum, e) => sum + e.quantity,
    );
    final totalAmount = _todaysEntries.fold<double>(
      0,
      (sum, e) => sum + e.amount,
    );

    return Container(
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
      child: Row(
        children: [
          _buildSummaryItem(
            'Today',
            '${_todaysEntries.length}',
            'Entries',
            Icons.format_list_numbered_rounded,
            accentBlue,
          ),
          Container(width: 1, height: 40, color: Colors.grey.shade200),
          _buildSummaryItem(
            'Total',
            totalLiters.toStringAsFixed(1),
            'Liters',
            Icons.water_drop_rounded,
            primaryGreen,
          ),
          Container(width: 1, height: 40, color: Colors.grey.shade200),
          _buildSummaryItem(
            'Amount',
            '₹${totalAmount.toStringAsFixed(0)}',
            'Total',
            Icons.currency_rupee_rounded,
            const Color(0xFFFF9800),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: textLight),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentEntries() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: accentBlue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Recent Entries',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textDark,
              ),
            ),
            const Spacer(),
            Text(
              '${_todaysEntries.length} today',
              style: TextStyle(fontSize: 12, color: textLight),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_todaysEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 48,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No entries yet today',
                    style: TextStyle(color: textLight, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(
            _todaysEntries.length > 5 ? 5 : _todaysEntries.length,
            (index) => _buildEntryCard(_todaysEntries[index]),
          ),
      ],
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
                  '${entry.quantity}L • Fat: ${entry.fat}%',
                  style: TextStyle(fontSize: 12, color: textLight),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${entry.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: primaryGreen,
                ),
              ),
              Text(
                entry.farmerCode,
                style: TextStyle(fontSize: 11, color: textLight),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
