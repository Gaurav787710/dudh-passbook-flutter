import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import '../models/farmer.dart';
import 'entry_history_screen.dart';
import '../utils/theme_helper.dart';
import '../utils/ui_helpers.dart';

class FarmersScreen extends StatefulWidget {
  const FarmersScreen({super.key});

  @override
  State<FarmersScreen> createState() => _FarmersScreenState();
}

class _FarmersScreenState extends State<FarmersScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final FirestoreSyncService _syncService = FirestoreSyncService.instance;
  List<Farmer> _farmers = [];
  List<Farmer> _filteredFarmers = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  int? _dairyId;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

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
    _loadUserAndFarmers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserAndFarmers() async {
    final prefs = await SharedPreferences.getInstance();
    _dairyId = prefs.getInt('dairyId');
    _languageCode = prefs.getString('language_code') ?? 'hi';
    _loadFarmers();
  }

  Future<void> _loadFarmers() async {
    setState(() => _isLoading = true);
    try {
      // Filter by dairyId to show only this dairy's farmers
      _farmers = await _db.getAllFarmers(dairyId: _dairyId);
      _filteredFarmers = _farmers;
    } catch (e) {
      _farmers = [];
      _filteredFarmers = [];
      debugPrint('[FarmersScreen] load error: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  void _filterFarmers(String query) {
    setState(() {
      _filteredFarmers = _farmers
          .where((farmer) =>
              farmer.name.toLowerCase().contains(query.toLowerCase()) ||
              farmer.code.toLowerCase().contains(query.toLowerCase()) ||
              farmer.mobile.contains(query))
          .toList();
    });
  }

  void _showAddEditDialog([Farmer? farmer]) async {
    final isEdit = farmer != null;
    
    // Auto-generate farmer code for new farmer
    String autoCode = '';
    if (!isEdit) {
      autoCode = await _db.getNextFarmerCode(dairyId: _dairyId);
    }
    
    final codeController = TextEditingController(text: farmer?.code ?? autoCode);
    final nameController = TextEditingController(text: farmer?.name ?? '');
    final fatherNameController = TextEditingController(text: farmer?.fatherName ?? '');
    final mobileController = TextEditingController(text: farmer?.mobile ?? '');
    String cattleType = farmer?.cattleType ?? 'buffalo';
    bool useFixedRate = farmer?.useFixedRate ?? false;
    final cowRateController = TextEditingController(
      text: farmer?.cowFixedRate?.toString() ?? farmer?.fixedRate?.toString() ?? '',
    );
    final buffaloRateController = TextEditingController(
      text: farmer?.buffaloFixedRate?.toString() ?? farmer?.fixedRate?.toString() ?? '',
    );
    // Pre-populate: if editing old farmer with single fixedRate, put it in correct field
    if (isEdit && farmer!.useFixedRate && farmer.fixedRate != null) {
      if (farmer.cowFixedRate == null && farmer.buffaloFixedRate == null) {
        // Legacy single rate — assign to the farmer's default cattle type
        if (farmer.cattleType == 'cow') {
          cowRateController.text = farmer.fixedRate!.toString();
          buffaloRateController.text = '';
        } else {
          buffaloRateController.text = farmer.fixedRate!.toString();
          cowRateController.text = '';
        }
      } else {
        cowRateController.text = farmer.cowFixedRate?.toString() ?? '';
        buffaloRateController.text = farmer.buffaloFixedRate?.toString() ?? '';
      }
    }

    bool isSaving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isEdit ? Icons.edit_rounded : Icons.person_add_rounded,
                        color: primaryGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isEdit
                          ? (_isHindi ? 'किसान संपादित करें' : 'Edit Farmer')
                          : (_isHindi ? 'किसान जोड़ें' : 'Add Farmer'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Code Field
                _buildFormField(
                  controller: codeController,
                  label: _isHindi ? 'किसान कोड' : 'Farmer Code',
                  icon: Icons.qr_code_rounded,
                  enabled: !isEdit,
                  isRequired: true,
                ),
                const SizedBox(height: 16),
                
                // Name Field
                _buildFormField(
                  controller: nameController,
                  label: _isHindi ? 'नाम' : 'Name',
                  icon: Icons.person_rounded,
                  isRequired: true,
                ),
                const SizedBox(height: 16),
                
                // Father Name Field
                _buildFormField(
                  controller: fatherNameController,
                  label: _isHindi ? 'पिता का नाम' : 'Father Name',
                  icon: Icons.family_restroom_rounded,
                ),
                const SizedBox(height: 16),
                
                // Mobile Field
                _buildFormField(
                  controller: mobileController,
                  label: _isHindi ? 'मोबाइल' : 'Mobile',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  isRequired: true,
                ),
                const SizedBox(height: 16),
                
                // Cattle Type
                Text(
                  _isHindi ? 'पशु प्रकार' : 'Cattle Type',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildCattleOption(
                        'cow',
                        _isHindi ? 'गाय' : 'Cow',
                        Icons.pets_rounded,
                        cattleType == 'cow',
                        () => setDialogState(() => cattleType = 'cow'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCattleOption(
                        'buffalo',
                        _isHindi ? 'भैंस' : 'Buffalo',
                        Icons.water_drop_rounded,
                        cattleType == 'buffalo',
                        () => setDialogState(() => cattleType = 'buffalo'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Fixed Rate Toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.currency_rupee_rounded, color: primaryGreen, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isHindi ? 'फिक्स रेट इस्तेमाल करें' : 'Use Fixed Rate',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              _isHindi ? 'गाय और भैंस के लिए अलग रेट' : 'Set separate rates for cow & buffalo',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: useFixedRate,
                        onChanged: (value) => setDialogState(() => useFixedRate = value),
                        activeThumbColor: primaryGreen,
                      ),
                    ],
                  ),
                ),
                
                if (useFixedRate) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFormField(
                          controller: cowRateController,
                          label: _isHindi ? 'गाय रेट (₹)' : 'Cow Rate (₹)',
                          icon: Icons.pets_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildFormField(
                          controller: buffaloRateController,
                          label: _isHindi ? 'भैंस रेट (₹)' : 'Buffalo Rate (₹)',
                          icon: Icons.water_drop_rounded,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isHindi
                        ? 'खाली छोड़ें = FAT/SNF से कैलकुलेट होगा'
                        : 'Leave empty = calculated from FAT/SNF',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 24),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: textLight)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Validate required fields
                          final List<String> missingFields = [];
                          if (codeController.text.trim().isEmpty) {
                            missingFields.add(_isHindi ? 'किसान कोड' : 'Farmer Code');
                          }
                          if (nameController.text.trim().isEmpty) {
                            missingFields.add(_isHindi ? 'नाम' : 'Name');
                          }
                          if (mobileController.text.trim().isEmpty) {
                            missingFields.add(_isHindi ? 'मोबाइल' : 'Mobile');
                          }

                          if (missingFields.isNotEmpty) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                                    const SizedBox(width: 10),
                                    Text(_isHindi ? 'अधूरी जानकारी' : 'Missing Info'),
                                  ],
                                ),
                                content: Text(
                                  _isHindi
                                      ? 'कृपया भरें: ${missingFields.join(', ')}'
                                      : 'Please fill: ${missingFields.join(', ')}',
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(_isHindi ? 'ठीक है' : 'OK'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          // Validate mobile number: must be exactly 10 digits starting with 6-9
                          final mobile = mobileController.text.trim();
                          final mobileRegex = RegExp(r'^[6-9]\d{9}$');
                          if (!mobileRegex.hasMatch(mobile)) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: Row(
                                  children: [
                                    Icon(Icons.phone_android_rounded, color: Colors.red.shade600),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isHindi ? 'गलत मोबाइल नंबर' : 'Invalid Mobile',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                content: Text(
                                  _isHindi
                                      ? 'कृपया सही 10 अंक का मोबाइल नंबर डालें (6-9 से शुरू)'
                                      : 'Please enter a valid 10-digit mobile number starting with 6-9',
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: Text(_isHindi ? 'ठीक है' : 'OK'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          if (isSaving) return;
                          setDialogState(() => isSaving = true);

                          final newFarmer = Farmer(
                            id: farmer?.id,
                            code: codeController.text,
                            name: nameController.text,
                            fatherName: fatherNameController.text.isNotEmpty ? fatherNameController.text : null,
                            mobile: mobileController.text,
                            cattleType: cattleType,
                            useFixedRate: useFixedRate,
                            fixedRate: null, // Legacy field — no longer used for new saves
                            cowFixedRate: useFixedRate
                                ? double.tryParse(cowRateController.text)
                                : null,
                            buffaloFixedRate: useFixedRate
                                ? double.tryParse(buffaloRateController.text)
                                : null,
                            dairyId: _dairyId,
                          );

                          // Capture ScaffoldMessenger BEFORE pop to avoid using invalidated dialog context
                          final scaffoldMessenger = ScaffoldMessenger.of(context);

                          try {
                            if (isEdit) {
                              await _syncService.updateFarmerWithSync(newFarmer, _dairyId);
                            } else {
                              await _syncService.addFarmerWithSync(newFarmer, _dairyId);
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              _loadFarmers();
                              HapticFeedback.mediumImpact();
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(isEdit
                                      ? 'Farmer updated successfully'
                                      : 'Farmer added successfully'),
                                  backgroundColor: primaryGreen,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: Colors.red.shade600,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          } finally {
                            isSaving = false;
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(
                          isEdit
                              ? (_isHindi ? 'अपडेट करें' : 'Update')
                              : (_isHindi ? 'सेव करें' : 'Save'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool enabled = true,
    bool isRequired = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            if (isRequired)
              Text(' *', style: TextStyle(color: Colors.red.shade600, fontSize: 14, fontWeight: FontWeight.bold)),
            if (!enabled) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded, size: 14, color: Colors.grey.shade400),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          enabled: enabled,
          style: TextStyle(
            fontSize: 16,
            color: enabled ? textDark : Colors.grey.shade600,
          ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: enabled ? primaryGreen : Colors.grey.shade400, size: 22),
            suffixIcon: !enabled ? Icon(Icons.lock_rounded, color: Colors.grey.shade400, size: 18) : null,
            filled: true,
            fillColor: enabled ? bgColor : Colors.grey.shade100,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryGreen, width: 1.5),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCattleOption(String value, String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? primaryGreen.withOpacity(0.1) : bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryGreen : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? primaryGreen : textLight,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? primaryGreen : textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.currency_rupee_rounded, size: 12, color: color),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBeforeEdit(Farmer farmer) async {
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
                _isHindi ? 'किसान एडिट करें?' : 'Edit Farmer?',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          _isHindi
              ? 'क्या आप वाकई "${farmer.name}" की जानकारी एडिट करना चाहते हैं?'
              : 'Are you sure you want to edit "${farmer.name}" details?',
          style: TextStyle(color: textLight, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: textLight)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'हाँ, एडिट करें' : 'Yes, Edit'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _showAddEditDialog(farmer);
    }
  }

  void _deleteFarmer(Farmer farmer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            Text(_isHindi ? 'किसान हटाएं?' : 'Delete Farmer?', style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isHindi
                  ? 'क्या आप वाकई ${farmer.name} को डिलीट करना चाहते हैं?'
                  : 'Are you sure you want to delete ${farmer.name}?',
              style: TextStyle(color: textLight, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade600, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isHindi
                          ? '⚠️ इस किसान की सभी दूध एंट्री, पेमेंट और एडवांस भी डिलीट हो जाएंगे! यह बदलाव पूर्ववत नहीं किया जा सकता।'
                          : '⚠️ All milk entries, payments and advances for this farmer will also be permanently deleted! This cannot be undone.',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w500),
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
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: textLight)),
          ),
          ElevatedButton(
            onPressed: () async {
              // Capture ScaffoldMessenger BEFORE pop to avoid using invalidated dialog context
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                await _syncService.deleteFarmerWithSync(farmer, _dairyId);
                if (mounted) {
                  Navigator.pop(context);
                  _loadFarmers();
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: const Text('Farmer deleted successfully'),
                      backgroundColor: Colors.red.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Error deleting farmer: $e'),
                      backgroundColor: Colors.red.shade600,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'डिलीट करें' : 'Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: primaryGreen,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Container(
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
              child: TextField(
                controller: _searchController,
                onChanged: _filterFarmers,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: _isHindi ? 'नाम, कोड या मोबाइल से खोजें...' : 'Search by name, code or mobile...',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search_rounded, color: primaryGreen),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: textLight),
                          onPressed: () {
                            _searchController.clear();
                            _filterFarmers('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
          ),
          
          // Stats Row
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
                  _isHindi ? 'सभी किसान' : 'All Farmers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _isHindi ? 'कुल ${_filteredFarmers.length}' : '${_filteredFarmers.length} total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          // Farmers List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  )
                : _filteredFarmers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: Icon(
                                Icons.people_outline_rounded,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _isHindi ? 'कोई किसान नहीं मिला' : 'No farmers found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredFarmers.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) => _buildFarmerCard(_filteredFarmers[index]),
                      ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildFarmerCard(Farmer farmer) {
    final isCow = farmer.cattleType == 'cow';
    final cattleColor = isCow ? Colors.brown : accentBlue;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Navigate to entry history filtered by this farmer
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EntryHistoryScreen(
                  initialFarmerId: farmer.id,
                  initialFarmerName: farmer.name,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cattleColor.withOpacity(0.15),
                        cattleColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      farmer.name.isNotEmpty ? farmer.name[0].toUpperCase() : 'F',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: cattleColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              farmer.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: cattleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCow ? 'COW' : 'BUFFALO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: cattleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.qr_code_rounded, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            farmer.code,
                            style: TextStyle(fontSize: 13, color: textLight),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.phone_rounded, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            farmer.mobile,
                            style: TextStyle(fontSize: 13, color: textLight),
                          ),
                        ],
                      ),
                      if (farmer.useFixedRate && (farmer.cowFixedRate != null || farmer.buffaloFixedRate != null || farmer.fixedRate != null)) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (farmer.cowFixedRate != null)
                              _buildRateBadge('COW ₹${farmer.cowFixedRate}', Colors.brown),
                            if (farmer.buffaloFixedRate != null)
                              _buildRateBadge('BUF ₹${farmer.buffaloFixedRate}', accentBlue),
                            // Legacy single rate (no per-type rates set)
                            if (farmer.cowFixedRate == null && farmer.buffaloFixedRate == null && farmer.fixedRate != null)
                              _buildRateBadge('Fixed ₹${farmer.fixedRate}', primaryGreen),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Action Buttons - Professional horizontal style
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: primaryGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _confirmBeforeEdit(farmer),
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.edit_rounded, color: primaryGreen, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Material(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _deleteFarmer(farmer),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
