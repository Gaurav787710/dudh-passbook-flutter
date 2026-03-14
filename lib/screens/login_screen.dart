import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database/database_helper.dart';
import '../services/firestore_sync_service.dart';
import '../services/mobile_otp_service.dart';
import 'home_screen.dart';
import 'signup_screen.dart';
import 'mobile_otp_login_screen.dart';
import '../utils/theme_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _selectedUserType; // null = show selection, 'admin' or 'staff'
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme-aware colors
  bool get _isDark => mounted && context.mounted ? TH.isDark(context) : false;
  Color get primaryGreen => _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark => _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get bgColor => _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor => _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark => _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight => _isDark ? Colors.white70 : const Color(0xFF666666);

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'hi';
    });
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final syncService = FirestoreSyncService.instance;
      final db = DatabaseHelper.instance;
      final input = _mobileController.text.trim();
      final password = _passwordController.text;

      // BUG FIX: Read previous auth state BEFORE calling login methods,
      // because login methods internally call _saveSyncState() which
      // overwrites firebaseDairyId in prefs — breaking the data isolation check.
      final prefsBeforeLogin = await SharedPreferences.getInstance();
      final previousFirebaseDairyId = prefsBeforeLogin.getString('firebaseDairyId');
      final previousUserRole = prefsBeforeLogin.getString('userRole');

      Map<String, dynamic> result;

      if (_selectedUserType == 'staff') {
        // Staff login - use Firestore staff collection (not Firebase Auth)

        result = await syncService.loginStaff(
          mobileOrEmail: input,
          password: password,
        );
      } else {
        // Admin login - use Firebase Authentication
        // Supports email, mobile number, or userId

        result = await syncService.login(
          emailOrMobileOrId: input,
          password: password,
        );
      }

      if (result['success'] == true) {
        final userData = result['userData'] as Map<String, dynamic>?;
        final dairyId = result['dairyId'] as String?;

        // Check if user role matches selected type
        final userRole = userData?['role'] as String? ?? 'admin';
        if (_selectedUserType == 'staff' && userRole != 'staff') {
          if (mounted) {
            _showSnackBar(
              _isHindi
                  ? 'यह Admin अकाउंट है! Staff में login नहीं हो सकता'
                  : 'This is an Admin account! Cannot login as Staff',
              isError: true,
            );
          }
          // BUG FIX: Always logout when role mismatch detected
          await syncService.logout();
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        if (_selectedUserType == 'admin' && userRole == 'staff') {
          if (mounted) {
            _showSnackBar(
              _isHindi
                  ? 'यह Staff अकाउंट है! Admin में login नहीं हो सकता'
                  : 'This is a Staff account! Cannot login as Admin',
              isError: true,
            );
          }
          await syncService.logout();
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        final prefs = await SharedPreferences.getInstance();

        // ===== DATA ISOLATION FIX =====
        // Use previousFirebaseDairyId and previousUserRole captured BEFORE login call
        // (login methods call _saveSyncState which overwrites firebaseDairyId)
        bool isFirstLoginOrDifferentUser = false;
        final currentRole = userData?['role'] as String? ?? _selectedUserType;

        if (previousFirebaseDairyId != null &&
            previousFirebaseDairyId != dairyId) {
          // Different dairy logging in - COMPLETELY RESET DATABASE AND PREFS
          await db.resetDatabase();
          final authKeys = [
            'isLoggedIn', 'userRole', 'userName', 'userMobile', 'userEmail',
            'firebaseDairyId', 'firebaseUserId', 'dairyId', 'userId',
            'dairyName', 'dairy_name', 'dairy_address', 'dairy_village',
            'dairy_city', 'dairy_state', 'dairy_pincode', 'dairy_contact',
            'managerMobile', 'tagline', 'signatureLabel', 'authProvider', 'isDemo',
            'lastDriveBackupDate', 'lastBackupDate', 'lastAutoBackupDate',
            'buffaloPerKgFatRate', 'cowEfuRate', 'cowDefaultSnf',
            'buffaloSnf88to89Deduction', 'buffaloSnf85to87Deduction',
            'buffaloSnf84Penalty', 'buffaloLowQualityPenalty',
            'cowSnf83to84Deduction', 'cowSnf81to82Deduction',
            'cowHighFatDeduction', 'cowSnf80Penalty', 'cowLowFatPenalty',
          ];
          for (final key in authKeys) {
            await prefs.remove(key);
          }
          isFirstLoginOrDifferentUser = true;
        } else if (previousFirebaseDairyId == null) {
          // First time Firebase login - reset database to start fresh
          await db.resetDatabase();
          isFirstLoginOrDifferentUser = true;
        } else if (previousUserRole != null && previousUserRole != currentRole) {
          // Same dairy but DIFFERENT role (admin ↔ staff switch) — reset to avoid stale data
          await db.resetDatabase();
          isFirstLoginOrDifferentUser = true;
        }
        // ===== END DATA ISOLATION FIX =====

        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userRole', userRole);
        await prefs.setString(
          'userName',
          userData?['name'] as String? ?? 'User',
        );
        await prefs.setString(
          'userMobile',
          userData?['mobile'] as String? ?? input,
        );
        await prefs.setString('firebaseDairyId', dairyId ?? '');

        // Generate a unique local dairyId from Firebase UID (hash to int)
        final localDairyId = dairyId?.hashCode.abs() ?? 1;
        await prefs.setInt('dairyId', localDairyId);

        // Save user ID for staff - used to filter entries by who created them
        // For staff: use document ID hash. For admin: use 0 (admin sees all)
        final staffId = userData?['id'] as String?;
        if (userRole == 'staff' && staffId != null) {
          final localUserId = staffId.hashCode.abs();
          await prefs.setInt('userId', localUserId);
          await prefs.setString('firebaseUserId', staffId);
        } else {
          await prefs.setInt('userId', 0); // Admin userId = 0 (sees all)
        }

        if (userData?['dairyName'] != null) {
          await prefs.setString('dairyName', userData!['dairyName'] as String);
        }

        // Save all profile/address fields from Firestore for Account/Profile screen
        if (userData?['email'] != null) {
          await prefs.setString('userEmail', userData!['email'] as String);
        } else {
          // Fallback: get email from Firebase Auth current user
          final currentUser = syncService.currentUser;
          if (currentUser?.email != null) {
            await prefs.setString('userEmail', currentUser!.email!);
          }
        }
        if (userData?['address'] != null) {
          await prefs.setString('dairy_address', userData!['address'] as String);
        }
        if (userData?['village'] != null) {
          await prefs.setString('dairy_village', userData!['village'] as String);
        }
        if (userData?['city'] != null) {
          await prefs.setString('dairy_city', userData!['city'] as String);
        }
        if (userData?['state'] != null) {
          await prefs.setString('dairy_state', userData!['state'] as String);
        }
        if (userData?['pincode'] != null) {
          await prefs.setString('dairy_pincode', userData!['pincode'] as String);
        }
        if (userData?['mobile'] != null) {
          await prefs.setString('dairy_contact', userData!['mobile'] as String);
        }
        if (userData?['managerMobile'] != null) {
          await prefs.setString('managerMobile', userData!['managerMobile'] as String);
        }
        if (userData?['tagline'] != null) {
          await prefs.setString('tagline', userData!['tagline'] as String);
        }
        if (userData?['signatureLabel'] != null) {
          await prefs.setString('signatureLabel', userData!['signatureLabel'] as String);
        }
        if (userData?['authProvider'] != null) {
          await prefs.setString('authProvider', userData!['authProvider'] as String);
        }

        // Load rate settings from Firestore (important for staff to use same rates as admin)
        try {
          final rateSettings = await syncService.loadRateSettings();
          if (rateSettings != null) {
            for (final entry in rateSettings.entries) {
              await prefs.setDouble(entry.key, entry.value);
            }
          } else {
          }
        } catch (e) {
        }

        if (mounted) {
          _showSnackBar(
            'Welcome, ${userData?['name'] ?? 'User'}! 🎉',
            isError: false,
          );
          await Future.delayed(const Duration(milliseconds: 500));

          // Sync data from Firebase to local
          // If first login or different user, only download (don't upload stale local data)
          if (mounted) {
            _showSnackBar('Syncing data from cloud...', isError: false);
          }
          await syncService.fullSync(
            localDairyId: localDairyId,
            isNewUser: isFirstLoginOrDifferentUser,
          );

          // BUG FIX: Check mounted again after async operation to avoid crash
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
            );
          }
        }
      } else {
        // Login failed - show error
        final error = result['error'] as String? ?? 'Login failed';
        if (mounted) {
          if (error.contains('user-not-found') ||
              error.contains('no user record') ||
              error.contains('not found')) {
            _showSnackBar(
              _isHindi ? 'कोई अकाउंट नहीं मिला!' : 'No account found!',
              isError: true,
            );
          } else if (error.contains('wrong-password') ||
              error.contains('invalid-credential') ||
              error.contains('Wrong password')) {
            _showSnackBar(_isHindi ? 'गलत पासवर्ड!' : 'Wrong password!', isError: true);
          } else if (error.contains('invalid-email')) {
            _showSnackBar('Invalid email format', isError: true);
          } else {
            _showSnackBar('Login error: $error', isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Login error: $e', isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loginWithDemo() async {
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final db = DatabaseHelper.instance;
      final farmers = await db.getAllFarmers();

      if (farmers.isEmpty) {
        await db.insertDemoData();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userRole', 'admin');
      await prefs.setString('userName', 'Demo Admin');
      await prefs.setBool('isDemo', true);

      if (mounted) {
        _showSnackBar('Demo mode activated! 🎉', isError: false);
        await Future.delayed(const Duration(milliseconds: 500));

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error loading demo: $e', isError: true);
      }
      if (mounted) setState(() => _isLoading = false);
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _selectedUserType == null
              ? _buildUserTypeSelection()
              : _buildLoginScreen(),
        ),
      ),
    );
  }

  // ===== USER TYPE SELECTION SCREEN =====
  Widget _buildUserTypeSelection() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo — Professional Book Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primaryGreen, primaryDark],
                ),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: primaryGreen.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Dudh Passbook',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: textDark,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isHindi ? 'दूध संग्रह प्रबंधन' : 'Milk Collection Management',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 48),

            // Question
            Text(
              _isHindi ? 'आप कौन हैं?' : 'Who are you?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
            Text(
              'Who are you?',
              style: TextStyle(fontSize: 16, color: textLight),
            ),
            const SizedBox(height: 32),

            // Admin/Owner Option
            _buildUserTypeCard(
              icon: Icons.admin_panel_settings_rounded,
              title: _isHindi ? 'एडमिन / मालिक' : 'Admin / Owner',
              subtitle: _isHindi ? 'डेयरी के मालिक या प्रबंधक' : 'Dairy owner or manager',
              description: 'डेयरी के मालिक या प्रबंधक',
              color: primaryGreen,
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() => _selectedUserType = 'admin');
              },
            ),
            const SizedBox(height: 16),

            // Staff/Employee Option
            _buildUserTypeCard(
              icon: Icons.person_rounded,
              title: _isHindi ? 'स्टाफ / कर्मचारी' : 'Staff / Employee',
              subtitle: _isHindi ? 'डेयरी में काम करने वाले' : 'Dairy worker',
              description: 'डेयरी में काम करने वाले',
              color: Colors.blue.shade600,
              onTap: () {
                HapticFeedback.mediumImpact();
                setState(() => _selectedUserType = 'staff');
              },
            ),
            const SizedBox(height: 32),

            // Demo Button
            TextButton.icon(
              onPressed: _isLoading ? null : _loginWithDemo,
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Try Demo Mode'),
              style: TextButton.styleFrom(foregroundColor: primaryGreen),
            ),
            // Google Sign-In moved to Admin login page only
          ],
        ),
      ),
    );
  }

  Widget _buildUserTypeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 350),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ===== LOGIN SCREEN =====
  Widget _buildLoginScreen() {
    final isAdmin = _selectedUserType == 'admin';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Back Button
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () {
                  setState(() => _selectedUserType = null);
                },
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
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: textDark,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            _buildHeader(isAdmin),
            const SizedBox(height: 32),

            // Login Card
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email/Mobile/UserId
                      _buildTextField(
                        controller: _mobileController,
                        label: 'Email / Mobile / User ID',
                        hint: 'your@email.com or mobile number',
                        icon: Icons.person_rounded,
                        keyboardType:
                            TextInputType.text, // Accept any input type
                        isLoginField:
                            true, // Custom flag for flexible validation
                      ),
                      const SizedBox(height: 16),

                      // Password
                      _buildTextField(
                        controller: _passwordController,
                        label: _isHindi ? 'पासवर्ड' : 'Password',
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                      ),
                      const SizedBox(height: 28),

                      // Login Button
                      _buildLoginButton(isAdmin),

                      // Forgot Password (only for Admin)
                      if (isAdmin) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: Text(
                              _isHindi ? 'पासवर्ड भूल गए?' : 'Forgot Password?',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider with "OR"
                        Row(
                          children: [
                            Expanded(
                              child: Divider(color: Colors.grey.shade300),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ),
                            Expanded(
                              child: Divider(color: Colors.grey.shade300),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Login with Mobile OTP (primary option)
                        _buildMobileOtpLoginButton(),
                        const SizedBox(height: 12),

                        // Google Sign-In for Admin
                        _buildGoogleSignInButton(),
                        const SizedBox(height: 16),

                        // Create Account
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SignupScreen(),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 24,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: primaryGreen.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_add_rounded,
                                    color: primaryGreen,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Create New Admin Account',
                                    style: TextStyle(
                                      color: primaryGreen,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Staff Info
                      if (!isAdmin) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.orange.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _isHindi
                                      ? 'Staff अकाउंट Admin/Owner बनाता है\nAdmin से अपना mobile और password लें'
                                      : 'Staff account is created by Admin/Owner\nGet your mobile and password from Admin',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Demo Button
            TextButton.icon(
              onPressed: _isLoading ? null : _loginWithDemo,
              icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
              label: const Text('Try Demo Mode'),
              style: TextButton.styleFrom(foregroundColor: primaryGreen),
            ),
            // No Google Sign-In for staff - staff accounts are created by admin
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isAdmin) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isAdmin
                  ? [primaryGreen, primaryDark]
                  : [Colors.blue.shade600, Colors.blue.shade800],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (isAdmin ? primaryGreen : Colors.blue).withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            isAdmin ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          isAdmin ? 'Admin Login' : 'Staff Login',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: textDark,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isAdmin
              ? (_isHindi ? 'एडमिन लॉगिन' : 'Admin Login')
              : (_isHindi ? 'स्टाफ लॉगिन' : 'Staff Login'),
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isLoginField = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textLight,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 16, color: textDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            prefixIcon: Icon(icon, color: primaryGreen, size: 22),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: textLight,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  )
                : null,
            filled: true,
            fillColor: bgColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: primaryGreen, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'This field is required';
            }
            // For login field, accept email, mobile (10 digits), or user ID (any text)
            if (isLoginField) {
              // It's valid if it's an email, 10-digit mobile, or any other user ID
              return null; // Accept any non-empty input for login
            }
            if (keyboardType == TextInputType.emailAddress &&
                !value.contains('@')) {
              return 'Enter valid email address';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildLoginButton(bool isAdmin) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: isAdmin ? primaryGreen : Colors.blue.shade600,
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login_rounded, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    isAdmin ? 'Login as Admin' : 'Login as Staff',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Google Sign-In Button Widget
  Widget _buildGoogleSignInButton() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 350),
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google Icon
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
              child: Image.network(
                'https://www.google.com/favicon.ico',
                width: 24,
                height: 24,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.g_mobiledata_rounded,
                  size: 24,
                  color: Colors.red,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile OTP Login Button Widget
  Widget _buildMobileOtpLoginButton() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 350),
      child: OutlinedButton(
        onPressed: _isLoading ? null : _showMobileOtpLoginDialog,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_android_rounded, size: 24, color: primaryGreen),
            const SizedBox(width: 12),
            Text(
              _isHindi ? 'मोबाइल OTP से लॉगिन' : 'Login with Mobile OTP',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== MOBILE OTP LOGIN FLOW ==========
  void _showMobileOtpLoginDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MobileOtpLoginScreen()),
    );
  }

  // Google Sign-In Method
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final syncService = FirestoreSyncService.instance;
      final db = DatabaseHelper.instance;

      // BUG FIX: Read previous auth state BEFORE calling signInWithGoogle,
      // because it internally calls _saveSyncState() which overwrites firebaseDairyId.
      final prefsBeforeLogin = await SharedPreferences.getInstance();
      final previousFirebaseDairyId = prefsBeforeLogin.getString('firebaseDairyId');
      final previousUserRole = prefsBeforeLogin.getString('userRole');

      final result = await syncService.signInWithGoogle();

      if (result['success'] == true) {
        final userData = result['userData'] as Map<String, dynamic>?;
        final dairyId = result['dairyId'] as String?;
        final isNewUser = result['isNewUser'] as bool? ?? false;

        final prefs = await SharedPreferences.getInstance();

        // ===== DATA ISOLATION FIX - GOOGLE SIGN IN =====
        // Use previousFirebaseDairyId captured BEFORE signInWithGoogle call
        final currentRole = userData?['role'] as String? ?? 'admin';
        bool isFirstLoginOrDifferentUser = isNewUser;

        if (previousFirebaseDairyId != null &&
            previousFirebaseDairyId != dairyId) {
          await db.resetDatabase();
          isFirstLoginOrDifferentUser = true;
        } else if (previousFirebaseDairyId == null) {
          await db.resetDatabase();
          isFirstLoginOrDifferentUser = true;
        } else if (previousUserRole != null && previousUserRole != currentRole) {
          // Same dairy but different role (admin ↔ staff) — reset to avoid stale data
          await db.resetDatabase();
          isFirstLoginOrDifferentUser = true;
        }
        // ===== END DATA ISOLATION FIX =====

        await prefs.setBool('isLoggedIn', true);
        await prefs.setString(
          'userRole',
          userData?['role'] as String? ?? 'admin',
        );
        await prefs.setString(
          'userName',
          userData?['name'] as String? ?? 'User',
        );
        await prefs.setString(
          'userMobile',
          userData?['mobile'] as String? ?? '',
        );
        await prefs.setString('firebaseDairyId', dairyId ?? '');

        final localDairyId = dairyId?.hashCode.abs() ?? 1;
        await prefs.setInt('dairyId', localDairyId);

        if (userData?['dairyName'] != null) {
          await prefs.setString('dairyName', userData!['dairyName'] as String);
        }

        // Save all profile/address fields from Firestore (same as normal login)
        if (userData?['email'] != null) {
          await prefs.setString('userEmail', userData!['email'] as String);
        } else {
          final currentUser = syncService.currentUser;
          if (currentUser?.email != null) {
            await prefs.setString('userEmail', currentUser!.email!);
          }
        }
        if (userData?['address'] != null) {
          await prefs.setString('dairy_address', userData!['address'] as String);
        }
        if (userData?['village'] != null) {
          await prefs.setString('dairy_village', userData!['village'] as String);
        }
        if (userData?['city'] != null) {
          await prefs.setString('dairy_city', userData!['city'] as String);
        }
        if (userData?['state'] != null) {
          await prefs.setString('dairy_state', userData!['state'] as String);
        }
        if (userData?['pincode'] != null) {
          await prefs.setString('dairy_pincode', userData!['pincode'] as String);
        }
        if (userData?['mobile'] != null) {
          await prefs.setString('dairy_contact', userData!['mobile'] as String);
        }
        if (userData?['managerMobile'] != null) {
          await prefs.setString('managerMobile', userData!['managerMobile'] as String);
        }
        if (userData?['tagline'] != null) {
          await prefs.setString('tagline', userData!['tagline'] as String);
        }
        if (userData?['signatureLabel'] != null) {
          await prefs.setString('signatureLabel', userData!['signatureLabel'] as String);
        }
        if (userData?['authProvider'] != null) {
          await prefs.setString('authProvider', userData!['authProvider'] as String);
        }

        if (mounted) {
          if (isNewUser) {
            _showSnackBar(
              'Welcome! Account created successfully 🎉',
              isError: false,
            );
          } else {
            _showSnackBar(
              'Welcome back, ${userData?['name'] ?? 'User'}! 🎉',
              isError: false,
            );
          }
          await Future.delayed(const Duration(milliseconds: 500));

          // Sync data from Firebase
          // IMPORTANT: If new/different user, only download data (don't upload local data to avoid data pollution)
          _showSnackBar('Syncing data from cloud...', isError: false);
          await syncService.fullSync(
            localDairyId: localDairyId,
            isNewUser: isFirstLoginOrDifferentUser,
          );

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      } else {
        // Check if needs setup (Google user exists but no Firestore document)
        final needsSetup = result['needsSetup'] as bool? ?? false;
        if (needsSetup && mounted) {
          // New user detected - redirect to registration screen with Google data
          final googleEmail = result['googleEmail'] as String?;
          final googleName = result['googleName'] as String?;

          // BUG FIX: Do NOT logout here! Keep user authenticated for Firestore writes in SignupScreen
          // The SignupScreen needs authenticated user to save data to Firestore
          // final syncService = FirestoreSyncService.instance;
          // await syncService.logout(); // REMOVED - This was causing auth issues

          _showSnackBar(
            _isHindi
                ? '👋 नया यूजर! प्रोफाइल पूरा करें'
                : '👋 New user detected! Please complete your profile.',
            isError: false,
          );
          await Future.delayed(const Duration(milliseconds: 500));

          // Navigate to SignupScreen with Google data pre-filled
          // User is still authenticated with Google credentials
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SignupScreen(
                  prefillEmail: googleEmail,
                  prefillName: googleName,
                  isGoogleUser: true, // New parameter to identify Google users
                ),
              ),
            );
          }
        } else {
          final error = result['error'] as String? ?? 'Google Sign-In failed';
          if (mounted) {
            if (!error.contains('cancelled')) {
              _showSnackBar('Google Sign-In error: $error', isError: true);
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Error: $e', isError: true);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ========== PROFESSIONAL FORGOT PASSWORD DIALOG ==========
  void _showForgotPasswordDialog() {
    final mobileController = TextEditingController();
    final otpController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    int step = 1; // 1 = Mobile, 2 = OTP, 3 = Password, 4 = Success
    bool isLoading = false;
    String? foundMobile;
    String? foundEmail;
    String? foundUserId; // Track the original user's UID for public_lookups
    String? errorMessage;
    int resendCountdown = 0;
    bool obscureNew = true;
    bool obscureConfirm = true;
    PhoneAuthCredential? verifiedPhoneCredential;
    bool resetWasEmailSent = false;
    // ignore: unused_local_variable
    String resetResultMessage = '';

    final mobileOtpService = MobileOtpService.instance;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          void startResendCountdown() {
            resendCountdown = 60;
            Future.doWhile(() async {
              await Future.delayed(const Duration(seconds: 1));
              if (resendCountdown > 0 && dialogContext.mounted) {
                setDialogState(() => resendCountdown--);
                return true;
              }
              return false;
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      if (step != 4)
                        GestureDetector(
                          onTap: isLoading
                              ? null
                              : () {
                                  if (step == 1) {
                                    mobileOtpService.clearVerification();
                                    Navigator.pop(dialogContext);
                                  } else {
                                    setDialogState(() {
                                      step = step - 1;
                                      errorMessage = null;
                                    });
                                  }
                                },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              step == 1
                                  ? Icons.close_rounded
                                  : Icons.arrow_back_rounded,
                              color: Colors.grey.shade700,
                              size: 22,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step == 1
                                  ? 'Forgot Password?'
                                  : step == 2
                                  ? 'Verify OTP'
                                  : step == 3
                                  ? 'Create New Password'
                                  : 'Success!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              step == 1
                                  ? (_isHindi ? 'पासवर्ड भूल गए?' : 'Forgot Password?')
                                  : step == 2
                                  ? (_isHindi ? 'OTP सत्यापित करें' : 'Verify OTP')
                                  : step == 3
                                  ? (_isHindi ? 'नया पासवर्ड बनाएं' : 'Create New Password')
                                  : (_isHindi ? 'सफल!' : 'Success!'),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Progress indicator
                if (step != 4)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Row(
                      children: [
                        _buildProgressDot(1, step),
                        Expanded(child: _buildProgressLine(step >= 2)),
                        _buildProgressDot(2, step),
                        Expanded(child: _buildProgressLine(step >= 3)),
                        _buildProgressDot(3, step),
                      ],
                    ),
                  ),

                // Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Step 1: Mobile Number
                        if (step == 1) ...[
                          // Illustration
                          Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    primaryGreen.withOpacity(0.1),
                                    primaryGreen.withOpacity(0.05),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.phone_android_rounded,
                                size: 56,
                                color: primaryGreen,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          Text(
                            'Enter Mobile Number',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isHindi
                                ? 'आपकी पहचान सत्यापित करने के लिए OTP भेजेंगे।'
                                : 'We\'ll send a 6-digit OTP to verify your identity.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Mobile input with beautiful design
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 18,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      bottomLeft: Radius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Image.network(
                                        'https://flagcdn.com/w40/in.png',
                                        width: 24,
                                        height: 16,
                                        errorBuilder: (_, __, ___) =>
                                            const Text('🇮🇳'),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '+91',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: mobileController,
                                    keyboardType: TextInputType.phone,
                                    maxLength: 10,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 2,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    decoration: const InputDecoration(
                                      hintText: '9876543210',
                                      hintStyle: TextStyle(
                                        color: Colors.grey,
                                        letterSpacing: 2,
                                      ),
                                      border: InputBorder.none,
                                      counterText: '',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                        // Step 2: OTP Verification
                        else if (step == 2) ...[
                          // Illustration
                          Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade100,
                                    Colors.blue.shade50,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.message_rounded,
                                size: 56,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // OTP sent info
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Colors.green.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'OTP sent to +91 $foundMobile',
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          Center(
                            child: Text(
                              'Enter 6-digit OTP',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: textDark,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '6 अंकों का OTP दर्ज करें',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // OTP Input boxes
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: TextField(
                              controller: otpController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 24,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: InputDecoration(
                                hintText: '• • • • • •',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade400,
                                  letterSpacing: 16,
                                  fontSize: 24,
                                ),
                                border: InputBorder.none,
                                counterText: '',
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Resend OTP
                          Center(
                            child: resendCountdown > 0
                                ? Text(
                                    'Resend OTP in ${resendCountdown}s',
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 14,
                                    ),
                                  )
                                : TextButton.icon(
                                    onPressed: isLoading
                                        ? null
                                        : () async {
                                            setDialogState(
                                              () => isLoading = true,
                                            );
                                            mobileOtpService.onCodeSent =
                                                (verId, token) {
                                                  setDialogState(
                                                    () => isLoading = false,
                                                  );
                                                  startResendCountdown();
                                                  _showSnackBar(
                                                    '✅ OTP फिर से भेजा गया!',
                                                    isError: false,
                                                  );
                                                };
                                            mobileOtpService.onError = (error) {
                                              setDialogState(
                                                () => isLoading = false,
                                              );
                                              _showSnackBar(
                                                error,
                                                isError: true,
                                              );
                                            };
                                            await mobileOtpService.sendOtp(
                                              phoneNumber: foundMobile!,
                                              purpose: 'password_reset',
                                            );
                                          },
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      color: primaryGreen,
                                      size: 18,
                                    ),
                                    label: Text(
                                      'Resend OTP',
                                      style: TextStyle(
                                        color: primaryGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                          ),
                        ]
                        // Step 3: New Password
                        else if (step == 3) ...[
                          // Illustration
                          Center(
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.purple.shade100,
                                    Colors.purple.shade50,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.lock_reset_rounded,
                                size: 56,
                                color: Colors.purple.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Verified badge
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.verified_rounded,
                                    color: Colors.blue.shade600,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Mobile Verified ✓',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          Text(
                            'Create New Password',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isHindi
                                ? 'अपने अकाउंट के लिए मजबूत पासवर्ड बनाएं।'
                                : 'Create a strong password for your account.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // New Password
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: TextField(
                              controller: newPasswordController,
                              obscureText: obscureNew,
                              style: const TextStyle(fontSize: 16),
                              decoration: InputDecoration(
                                hintText: _isHindi ? 'नया पासवर्ड' : 'New Password',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_rounded,
                                  color: Colors.grey.shade600,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureNew
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: Colors.grey.shade600,
                                  ),
                                  onPressed: () => setDialogState(
                                    () => obscureNew = !obscureNew,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Confirm Password
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: TextField(
                              controller: confirmPasswordController,
                              obscureText: obscureConfirm,
                              style: const TextStyle(fontSize: 16),
                              decoration: InputDecoration(
                                hintText: _isHindi ? 'पासवर्ड पुष्टि' : 'Confirm Password',
                                hintStyle: TextStyle(
                                  color: Colors.grey.shade500,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline_rounded,
                                  color: Colors.grey.shade600,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    obscureConfirm
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: Colors.grey.shade600,
                                  ),
                                  onPressed: () => setDialogState(
                                    () => obscureConfirm = !obscureConfirm,
                                  ),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 18,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Password requirements
                          Container(
                            padding: const EdgeInsets.all(16),
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
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _isHindi
                                        ? 'पासवर्ड कम से कम 6 अक्षर का होना चाहिए'
                                        : 'Password must be at least 6 characters',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.amber.shade800,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                        // Step 4: Success
                        else if (step == 4) ...[
                          const SizedBox(height: 40),

                          // Success animation
                          Center(
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green.shade100,
                                    Colors.green.shade50,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.shade200,
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 80,
                                color: Colors.green.shade600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),

                          Center(
                            child: Text(
                              resetWasEmailSent
                                  ? (_isHindi ? 'पासवर्ड रिसेट ईमेल भेजा गया!' : 'Password Reset Email Sent!')
                                  : (_isHindi ? 'पासवर्ड सफलतापूर्वक बदल दिया गया!' : 'Password Reset Successful!'),
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              resetWasEmailSent
                                  ? (_isHindi ? 'आपके ईमेल पर पासवर्ड रिसेट लिंक भेजा गया है' : 'A password reset link has been sent to your email')
                                  : (_isHindi ? 'पासवर्ड सफलतापूर्वक बदल दिया गया!' : 'Password changed successfully!'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 24),

                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  resetWasEmailSent ? Icons.email_rounded : Icons.login_rounded,
                                  color: Colors.green.shade600,
                                  size: 32,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  resetWasEmailSent
                                      ? (_isHindi
                                          ? 'ईमेल में लिंक पर क्लिक करके नया पासवर्ड सेट करें'
                                          : 'Check your email and click the link to set your new password')
                                      : 'You can now login with your new password',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (resetWasEmailSent && foundEmail != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    foundEmail!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                if (!resetWasEmailSent) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _isHindi ? 'अब नए पासवर्ड से लॉगिन करें' : 'Please login with your new password',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green.shade600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        // Error message
                        if (errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.red.shade600,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    errorMessage!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Bottom Action Button
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isLoading
                          ? null
                          : () async {
                              if (step == 1) {
                                // Send OTP
                                final mobile = mobileController.text.trim();
                                if (mobile.isEmpty || mobile.length != 10) {
                                  _showSnackBar(
                                    _isHindi ? 'कृपया सही 10 अंक का मोबाइल नंबर डालें' : 'Please enter a valid 10-digit mobile number',
                                    isError: true,
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                // Try to find account (public_lookups - no auth needed)
                                // Don't block if not found - we'll re-check after OTP sign-in
                                final syncService =
                                    FirestoreSyncService.instance;
                                final checkResult = await syncService
                                    .findAccountByMobile(mobile);

                                if (checkResult['success'] == true) {
                                  foundEmail = checkResult['email'] as String?;
                                  foundUserId = checkResult['userId'] as String?;
                                }
                                foundMobile = mobile;

                                mobileOtpService.onCodeSent = (verId, token) {
                                  setDialogState(() {
                                    isLoading = false;
                                    step = 2;
                                  });
                                  startResendCountdown();
                                };
                                mobileOtpService.onError = (error) {
                                  setDialogState(() {
                                    isLoading = false;
                                    errorMessage = error;
                                  });
                                };
                                mobileOtpService.onAutoVerified = (credential) {
                                  setDialogState(() {
                                    isLoading = false;
                                    step = 3;
                                  });
                                };

                                await mobileOtpService.sendOtp(
                                  phoneNumber: mobile,
                                  purpose: 'password_reset',
                                );
                              } else if (step == 2) {
                                // Verify OTP
                                final otp = otpController.text.trim();
                                if (otp.isEmpty || otp.length != 6) {
                                  _showSnackBar(
                                    _isHindi ? 'कृपया 6-अंक का OTP डालें' : 'Please enter a 6-digit OTP',
                                    isError: true,
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                final result = await mobileOtpService.verifyOtp(
                                  otp: otp,
                                );

                                if (result['success'] != true) {
                                  setDialogState(() {
                                    isLoading = false;
                                    errorMessage = result['error'];
                                  });
                                  return;
                                }

                                verifiedPhoneCredential =
                                    result['credential']
                                        as PhoneAuthCredential?;

                                // Sign in with phone credential to get auth for Firestore queries
                                if (verifiedPhoneCredential != null) {
                                  try {
                                    final signInResult = await mobileOtpService
                                        .signInWithCredential(
                                          verifiedPhoneCredential!,
                                        );
                                    
                                    // If account wasn't found in step 1 (public_lookups missing),
                                    // retry now that we're authenticated
                                    if (foundEmail == null || foundEmail!.isEmpty) {
                                      final syncService =
                                          FirestoreSyncService.instance;
                                      final recheckResult = await syncService
                                          .findAccountByMobile(foundMobile!);
                                      if (recheckResult['success'] == true) {
                                        foundEmail = recheckResult['email'] as String?;
                                        foundUserId ??= recheckResult['userId'] as String?;
                                      }
                                    }
                                    
                                    // If still no email, try from signed-in user
                                    if (foundEmail == null || foundEmail!.isEmpty) {
                                      final user = signInResult['user'] as User?;
                                      foundEmail = user?.email;
                                      foundUserId ??= user?.uid;
                                    }
                                  } catch (e) {
                                  }
                                }

                                // If STILL no account found after all checks → error
                                if (foundEmail == null || foundEmail!.isEmpty) {
                                  setDialogState(() {
                                    isLoading = false;
                                    step = 1;
                                    errorMessage =
                                        _isHindi ? 'इस मोबाइल नंबर से कोई अकाउंट नहीं मिला' : 'No account found with this mobile number';
                                  });
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = false;
                                  step = 3;
                                });
                              } else if (step == 3) {
                                // Reset Password
                                final newPass = newPasswordController.text;
                                final confirmPass =
                                    confirmPasswordController.text;

                                if (newPass.isEmpty || newPass.length < 6) {
                                  _showSnackBar(
                                    _isHindi ? 'पासवर्ड कम से कम 6 अक्षर का होना चाहिए' : 'Password must be at least 6 characters',
                                    isError: true,
                                  );
                                  return;
                                }
                                if (newPass != confirmPass) {
                                  _showSnackBar(
                                    _isHindi ? 'पासवर्ड मेल नहीं खाते' : 'Passwords do not match',
                                    isError: true,
                                  );
                                  return;
                                }

                                setDialogState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                if (verifiedPhoneCredential != null) {
                                  try {
                                    await mobileOtpService.signInWithCredential(
                                      verifiedPhoneCredential!,
                                    );
                                  } catch (e) {
                                  }
                                }

                                final syncService =
                                    FirestoreSyncService.instance;

                                // Use email from account lookup, or from
                                // the current signed-in user (phone auth)
                                final emailForReset = foundEmail
                                    ?? FirebaseAuth.instance.currentUser?.email
                                    ?? '';

                                final result = await syncService
                                    .updatePasswordAfterOtpVerification(
                                      email: emailForReset,
                                      newPassword: newPass,
                                      phoneCredential: verifiedPhoneCredential,
                                      mobile: foundMobile,
                                    );

                                mobileOtpService.clearVerification();
                                setDialogState(() => isLoading = false);

                                if (result['success'] == true) {
                                  // Populate public_lookups so future mobile+password logins work
                                  try {
                                    final uid = foundUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
                                    if (foundMobile != null && uid.isNotEmpty) {
                                      await FirebaseFirestore.instance
                                          .collection('public_lookups')
                                          .doc('mobile_$foundMobile')
                                          .set({
                                            'userId': uid,
                                            'name': FirebaseAuth.instance.currentUser?.displayName ?? '',
                                            'createdAt': FieldValue.serverTimestamp(),
                                          }, SetOptions(merge: true));
                                    }
                                  } catch (_) {}

                                  resetWasEmailSent = result['emailSent'] == true;
                                  resetResultMessage = (result['message'] as String?) ?? '';
                                  setDialogState(() => step = 4);
                                } else {
                                  setDialogState(
                                    () => errorMessage = result['error'],
                                  );
                                }
                              } else if (step == 4) {
                                Navigator.pop(dialogContext);
                              }
                            },
                      child: isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  step == 1
                                      ? 'Send OTP'
                                      : step == 2
                                      ? 'Verify OTP'
                                      : step == 3
                                      ? 'Reset Password'
                                      : 'Done',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  step == 4
                                      ? Icons.check_rounded
                                      : Icons.arrow_forward_rounded,
                                  size: 22,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Progress dot for forgot password
  Widget _buildProgressDot(int stepNum, int currentStep) {
    final isCompleted = currentStep > stepNum;
    final isActive = currentStep >= stepNum;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isActive ? primaryGreen : Colors.grey.shade200,
        shape: BoxShape.circle,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: primaryGreen.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: isCompleted
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : Text(
                '$stepNum',
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade500,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  // Progress line for forgot password
  Widget _buildProgressLine(bool isActive) {
    return Container(
      height: 3,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isActive ? primaryGreen : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

}
