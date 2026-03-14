import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_sync_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Profile data
  String _userName = '';
  String _userMobile = '';
  String _userEmail = '';
  String _userRole = '';
  String _dairyName = '';
  String _dairyAddress = '';
  String _dairyVillage = '';
  String _dairyCity = '';
  String _dairyState = '';
  String _dairyPincode = '';
  String _dairyContact = '';
  String _managerMobile = '';
  String _tagline = '';
  String _signatureLabel = '';

  // Professional Colors
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // First load from local cache
    if (!mounted) return;
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'hi';
      _userName = prefs.getString('userName') ?? firebaseUser?.displayName ?? '';
      _userMobile = prefs.getString('userMobile') ?? firebaseUser?.phoneNumber ?? '';
      _userEmail = prefs.getString('userEmail') ?? firebaseUser?.email ?? '';
      _userRole = prefs.getString('userRole') ?? 'admin';
      _dairyName = prefs.getString('dairyName') ?? prefs.getString('dairy_name') ?? '';
      _dairyAddress = prefs.getString('dairy_address') ?? '';
      _dairyVillage = prefs.getString('dairy_village') ?? '';
      _dairyCity = prefs.getString('dairy_city') ?? '';
      _dairyState = prefs.getString('dairy_state') ?? '';
      _dairyPincode = prefs.getString('dairy_pincode') ?? '';
      _dairyContact = prefs.getString('dairy_contact') ?? prefs.getString('userMobile') ?? '';
      _managerMobile = prefs.getString('managerMobile') ?? '';
      _tagline = prefs.getString('tagline') ?? '';
      _signatureLabel = prefs.getString('signatureLabel') ?? '';
    });

    // Then load fresh data from Firestore server
    try {
      final syncService = FirestoreSyncService.instance;
      if (syncService.isAuthenticated && firebaseUser != null) {
        final doc = await syncService.getUserProfileFromServer();
        if (doc != null && mounted) {
          setState(() {
            _userName = doc['name'] as String? ?? _userName;
            _userEmail = doc['email'] as String? ?? firebaseUser.email ?? _userEmail;
            _userMobile = doc['mobile'] as String? ?? _userMobile;
            _dairyName = doc['dairyName'] as String? ?? _dairyName;
            _dairyAddress = doc['address'] as String? ?? _dairyAddress;
            _dairyVillage = doc['village'] as String? ?? _dairyVillage;
            _dairyCity = doc['city'] as String? ?? _dairyCity;
            _dairyState = doc['state'] as String? ?? _dairyState;
            _dairyPincode = doc['pincode'] as String? ?? _dairyPincode;
            _dairyContact = doc['mobile'] as String? ?? _dairyContact;
            _managerMobile = doc['managerMobile'] as String? ?? _managerMobile;
            _tagline = doc['tagline'] as String? ?? _tagline;
            _signatureLabel = doc['signatureLabel'] as String? ?? _signatureLabel;
          });

          // Update SharedPreferences cache with fresh server data
          await prefs.setString('userName', _userName);
          await prefs.setString('userEmail', _userEmail);
          await prefs.setString('userMobile', _userMobile);
          await prefs.setString('dairyName', _dairyName);
          await prefs.setString('dairy_address', _dairyAddress);
          await prefs.setString('dairy_village', _dairyVillage);
          await prefs.setString('dairy_city', _dairyCity);
          await prefs.setString('dairy_state', _dairyState);
          await prefs.setString('dairy_pincode', _dairyPincode);
          await prefs.setString('dairy_contact', _dairyContact);
          await prefs.setString('managerMobile', _managerMobile);
          await prefs.setString('tagline', _tagline);
          await prefs.setString('signatureLabel', _signatureLabel);
        }
      }
    } catch (e) {
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _userRole == 'admin';

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // Profile Header
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryGreen, primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 30),
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                        ),
                        child: Icon(
                          isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _userName.isNotEmpty ? _userName : (_isHindi ? 'नाम सेट करें' : 'Set Name'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isAdmin ? (_isHindi ? 'एडमिन / मालिक' : 'Admin / Owner') : (_isHindi ? 'स्टाफ' : 'Staff'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Profile Details
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Personal Info Card
                  _buildSectionCard(
                    title: _isHindi ? 'व्यक्तिगत जानकारी' : 'Personal Information',
                    icon: Icons.person_outline_rounded,
                    children: [
                      _buildInfoTile(Icons.person_rounded, _isHindi ? 'नाम' : 'Name', _userName),
                      _buildInfoTile(Icons.phone_rounded, _isHindi ? 'मोबाइल' : 'Mobile', _userMobile),
                      _buildInfoTile(Icons.email_rounded, _isHindi ? 'ईमेल' : 'Email', _userEmail),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Dairy Info Card
                  _buildSectionCard(
                    title: _isHindi ? 'डेयरी जानकारी' : 'Dairy Information',
                    icon: Icons.store_rounded,
                    children: [
                      _buildInfoTile(Icons.store_rounded, _isHindi ? 'डेयरी का नाम' : 'Dairy Name', _dairyName),
                      _buildInfoTile(Icons.phone_rounded, _isHindi ? 'संपर्क' : 'Contact', _dairyContact),
                      if (_managerMobile.isNotEmpty)
                        _buildInfoTile(Icons.phone_android_rounded, _isHindi ? 'मैनेजर मोबाइल' : 'Manager Mobile', _managerMobile),
                      if (_tagline.isNotEmpty)
                        _buildInfoTile(Icons.format_quote_rounded, _isHindi ? 'टैगलाइन' : 'Tagline', _tagline),
                      if (_signatureLabel.isNotEmpty)
                        _buildInfoTile(Icons.draw_rounded, _isHindi ? 'हस्ताक्षर लेबल' : 'Signature Label', _signatureLabel),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Address Card
                  _buildSectionCard(
                    title: _isHindi ? 'पता' : 'Address',
                    icon: Icons.location_on_rounded,
                    children: [
                      if (_dairyAddress.isNotEmpty)
                        _buildInfoTile(Icons.home_rounded, _isHindi ? 'पता' : 'Address', _dairyAddress),
                      if (_dairyVillage.isNotEmpty)
                        _buildInfoTile(Icons.location_city_rounded, _isHindi ? 'गाँव' : 'Village', _dairyVillage),
                      if (_dairyCity.isNotEmpty)
                        _buildInfoTile(Icons.apartment_rounded, _isHindi ? 'शहर' : 'City', _dairyCity),
                      if (_dairyState.isNotEmpty)
                        _buildInfoTile(Icons.map_rounded, _isHindi ? 'राज्य' : 'State', _dairyState),
                      if (_dairyPincode.isNotEmpty)
                        _buildInfoTile(Icons.pin_drop_rounded, _isHindi ? 'पिनकोड' : 'Pincode', _dairyPincode),
                      if (_dairyAddress.isEmpty && _dairyVillage.isEmpty && _dairyCity.isEmpty)
                        _buildInfoTile(Icons.location_off_rounded, _isHindi ? 'पता' : 'Address', _isHindi ? 'सेट नहीं' : 'Not set'),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Edit Profile Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => _openEditProfile(),
                      icon: const Icon(Icons.edit_rounded, size: 20),
                      label: Text(
                        _isHindi ? 'प्रोफाइल एडिट करें' : 'Edit Profile',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primaryGreen, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    final displayValue = value.isNotEmpty ? value : (_isHindi ? 'सेट नहीं' : 'Not set');
    final isEmpty = value.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, color: isEmpty ? Colors.grey.shade400 : primaryGreen, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isEmpty ? Colors.grey.shade400 : textDark,
                    fontStyle: isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
    );
    _loadProfile(); // Refresh after editing
  }
}

// ==================== EDIT PROFILE SCREEN ====================

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';
  bool _isSaving = false;

  final _dairyNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _managerMobileController = TextEditingController();
  final _taglineController = TextEditingController();
  final _signatureLabelController = TextEditingController();
  final _addressController = TextEditingController();
  final _villageController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF1A1A1A);
  static const Color textLight = Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _dairyNameController.dispose();
    _ownerNameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _managerMobileController.dispose();
    _taglineController.dispose();
    _signatureLabelController.dispose();
    _addressController.dispose();
    _villageController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }


  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'hi';
      _ownerNameController.text = prefs.getString('userName') ?? '';
      _dairyNameController.text = prefs.getString('dairyName') ?? prefs.getString('dairy_name') ?? '';
      _contactController.text = prefs.getString('userMobile') ?? '';
      _emailController.text = prefs.getString('userEmail') ?? firebaseUser?.email ?? '';
      _managerMobileController.text = prefs.getString('managerMobile') ?? '';
      _taglineController.text = prefs.getString('tagline') ?? '';
      _signatureLabelController.text = prefs.getString('signatureLabel') ?? '';
      _addressController.text = prefs.getString('dairy_address') ?? '';
      _villageController.text = prefs.getString('dairy_village') ?? '';
      _cityController.text = prefs.getString('dairy_city') ?? '';
      _stateController.text = prefs.getString('dairy_state') ?? '';
      _pincodeController.text = prefs.getString('dairy_pincode') ?? '';
    });

    // Load fresh data from Firestore server
    try {
      final syncService = FirestoreSyncService.instance;
      if (syncService.isAuthenticated && firebaseUser != null) {
        final doc = await syncService.getUserProfileFromServer();
        if (doc != null && mounted) {
          setState(() {
            _ownerNameController.text = doc['name'] as String? ?? _ownerNameController.text;
            _dairyNameController.text = doc['dairyName'] as String? ?? _dairyNameController.text;
            _contactController.text = doc['mobile'] as String? ?? _contactController.text;
            _emailController.text = doc['email'] as String? ?? firebaseUser.email ?? _emailController.text;
            _managerMobileController.text = doc['managerMobile'] as String? ?? _managerMobileController.text;
            _taglineController.text = doc['tagline'] as String? ?? _taglineController.text;
            _signatureLabelController.text = doc['signatureLabel'] as String? ?? _signatureLabelController.text;
            _addressController.text = doc['address'] as String? ?? _addressController.text;
            _villageController.text = doc['village'] as String? ?? _villageController.text;
            _cityController.text = doc['city'] as String? ?? _cityController.text;
            _stateController.text = doc['state'] as String? ?? _stateController.text;
            _pincodeController.text = doc['pincode'] as String? ?? _pincodeController.text;
          });
        }
      }
    } catch (e) {
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _ownerNameController.text);
      await prefs.setString('dairyName', _dairyNameController.text);
      await prefs.setString('dairy_name', _dairyNameController.text);
      await prefs.setString('dairy_contact', _contactController.text);
      await prefs.setString('userEmail', _emailController.text);
      await prefs.setString('managerMobile', _managerMobileController.text);
      await prefs.setString('tagline', _taglineController.text);
      await prefs.setString('signatureLabel', _signatureLabelController.text);
      await prefs.setString('dairy_address', _addressController.text);
      await prefs.setString('dairy_village', _villageController.text);
      await prefs.setString('dairy_city', _cityController.text);
      await prefs.setString('dairy_state', _stateController.text);
      await prefs.setString('dairy_pincode', _pincodeController.text);

      // Update Firebase
      final syncService = FirestoreSyncService.instance;
      if (syncService.isAuthenticated) {
        await syncService.updateUserProfile(
          dairyName: _dairyNameController.text,
          ownerName: _ownerNameController.text,
          address: _addressController.text,
          village: _villageController.text,
          city: _cityController.text,
          state: _stateController.text,
          pincode: _pincodeController.text,
          mobile: _contactController.text,
          email: _emailController.text,
          managerMobile: _managerMobileController.text,
          tagline: _taglineController.text,
          signatureLabel: _signatureLabelController.text,
        );
      }

      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text(_isHindi ? 'प्रोफाइल अपडेट हो गई' : 'Profile updated successfully'),
              ],
            ),
            backgroundColor: primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          _isHindi ? 'प्रोफाइल एडिट करें' : 'Edit Profile',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Personal Details
          _buildSection(
            _isHindi ? 'व्यक्तिगत जानकारी' : 'Personal Details',
            [
              _buildField(_ownerNameController, _isHindi ? 'मालिक का नाम' : 'Owner Name', Icons.person_rounded),
              _buildField(_contactController, _isHindi ? 'मोबाइल नंबर' : 'Mobile Number', Icons.phone_rounded, keyboard: TextInputType.phone, locked: true),
              _buildField(_emailController, _isHindi ? 'ईमेल' : 'Email', Icons.email_rounded, keyboard: TextInputType.emailAddress, locked: true),
            ],
          ),
          const SizedBox(height: 16),

          // Dairy Details
          _buildSection(
            _isHindi ? 'डेयरी जानकारी' : 'Dairy Details',
            [
              _buildField(_dairyNameController, _isHindi ? 'डेयरी का नाम' : 'Dairy Name', Icons.store_rounded),
              _buildField(_managerMobileController, _isHindi ? 'मैनेजर मोबाइल' : 'Manager Mobile', Icons.phone_android_rounded, keyboard: TextInputType.phone),
              _buildField(_taglineController, _isHindi ? 'टैगलाइन' : 'Tagline', Icons.format_quote_rounded),
              _buildField(_signatureLabelController, _isHindi ? 'हस्ताक्षर लेबल' : 'Signature Label', Icons.draw_rounded),
            ],
          ),
          const SizedBox(height: 16),

          // Address
          _buildSection(
            _isHindi ? 'पता' : 'Address',
            [
              _buildField(_addressController, _isHindi ? 'पता' : 'Address Line', Icons.home_rounded),
              _buildField(_villageController, _isHindi ? 'गाँव' : 'Village', Icons.location_city_rounded),
              _buildField(_cityController, _isHindi ? 'शहर' : 'City', Icons.apartment_rounded),
              _buildField(_stateController, _isHindi ? 'राज्य' : 'State', Icons.map_rounded),
              _buildField(_pincodeController, _isHindi ? 'पिनकोड' : 'Pincode', Icons.pin_drop_rounded, keyboard: TextInputType.number),
            ],
          ),
          const SizedBox(height: 24),

          // Save Button
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_rounded, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _isHindi ? 'सेव करें' : 'Save Profile',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> fields) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textDark,
            ),
          ),
          const SizedBox(height: 16),
          ...fields,
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    bool locked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        readOnly: locked,
        enabled: !locked,
        style: TextStyle(fontSize: 15, color: locked ? Colors.grey.shade600 : textDark),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: locked ? Colors.grey.shade400 : primaryGreen, size: 20),
          suffixIcon: locked ? Icon(Icons.lock_rounded, color: Colors.grey.shade400, size: 18) : null,
          filled: true,
          fillColor: locked ? Colors.grey.shade100 : bgColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryGreen, width: 1.5),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          labelStyle: const TextStyle(fontSize: 14, color: textLight),
        ),
      ),
    );
  }
}
