import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firestore_sync_service.dart';
import '../utils/rate_calculator.dart';

class RateChartScreen extends StatefulWidget {
  const RateChartScreen({super.key});

  @override
  State<RateChartScreen> createState() => _RateChartScreenState();
}

class _RateChartScreenState extends State<RateChartScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;
  bool _isLoading = true;

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Rate calculator (shared utility)
  final RateCalculator _rateCalc = RateCalculator();

  // Professional Colors
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryOrange = Color(0xFFEF6C00);
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textLight = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _languageCode = prefs.getString('language_code') ?? 'hi';

    // पहले Firestore से latest settings लोड करें (server = source of truth)
    try {
      final firestoreSettings = await _syncService.loadRateSettings();
      if (firestoreSettings != null) {
        // Firestore से मिला — local prefs में भी save करो
        final keys = [
          'buffaloPerKgFatRate', 'cowEfuRate', 'cowDefaultSnf',
          'buffaloSnf88to89Deduction', 'buffaloSnf85to87Deduction',
          'buffaloSnf84Penalty', 'buffaloLowQualityPenalty',
          'cowSnf83to84Deduction', 'cowSnf81to82Deduction',
          'cowHighFatDeduction', 'cowSnf80Penalty', 'cowLowFatPenalty',
        ];
        for (final key in keys) {
          final val = firestoreSettings[key];
          if (val != null) await prefs.setDouble(key, (val as num).toDouble());
        }
      }
    } catch (_) {
      // Firestore fail हो तो local prefs से चलेगा
    }

    await _rateCalc.loadSettings(prefs);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('buffaloPerKgFatRate', _rateCalc.buffaloPerKgFatRate);
    await prefs.setDouble('cowEfuRate', _rateCalc.cowEfuRate);
    await prefs.setDouble('cowDefaultSnf', _rateCalc.cowDefaultSnf);

    // Save SNF deduction settings
    await prefs.setDouble(
      'buffaloSnf88to89Deduction',
      _rateCalc.buffaloSnf88to89Deduction,
    );
    await prefs.setDouble(
      'buffaloSnf85to87Deduction',
      _rateCalc.buffaloSnf85to87Deduction,
    );
    await prefs.setDouble('buffaloSnf84Penalty', _rateCalc.buffaloSnf84Penalty);
    await prefs.setDouble(
      'buffaloLowQualityPenalty',
      _rateCalc.buffaloLowQualityPenalty,
    );

    await prefs.setDouble('cowSnf83to84Deduction', _rateCalc.cowSnf83to84Deduction);
    await prefs.setDouble('cowSnf81to82Deduction', _rateCalc.cowSnf81to82Deduction);
    await prefs.setDouble('cowHighFatDeduction', _rateCalc.cowHighFatDeduction);
    await prefs.setDouble('cowSnf80Penalty', _rateCalc.cowSnf80Penalty);
    await prefs.setDouble('cowLowFatPenalty', _rateCalc.cowLowFatPenalty);

    // Sync rate settings to Firestore for staff access
    try {
      await _syncService.syncRateSettings(
        buffaloPerKgFatRate: _rateCalc.buffaloPerKgFatRate,
        cowEfuRate: _rateCalc.cowEfuRate,
        cowDefaultSnf: _rateCalc.cowDefaultSnf,
        buffaloSnf88to89Deduction: _rateCalc.buffaloSnf88to89Deduction,
        buffaloSnf85to87Deduction: _rateCalc.buffaloSnf85to87Deduction,
        buffaloSnf84Penalty: _rateCalc.buffaloSnf84Penalty,
        buffaloLowQualityPenalty: _rateCalc.buffaloLowQualityPenalty,
        cowSnf83to84Deduction: _rateCalc.cowSnf83to84Deduction,
        cowSnf81to82Deduction: _rateCalc.cowSnf81to82Deduction,
        cowHighFatDeduction: _rateCalc.cowHighFatDeduction,
        cowSnf80Penalty: _rateCalc.cowSnf80Penalty,
        cowLowFatPenalty: _rateCalc.cowLowFatPenalty,
      );
    } catch (e) {
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _showSnackBar('Settings saved successfully!');
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showEditRateModal(String cattleType) {
    final isBuffalo = cattleType == 'buffalo';
    final rateController = TextEditingController(
      text: isBuffalo
          ? _rateCalc.buffaloPerKgFatRate.toString()
          : _rateCalc.cowEfuRate.toString(),
    );
    final snfController = TextEditingController(
      text: _rateCalc.cowDefaultSnf.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isBuffalo
                              ? primaryBlue.withOpacity(0.1)
                              : primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.water_drop_rounded,
                          color: isBuffalo ? primaryBlue : primaryOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isBuffalo
                            ? 'Buffalo Rate Settings'
                            : 'Cow Rate Settings',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                isBuffalo ? 'Per KG Fat Rate (₹)' : 'EFU Rate (₹)',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rateController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: isBuffalo ? '820' : '382.69',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: bgColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),

              if (!isBuffalo) ...[
                const SizedBox(height: 16),
                Text(
                  'Default SNF (%)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: snfController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '8.5',
                    suffixText: '%',
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isBuffalo
                            ? 'Formula: Rate = FAT × Per KG Fat Rate / 100'
                            : 'Formula: Rate = (FAT + SNF×⅔) × EFU Rate / 100',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                        setState(() {
                          if (isBuffalo) {
                            _rateCalc.buffaloPerKgFatRate =
                                double.tryParse(rateController.text) ?? 820;
                          } else {
                            _rateCalc.cowEfuRate =
                                double.tryParse(rateController.text) ?? 382.69;
                            _rateCalc.cowDefaultSnf =
                                double.tryParse(snfController.text) ?? 8.5;
                          }
                        });
                        _saveSettings();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isBuffalo
                            ? primaryBlue
                            : primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Settings',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Advanced SNF Settings Button
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showSnfSettingsModal(cattleType);
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: Text(
                  isBuffalo
                      ? 'SNF Deduction Settings (Buffalo)'
                      : 'SNF Deduction Settings (Cow)',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: isBuffalo ? primaryBlue : primaryOrange,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnfSettingsModal(String cattleType) {
    final isBuffalo = cattleType == 'buffalo';

    // Controllers for Buffalo SNF settings
    final buffaloSnf88to89Controller = TextEditingController(
      text: _rateCalc.buffaloSnf88to89Deduction.toString(),
    );
    final buffaloSnf85to87Controller = TextEditingController(
      text: _rateCalc.buffaloSnf85to87Deduction.toString(),
    );
    final buffaloSnf84Controller = TextEditingController(
      text: _rateCalc.buffaloSnf84Penalty.toString(),
    );
    final buffaloLowQualityController = TextEditingController(
      text: _rateCalc.buffaloLowQualityPenalty.toString(),
    );

    // Controllers for Cow SNF settings
    final cowSnf83to84Controller = TextEditingController(
      text: _rateCalc.cowSnf83to84Deduction.toString(),
    );
    final cowSnf81to82Controller = TextEditingController(
      text: _rateCalc.cowSnf81to82Deduction.toString(),
    );
    final cowHighFatController = TextEditingController(
      text: _rateCalc.cowHighFatDeduction.toString(),
    );
    final cowSnf80Controller = TextEditingController(
      text: _rateCalc.cowSnf80Penalty.toString(),
    );
    final cowLowFatController = TextEditingController(
      text: _rateCalc.cowLowFatPenalty.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isBuffalo
                              ? primaryBlue.withOpacity(0.1)
                              : primaryOrange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.science_outlined,
                          color: isBuffalo ? primaryBlue : primaryOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isBuffalo ? 'Buffalo SNF Settings' : 'Cow SNF Settings',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Info box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.blue.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isHindi
                            ? 'इन settings से आप SNF के हिसाब से rate में deduction customize कर सकते हैं'
                            : 'These settings let you customize rate deductions based on SNF levels',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: isBuffalo
                      ? _buildBuffaloSnfSettings(
                          buffaloSnf88to89Controller,
                          buffaloSnf85to87Controller,
                          buffaloSnf84Controller,
                          buffaloLowQualityController,
                        )
                      : _buildCowSnfSettings(
                          cowSnf83to84Controller,
                          cowSnf81to82Controller,
                          cowHighFatController,
                          cowSnf80Controller,
                          cowLowFatController,
                        ),
                ),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
                        setState(() {
                          if (isBuffalo) {
                            _rateCalc.buffaloSnf88to89Deduction =
                                double.tryParse(
                                  buffaloSnf88to89Controller.text,
                                ) ??
                                2.0;
                            _rateCalc.buffaloSnf85to87Deduction =
                                double.tryParse(
                                  buffaloSnf85to87Controller.text,
                                ) ??
                                4.0;
                            _rateCalc.buffaloSnf84Penalty =
                                double.tryParse(buffaloSnf84Controller.text) ??
                                75.0;
                            _rateCalc.buffaloLowQualityPenalty =
                                double.tryParse(
                                  buffaloLowQualityController.text,
                                ) ??
                                75.0;
                          } else {
                            _rateCalc.cowSnf83to84Deduction =
                                double.tryParse(cowSnf83to84Controller.text) ??
                                2.0;
                            _rateCalc.cowSnf81to82Deduction =
                                double.tryParse(cowSnf81to82Controller.text) ??
                                4.0;
                            _rateCalc.cowHighFatDeduction =
                                double.tryParse(cowHighFatController.text) ??
                                15.0;
                            _rateCalc.cowSnf80Penalty =
                                double.tryParse(cowSnf80Controller.text) ??
                                75.0;
                            _rateCalc.cowLowFatPenalty =
                                double.tryParse(cowLowFatController.text) ??
                                50.0;
                          }
                        });
                        _saveSettings();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isBuffalo
                            ? primaryBlue
                            : primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save SNF Settings',
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
  }

  Widget _buildBuffaloSnfSettings(
    TextEditingController snf88to89,
    TextEditingController snf85to87,
    TextEditingController snf84,
    TextEditingController lowQuality,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSnfSettingField(
          label: 'SNF 8.8-8.9% Deduction',
          hint: 'Deduction %',
          controller: snf88to89,
          description: 'Rate में कितने % की कटौती (Default: 2%)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'SNF 8.5-8.7% Deduction',
          hint: 'Deduction %',
          controller: snf85to87,
          description: 'Rate में कितने % की कटौती (Default: 4%)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'SNF 8.4% Penalty',
          hint: 'Penalty %',
          controller: snf84,
          description: 'Rate का कितना % काटना है (Default: 75% = 25% payment)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'Low Quality Penalty (FAT ≤5.0 & SNF ≤9.0)',
          hint: 'Penalty %',
          controller: lowQuality,
          description: 'Rate का कितना % काटना है (Default: 75% = 25% payment)',
        ),
      ],
    );
  }

  Widget _buildCowSnfSettings(
    TextEditingController snf83to84,
    TextEditingController snf81to82,
    TextEditingController highFat,
    TextEditingController snf80,
    TextEditingController lowFat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSnfSettingField(
          label: 'SNF 8.3-8.4% Deduction',
          hint: 'Deduction %',
          controller: snf83to84,
          description: 'Rate में कितने % की कटौती (Default: 2%)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'SNF 8.1-8.2% Deduction',
          hint: 'Deduction %',
          controller: snf81to82,
          description: 'Rate में कितने % की कटौती (Default: 4%)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'High FAT (≥5.1%) Deduction',
          hint: 'Deduction %',
          controller: highFat,
          description: 'Cow में ज्यादा FAT पर कटौती (Default: 15%)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'SNF 8.0% Penalty',
          hint: 'Penalty %',
          controller: snf80,
          description: 'Rate का कितना % काटना है (Default: 75% = 25% payment)',
        ),
        const SizedBox(height: 16),
        _buildSnfSettingField(
          label: 'Low FAT (3.0-3.2%) Penalty',
          hint: 'Penalty %',
          controller: lowFat,
          description: 'Cow में कम FAT पर Penalty (Default: 50% = 50% payment)',
        ),
      ],
    );
  }

  Widget _buildSnfSettingField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: '%',
            filled: true,
            fillColor: bgColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: textDark,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isHindi ? 'रेट चार्ट' : 'Rate Chart',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: primaryBlue,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: primaryBlue,
                    unselectedLabelColor: textLight,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.water_drop_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(_isHindi ? 'भैंस' : 'Buffalo'),
                          ],
                        ),
                      ),
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.water_drop_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(_isHindi ? 'गाय' : 'Cow'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildBuffaloChart(), _buildCowChart()],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBuffaloChart() {
    // Buffalo FAT range: 5.0% to 9.0%
    final fatValues = List.generate(
      41,
      (i) => 5.0 + i * 0.1,
    ).map((v) => (v * 10).round() / 10.0).toList();

    return Column(
      children: [
        // Rate Settings Header
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryBlue.withOpacity(0.1),
                primaryBlue.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryBlue.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryBlue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isHindi ? 'प्रति किलो फैट' : 'Per KG Fat Rate',
                      style: TextStyle(fontSize: 12, color: textLight),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₹${_rateCalc.buffaloPerKgFatRate.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryBlue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Per KG',
                            style: TextStyle(
                              fontSize: 10,
                              color: primaryBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '6.0% FAT = ₹${_rateCalc.calcBuffaloBaseRate(6.0).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEditRateModal('buffalo'),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Rate Chart Grid
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.table_chart_rounded,
                            size: 18,
                            color: primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Rate Chart (FAT 5.0% - 9.0%)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${fatValues.length} rates',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 500
                          ? 6
                          : 4,
                      childAspectRatio: 1.2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: fatValues.length,
                    itemBuilder: (context, index) {
                      final fat = fatValues[index];
                      final rate = _rateCalc.calcBuffaloBaseRate(fat);
                      return Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'FAT ${fat.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${rate.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCowChart() {
    // Cow FAT range: 3.3% to 5.5%
    final fatValues = List.generate(
      23,
      (i) => 3.3 + i * 0.1,
    ).map((v) => (v * 10).round() / 10.0).toList();

    return Column(
      children: [
        // Rate Settings Header
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryOrange.withOpacity(0.1),
                primaryOrange.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: primaryOrange.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.water_drop_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EFU Rate Method',
                      style: TextStyle(fontSize: 12, color: textLight),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₹${_rateCalc.cowEfuRate.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryOrange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SNF ${_rateCalc.cowDefaultSnf.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 9,
                              color: primaryOrange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '4.0% FAT = ₹${_rateCalc.calcCowBaseRate(4.0, _rateCalc.cowDefaultSnf).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _showEditRateModal('cow'),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Rate Chart Grid
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.table_chart_rounded,
                            size: 18,
                            color: primaryOrange,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Rate Chart (FAT 3.3% - 5.5%)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${fatValues.length} rates',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: MediaQuery.of(context).size.width > 500
                          ? 6
                          : 4,
                      childAspectRatio: 1.2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: fatValues.length,
                    itemBuilder: (context, index) {
                      final fat = fatValues[index];
                      final rate = _rateCalc.calcCowBaseRate(fat, _rateCalc.cowDefaultSnf);
                      return Container(
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'FAT ${fat.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${rate.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Formula Info
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calculate_rounded,
                color: Colors.amber.shade700,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isHindi ? 'EFU सूत्र' : 'EFU Formula',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rate = (FAT + SNF×⅔) × EFU Rate ÷ 100',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
