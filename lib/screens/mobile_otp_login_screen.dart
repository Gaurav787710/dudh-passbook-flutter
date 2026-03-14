import 'dart:async';
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

/// Full-page Mobile OTP Login Screen
/// Professional UI with complete OTP flow and Firebase Auth integration
class MobileOtpLoginScreen extends StatefulWidget {
  const MobileOtpLoginScreen({super.key});

  @override
  State<MobileOtpLoginScreen> createState() => _MobileOtpLoginScreenState();
}

class _MobileOtpLoginScreenState extends State<MobileOtpLoginScreen>
    with SingleTickerProviderStateMixin {
  final _mobileController = TextEditingController();
  final _otpController = TextEditingController();
  final _mobileFocusNode = FocusNode();
  final _otpFocusNode = FocusNode();

  int _step = 1; // 1 = Enter Mobile, 2 = Enter OTP, 3 = Processing
  bool _isLoading = false;
  String? _errorMessage;
  int _resendCountdown = 0;
  Timer? _resendTimerObj;

  final MobileOtpService _otpService = MobileOtpService.instance;

  // Language
  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Theme colors
  bool get _isDark => mounted && context.mounted
      ? Theme.of(context).brightness == Brightness.dark
      : false;
  Color get primaryGreen =>
      _isDark ? const Color(0xFF5C6BC0) : const Color(0xFF2E7D32);
  Color get primaryDark =>
      _isDark ? const Color(0xFF1A237E) : const Color(0xFF1B5E20);
  Color get bgColor =>
      _isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
  Color get cardColor =>
      _isDark ? const Color(0xFF1E1E2E) : Colors.white;
  Color get textDark =>
      _isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get textLight =>
      _isDark ? Colors.white70 : const Color(0xFF666666);

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _languageCode = prefs.getString('language_code') ?? 'hi';
      });
    }
  }

  @override
  void dispose() {
    _resendTimerObj?.cancel();
    _mobileController.dispose();
    _otpController.dispose();
    _mobileFocusNode.dispose();
    _otpFocusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimerObj?.cancel();
    _resendCountdown = 60;
    _resendTimerObj = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendCountdown <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _resendCountdown--);
    });
  }

  // ========== SEND OTP ==========
  Future<void> _sendOtp() async {
    final mobile = _mobileController.text.trim();
    if (mobile.length != 10) {
      setState(() => _errorMessage = _isHindi
          ? '10 अंकों का मोबाइल नंबर डालें'
          : 'Enter 10 digit mobile number');
      return;
    }

    // IMPORTANT: Clear old OTP from input when resending
    // If user taps resend, old OTP code is now invalid
    _otpController.clear();
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    print('[OTPLogin] 📱 Sending OTP to: $mobile (cleared old OTP from input)');

    _otpService.onCodeSent = (verificationId, resendToken) {
      if (mounted) {
        // RACE GUARD: Don't revert to step 2 if auto-verification already moved us to step 3
        if (_step < 3) {
          setState(() {
            _step = 2;
            _isLoading = false;
          });
          _startResendTimer();
          _otpFocusNode.requestFocus();
        }
        print('[OTPLogin] ✅ OTP sent (step=$_step)');
      }
    };

    _otpService.onError = (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
        print('[OTPLogin] ❌ OTP send error: $error');
      }
    };

    _otpService.onAutoVerified = (credential) async {
      if (mounted && _step < 3) {
        print('[OTPLogin] ✅ AUTO-VERIFIED! Firebase already signed in.');
        setState(() {
          _step = 3;
          _isLoading = true;
        });
        // Auto-verification already signed us in, just fetch user data
        await _fetchUserDataAndNavigate();
      }
    };

    await _otpService.sendOtp(
      phoneNumber: mobile,
      purpose: 'login',
    );
  }

  // ========== VERIFY OTP ==========
  Future<void> _verifyOtp() async {
    // RACE GUARD: If auto-verification already moved us to step 3, skip manual verify
    if (_step >= 3) {
      print('[OTPLogin] ⚡ Auto-verification already in progress, skipping manual verify');
      return;
    }
    
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = _isHindi
          ? '6 अंकों का OTP डालें'
          : 'Enter 6 digit OTP');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    print('[OTPLogin] 🔍 Verifying OTP: ${otp.substring(0, 2)}****');
    
    // Check if verification ID exists (prevent session-expired error)
    if (_otpService.verificationId == null) {
      print('[OTPLogin] ❌ No verification session! Verification ID is null.');
      if (mounted) {
        setState(() {
          _errorMessage = _isHindi
              ? 'OTP सत्र समाप्त हो गया। OTP दोबारा मांगें। (सत्र गायब)'
              : 'OTP session expired. Request new OTP. (Session missing)';
          _isLoading = false;
        });
      }
      return;
    }
    
    final result = await _otpService.verifyOtp(otp: otp);
    print('[OTPLogin] OTP verification result: success=${result['success']}');
    
    if (result['success'] == true) {
      setState(() => _step = 3);
      // verifyOtp already signed us in, just fetch user data
      await _fetchUserDataAndNavigate();
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = result['error'] ?? 'OTP verification failed';
          _isLoading = false;
        });
      }
    }
  }

  // ========== FETCH USER DATA & NAVIGATE ==========
  Future<void> _fetchUserDataAndNavigate() async {
    try {
      print('[Login] 🔍 Fetching user data...');
      
      // User is already signed in by verifyOtp() or auto-verification
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        print('[Login] ❌ No user signed in!');
        if (mounted) {
          setState(() {
            _errorMessage = 'Authentication failed. Please try again.';
            _isLoading = false;
            _step = 2;
          });
        }
        return;
      }

      print('[Login] ✅ User already authenticated. UID: ${user.uid}');
      print('[Login] Provider data: ${user.providerData.map((p) => p.providerId).join(', ')}');
      
      final mobile = _mobileController.text.trim();
      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic>? userData;
      String? dairyId;

      // ── METHOD 1: Direct doc read with signed-in user's UID ──
      // Works when phone was linked to original account during signup
      print('[Login] 🔍 METHOD 1: Trying direct users doc with UID ${user.uid}...');
      try {
        final userDoc = await firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          userData = {...userDoc.data()!, 'id': userDoc.id};
          dairyId = (userData['dairyId'] as String?) ?? userDoc.id;
          print('[Login] ✅ METHOD 1 SUCCESS: Found user data');
        } else {
          print('[Login] ⚠️ METHOD 1: No users doc found for UID');
        }
      } catch (e) {
        print('[Login] ⚠️ METHOD 1 Error: $e');
      }

      // ── METHOD 2: Check dairies with same UID ──
      if (userData == null) {
        print('[Login] 🔍 METHOD 2: Trying dairies doc with UID ${user.uid}...');
        try {
          final dairyDoc = await firestore.collection('dairies').doc(user.uid).get();
          if (dairyDoc.exists && dairyDoc.data() != null) {
            final dd = dairyDoc.data()!;
            dairyId = user.uid;
            userData = {
              ...dd,
              'id': user.uid,
              'role': 'admin',
              'name': dd['ownerName'] ?? dd['name'] ?? 'User',
              'email': dd['email'],
              'dairyName': dd['name'],
            };
            print('[Login] ✅ METHOD 2 SUCCESS: Found dairy data');
          } else {
            print('[Login] ⚠️ METHOD 2: No dairies doc found');
          }
        } catch (e) {
          print('[Login] ⚠️ METHOD 2 Error: $e');
        }
      }

      // ── METHOD 3: public_lookups → userId → direct doc read ──
      if (userData == null) {
        print('[Login] 🔍 METHOD 3: Trying public_lookups for mobile $mobile...');
        try {
          final publicDoc = await firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .get();
          if (publicDoc.exists && publicDoc.data() != null) {
            final origUserId = publicDoc.data()!['userId'] as String?;
            print('[Login] Found public_lookups entry with userId: $origUserId');
            if (origUserId != null && origUserId.isNotEmpty) {
              final userDoc = await firestore.collection('users').doc(origUserId).get();
              if (userDoc.exists && userDoc.data() != null) {
                userData = {...userDoc.data()!, 'id': origUserId};
                dairyId = (userData['dairyId'] as String?) ?? origUserId;
                print('[Login] ✅ METHOD 3 SUCCESS: Found user from public_lookups');
              } else {
                // Try dairy doc instead
                print('[Login] No users doc, trying dairies for $origUserId...');
                final dairyDoc = await firestore.collection('dairies').doc(origUserId).get();
                if (dairyDoc.exists && dairyDoc.data() != null) {
                  final dd = dairyDoc.data()!;
                  dairyId = origUserId;
                  userData = {
                    ...dd,
                    'id': origUserId,
                    'role': 'admin',
                    'name': dd['ownerName'] ?? dd['name'] ?? 'User',
                    'email': dd['email'],
                    'dairyName': dd['name'],
                  };
                  print('[Login] ✅ METHOD 3 SUCCESS: Found dairy from public_lookups');
                }
              }
            }
          } else {
            print('[Login] ⚠️ METHOD 3: No public_lookups doc found');
          }
        } catch (e) {
          print('[Login] ⚠️ METHOD 3 Error: $e');
        }
      }

      // ── METHOD 4: Query dairies by mobile field ──
      if (userData == null) {
        print('[Login] 🔍 METHOD 4: Querying dairies by mobile...');
        try {
          final dairiesQuery = await firestore
              .collection('dairies')
              .where('mobile', isEqualTo: mobile)
              .limit(1)
              .get();
          if (dairiesQuery.docs.isNotEmpty) {
            final dDoc = dairiesQuery.docs.first;
            final dd = dDoc.data();
            dairyId = dDoc.id;
            print('[Login] Found dairy by mobile: $dairyId');
            // Try users/{dairyId} for full data
            try {
              final userDoc = await firestore.collection('users').doc(dairyId).get();
              if (userDoc.exists && userDoc.data() != null) {
                userData = {...userDoc.data()!, 'id': dairyId};
                print('[Login] ✅ METHOD 4 SUCCESS: Found users data for dairy');
              }
            } catch (_) {}
            userData ??= {
              ...dd,
              'id': dairyId,
              'role': 'admin',
              'name': dd['ownerName'] ?? dd['name'] ?? 'User',
              'email': dd['email'],
              'dairyName': dd['name'],
            };
            print('[Login] ✅ METHOD 4 SUCCESS: Using dairy data');
          } else {
            print('[Login] ⚠️ METHOD 4: No dairies found with mobile $mobile');
          }
        } catch (e) {
          print('[Login] ⚠️ METHOD 4 Error: $e');
        }
      }

      // ── METHOD 5: Query users by mobile field ──
      if (userData == null) {
        print('[Login] 🔍 METHOD 5: Querying users by mobile...');
        try {
          final usersQuery = await firestore
              .collection('users')
              .where('mobile', isEqualTo: mobile)
              .limit(1)
              .get();
          if (usersQuery.docs.isNotEmpty) {
            final doc = usersQuery.docs.first;
            userData = {...doc.data(), 'id': doc.id};
            dairyId = (userData['dairyId'] as String?) ?? doc.id;
            print('[Login] ✅ METHOD 5 SUCCESS: Found users by mobile');
          } else {
            print('[Login] ⚠️ METHOD 5: No users found with mobile $mobile');
          }
        } catch (e) {
          print('[Login] ⚠️ METHOD 5 Error: $e');
        }
      }

      // ── METHOD 6: Try +91 prefix ──
      if (userData == null) {
        print('[Login] 🔍 METHOD 6: Querying users with +91 prefix...');
        try {
          final usersQuery = await firestore
              .collection('users')
              .where('mobile', isEqualTo: '+91$mobile')
              .limit(1)
              .get();
          if (usersQuery.docs.isNotEmpty) {
            final doc = usersQuery.docs.first;
            userData = {...doc.data(), 'id': doc.id};
            dairyId = (userData['dairyId'] as String?) ?? doc.id;
            print('[Login] ✅ METHOD 6 SUCCESS: Found users with +91 prefix');
          } else {
            print('[Login] ⚠️ METHOD 6: No users found');
          }
        } catch (e) {
          print('[Login] ⚠️ METHOD 6 Error: $e');
        }
      }

      if (userData != null && dairyId != null) {
        print('[Login] ✅✅✅ ALL METHODS: User data found! Proceeding to login...');
        await _completeLogin(userData, dairyId, mobile);
      } else {
        // User not found
        print('[Login] ❌ ERROR: No user data found after all lookup methods!');
        print('[Login] userId found: $userData');
        if (mounted) {
          _showSnackBar(
            _isHindi
                ? 'यह नंबर रजिस्टर्ड नहीं है। नया अकाउंट बनाएं।'
                : 'This number is not registered. Please create a new account.',
            isError: true,
          );
          await Future.delayed(const Duration(milliseconds: 800));
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SignupScreen()),
            );
          }
        }
      }
    } catch (e) {
      print('[Login] ❌ EXCEPTION in _signInAndProcess: $e');
      print('[Login] Stack trace: ${StackTrace.current}');
      if (mounted) {
        setState(() {
          _errorMessage = _isHindi
              ? 'OTP सत्यापन विफल। पुनः प्रयास करें। (Error: ${e.toString().split('\n').first})'
              : 'OTP verification failed. Please try again. (Error: ${e.toString().split('\n').first})';
          _isLoading = false;
          _step = 2;
        });
      }
    }
  }

  // ========== COMPLETE LOGIN WITH FOUND USER DATA ==========
  Future<void> _completeLogin(Map<String, dynamic> userData, String dairyId, String mobile) async {
    try {
      final syncService = FirestoreSyncService.instance;
      final db = DatabaseHelper.instance;
      final prefs = await SharedPreferences.getInstance();

      // Data isolation check
      final previousFirebaseDairyId = prefs.getString('firebaseDairyId');
      final previousUserRole = prefs.getString('userRole');
      bool isFirstLoginOrDifferentUser = false;
      final currentRole = userData['role'] as String? ?? 'admin';

      if (previousFirebaseDairyId != null && previousFirebaseDairyId != dairyId) {
        await db.resetDatabase();
        // Remove only auth/dairy keys, preserve UI settings (language, theme)
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
        await db.resetDatabase();
        isFirstLoginOrDifferentUser = true;
      } else if (previousUserRole != null && previousUserRole != currentRole) {
        // Same dairy but DIFFERENT role (admin ↔ staff switch) — reset to avoid stale data
        await db.resetDatabase();
        isFirstLoginOrDifferentUser = true;
      }

      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userRole', userData['role'] as String? ?? 'admin');
      await prefs.setString('userName', userData['name'] as String? ?? 'User');
      await prefs.setString('userMobile', userData['mobile'] as String? ?? mobile);
      await prefs.setString('firebaseDairyId', dairyId);

      final localDairyId = dairyId.hashCode.abs();
      await prefs.setInt('dairyId', localDairyId);
      await prefs.setInt('userId', 0);

      if (userData['dairyName'] != null) {
        await prefs.setString('dairyName', userData['dairyName'] as String);
      }
      if (userData['email'] != null) {
        await prefs.setString('userEmail', userData['email'] as String);
      }
      if (userData['address'] != null) {
        await prefs.setString('dairy_address', userData['address'] as String);
      }
      if (userData['village'] != null) {
        await prefs.setString('dairy_village', userData['village'] as String);
      }
      if (userData['city'] != null) {
        await prefs.setString('dairy_city', userData['city'] as String);
      }
      if (userData['state'] != null) {
        await prefs.setString('dairy_state', userData['state'] as String);
      }
      if (userData['pincode'] != null) {
        await prefs.setString('dairy_pincode', userData['pincode'] as String);
      }
      if (userData['mobile'] != null) {
        await prefs.setString('dairy_contact', userData['mobile'] as String);
      }
      if (userData['managerMobile'] != null) {
        await prefs.setString('managerMobile', userData['managerMobile'] as String);
      }
      if (userData['tagline'] != null) {
        await prefs.setString('tagline', userData['tagline'] as String);
      }
      if (userData['signatureLabel'] != null) {
        await prefs.setString('signatureLabel', userData['signatureLabel'] as String);
      }
      await prefs.setString('authProvider', 'phone');

      // Ensure public_lookups for future logins (NO EMAIL stored)
      try {
        await FirebaseFirestore.instance
            .collection('public_lookups')
            .doc('mobile_$mobile')
            .set({
              'userId': dairyId,
              'name': userData['name'] ?? 'User',
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      } catch (_) {}

      syncService.setDairyId(dairyId);

      if (mounted) {
        _showSnackBar(
          'Welcome, ${userData['name'] ?? 'User'}! 🎉',
          isError: false,
        );
        await Future.delayed(const Duration(milliseconds: 500));

        _showSnackBar('Syncing data from cloud...', isError: false);
        await syncService.fullSync(
          localDairyId: localDairyId,
          isNewUser: isFirstLoginOrDifferentUser,
        );

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: $e';
          _isLoading = false;
          _step = 1;
        });
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
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ========== BUILD UI ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                children: [
                  // Top Bar
                  _buildTopBar(),

                  const SizedBox(height: 20),

                  // Illustration / Icon
                  _buildIllustration(),

                  const SizedBox(height: 32),

                  // Content Card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _step == 3
                        ? _buildProcessingView()
                        : _step == 2
                            ? _buildOtpStep()
                            : _buildMobileStep(),
                  ),

                  // Error Message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(),
                  ],

                  const SizedBox(height: 24),

                  // Footer info
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _isLoading && _step == 3
                ? null
                : () {
                    if (_step == 2) {
                      setState(() {
                        _step = 1;
                        _errorMessage = null;
                        _otpController.clear();
                      });
                    } else {
                      _otpService.clearVerification();
                      Navigator.pop(context);
                    }
                  },
            icon: Icon(
              _step == 2
                  ? Icons.arrow_back_rounded
                  : Icons.close_rounded,
              color: textDark,
            ),
            style: IconButton.styleFrom(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _step == 1
                      ? (_isHindi ? 'मोबाइल से लॉगिन' : 'Login with Mobile')
                      : _step == 2
                          ? (_isHindi ? 'OTP वेरिफाई करें' : 'Verify OTP')
                          : (_isHindi ? 'लॉगिन हो रहा है...' : 'Logging in...'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _step == 1
                      ? (_isHindi
                          ? 'अपना रजिस्टर्ड मोबाइल नंबर डालें'
                          : 'Enter your registered mobile number')
                      : _step == 2
                          ? (_isHindi
                              ? '+91 ${_mobileController.text} पर भेजा गया OTP डालें'
                              : 'Enter OTP sent to +91 ${_mobileController.text}')
                          : (_isHindi
                              ? 'कृपया प्रतीक्षा करें...'
                              : 'Please wait...'),
                  style: TextStyle(
                    fontSize: 13,
                    color: textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustration() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryGreen.withOpacity(0.15),
            primaryGreen.withOpacity(0.05),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          _step == 1
              ? Icons.phone_android_rounded
              : _step == 2
                  ? Icons.sms_rounded
                  : Icons.verified_rounded,
          size: 48,
          color: primaryGreen,
        ),
      ),
    );
  }

  Widget _buildMobileStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Mobile Number Input
          Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _mobileFocusNode.hasFocus
                    ? primaryGreen
                    : Colors.grey.shade200,
                width: _mobileFocusNode.hasFocus ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.08),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(13),
                      bottomLeft: Radius.circular(13),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '🇮🇳',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+91',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey.shade300,
                ),
                Expanded(
                  child: TextField(
                    controller: _mobileController,
                    focusNode: _mobileFocusNode,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: textDark,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      hintText: _isHindi
                          ? 'मोबाइल नंबर'
                          : 'Mobile Number',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        letterSpacing: 0,
                        fontWeight: FontWeight.normal,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() => _errorMessage = null);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Send OTP Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _isHindi ? 'OTP भेजें' : 'Send OTP',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // Info text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withOpacity(_isDark ? 0.1 : 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Colors.blue.shade600,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isHindi
                        ? 'आपके रजिस्टर्ड मोबाइल नंबर पर SMS OTP भेजा जाएगा'
                        : 'An SMS OTP will be sent to your registered mobile number',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Phone number badge
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phone_rounded, size: 16, color: primaryGreen),
                const SizedBox(width: 6),
                Text(
                  '+91 ${_mobileController.text}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primaryGreen,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _step = 1;
                      _errorMessage = null;
                      _otpController.clear();
                    });
                  },
                  child: Icon(
                    Icons.edit_rounded,
                    size: 14,
                    color: primaryGreen,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // OTP Input
          TextField(
            controller: _otpController,
            focusNode: _otpFocusNode,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 12,
              color: textDark,
            ),
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              hintText: '• • • • • •',
              hintStyle: TextStyle(
                color: Colors.grey.shade300,
                letterSpacing: 12,
                fontSize: 28,
              ),
              counterText: '',
              filled: true,
              fillColor: bgColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryGreen, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 18,
              ),
            ),
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
          ),

          const SizedBox(height: 12),

          // Resend timer
          if (_resendCountdown > 0)
            Text(
              _isHindi
                  ? '${_resendCountdown}s में पुनः भेजें'
                  : 'Resend in ${_resendCountdown}s',
              style: TextStyle(fontSize: 13, color: textLight),
            )
          else
            TextButton.icon(
              onPressed: _isLoading ? null : _sendOtp,
              icon: Icon(Icons.refresh_rounded, size: 16,
                  color: primaryGreen),
              label: Text(
                _isHindi ? 'OTP दोबारा भेजें' : 'Resend OTP',
                style: TextStyle(color: primaryGreen),
              ),
            ),

          const SizedBox(height: 20),

          // Verify Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyOtp,
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          _isHindi
                              ? 'वेरिफाई करें और लॉगिन'
                              : 'Verify & Login',
                          style: const TextStyle(
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
    );
  }

  Widget _buildProcessingView() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: primaryGreen,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isHindi ? 'लॉगिन हो रहा है...' : 'Logging in...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isHindi
                ? 'कृपया प्रतीक्षा करें, आपका डेटा सिंक हो रहा है'
                : 'Please wait, syncing your data',
            style: TextStyle(fontSize: 13, color: textLight),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red.shade600, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 13,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _errorMessage = null),
              child: Icon(Icons.close_rounded,
                  color: Colors.red.shade400, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_rounded, size: 14, color: textLight),
              const SizedBox(width: 6),
              Text(
                _isHindi
                    ? 'Firebase द्वारा सुरक्षित OTP'
                    : 'Secured OTP by Firebase',
                style: TextStyle(fontSize: 11, color: textLight),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _isHindi
                ? 'Dudh Passbook © 2024'
                : 'Dudh Passbook © 2024',
            style: TextStyle(fontSize: 11, color: textLight),
          ),
        ],
      ),
    );
  }
}
