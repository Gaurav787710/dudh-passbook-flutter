import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_sync_service.dart';
import '../services/mobile_otp_service.dart';

class SignupScreen extends StatefulWidget {
  final String? prefillEmail;
  final String? prefillName;
  final bool isGoogleUser;
  
  const SignupScreen({
    super.key,
    this.prefillEmail,
    this.prefillName,
    this.isGoogleUser = false,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _dairyNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _managerMobileController = TextEditingController();
  final _taglineController = TextEditingController();
  final _signatureLabelController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _termsAccepted = false;
  
  // Registration step: 1=mobile, 2=otp, 3=details, 4=success
  int _currentStep = 1;
  
  // OTP related
  int _resendCountdown = 0;
  String? _verifiedMobile;
  PhoneAuthCredential? _verifiedPhoneCredential; // Store for phone linking after registration
  
  final MobileOtpService _mobileOtpService = MobileOtpService.instance;

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';
  
  // Animation
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  
  // Resend countdown timer (cancellable)
  Timer? _resendTimer;

  // Gesture recognizers (must be disposed)
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  // Professional Colors
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color bgColor = Color(0xFFF8FAFC);
  static const Color textDark = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _animController.forward();

    _termsRecognizer = TapGestureRecognizer()..onTap = () => _showTermsDialog();
    _privacyRecognizer = TapGestureRecognizer()..onTap = () => _showPrivacyDialog();
    
    // Pre-fill from Google Sign-In if available
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
    if (widget.prefillName != null) {
      _nameController.text = widget.prefillName!;
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _animController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _dairyNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _pincodeController.dispose();
    _managerMobileController.dispose();
    _taglineController.dispose();
    _signatureLabelController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _languageCode = prefs.getString('language_code') ?? 'hi';
    });
  }

  void _animateToStep(int newStep) {
    _animController.reset();
    setState(() => _currentStep = newStep);
    _animController.forward();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Start resend countdown timer
  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendCountdown = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendCountdown <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _resendCountdown--);
    });
  }

  // Send OTP to mobile number
  Future<void> _sendOtp() async {
    final mobile = _mobileController.text.trim();
    if (mobile.isEmpty || mobile.length != 10) {
      _showSnackBar(_isHindi ? 'कृपया सही 10 अंक का मोबाइल नंबर डालें' : 'Please enter a valid 10-digit mobile number', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();
    
    // NOTE: Don't check 'already exists' here — wait until OTP is verified (step 2)
    // User should enter OTP first, THEN we check if account exists
    
    _mobileOtpService.onCodeSent = (verId, token) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _verifiedMobile = mobile;
      });
      _animateToStep(2);
      _startResendCountdown();
      _showSnackBar(_isHindi ? '✅ OTP भेजा गया +91 $mobile पर!' : '✅ OTP sent to +91 $mobile!', isError: false);
    };
    
    _mobileOtpService.onError = (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar(error, isError: true);
    };
    
    _mobileOtpService.onAutoVerified = (credential) async {
      _verifiedPhoneCredential = credential; // Store for phone linking during registration
      
      if (widget.isGoogleUser) {
        // Link phone directly to the already-signed-in Google account
        try {
          await _mobileOtpService.linkPhoneToUser(credential);
        } catch (e) {
          // Non-critical — will retry in registerAdminWithGoogle()
        }
      }
      
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _verifiedMobile = mobile;
      });
      _animateToStep(3);
      _showSnackBar('✅ Mobile auto-verified!', isError: false);
    };
    
    await _mobileOtpService.sendOtp(phoneNumber: mobile, purpose: 'registration');
  }

  // Verify OTP
  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty || otp.length != 6) {
      _showSnackBar(_isHindi ? 'कृपया 6-अंक का OTP डालें' : 'Please enter 6-digit OTP', isError: true);
      return;
    }
    
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();
    
    final mobile = _verifiedMobile ?? _mobileController.text.trim();

    // ══════ GOOGLE SIGNUP PATH ══════
    // For Google users, link phone directly to the already-signed-in Google account.
    // user.linkWithCredential() validates the OTP AND links the phone in one step.
    // This avoids creating a temporary phone-only user that breaks the flow.
    if (widget.isGoogleUser) {
      final credential = _mobileOtpService.createCredential(otp);
      if (credential == null) {
        setState(() => _isLoading = false);
        _showSnackBar(_isHindi ? 'OTP सत्र समाप्त हो गया। नया OTP मांगें।' : 'OTP session expired. Request a new OTP.', isError: true);
        return;
      }
      _verifiedPhoneCredential = credential;

      // Try linking phone to the Google account directly
      final user = FirebaseAuth.instance.currentUser;
      bool phoneLinkSuccess = false;
      
      if (user != null) {
        try {
          await user.linkWithCredential(credential);
          // Verify linking succeeded by checking provider data
          await user.reload();
          final updatedUser = FirebaseAuth.instance.currentUser;
          final hasPhone = updatedUser?.providerData.any((p) => p.providerId == 'phone') ?? false;
          
          if (hasPhone) {
            print('[Signup] ✅ Phone successfully linked to Google account (UID: ${user.uid})');
            phoneLinkSuccess = true;
          } else {
            print('[Signup] ⚠️ linkWithCredential completed but phone not in providerData');
          }
          // Success: phone linked to Google account + OTP validated (or already was)
        } on FirebaseAuthException catch (e) {
          if (e.code == 'invalid-verification-code' || e.code == 'invalid-credential') {
            setState(() => _isLoading = false);
            _showSnackBar(_isHindi ? 'गलत OTP! फिर से कोशिश करें' : 'Wrong OTP! Please try again', isError: true);
            return;
          } else if (e.code == 'credential-already-in-use') {
            // Phone number is already linked to a different Firebase account
            setState(() => _isLoading = false);
            _showAccountExistsDialog(mobile, null);
            return;
          } else if (e.code == 'provider-already-linked') {
            // Phone already linked to this account - that's fine!
            print('[Signup] ℹ️ Phone already linked to this account');
            phoneLinkSuccess = true;
          } else {
            print('[Signup] ⚠️ Linking error ${e.code}: ${e.message}');
          }
          // Other errors - proceed anyway as phone may be linked
        } catch (e) {
          print('[Signup] ⚠️ Non-Firebase error during linking: $e');
        }
      }

      // Also check Firestore if this mobile is registered to a DIFFERENT user
      final syncService = FirestoreSyncService.instance;
      final existingCheck = await syncService.findAccountByMobile(mobile);
      if (existingCheck['success'] == true) {
        final existingUserId = existingCheck['userId'] as String?;
        final currentUid = user?.uid;
        if (existingUserId != null && existingUserId != currentUid) {
          final existingEmail = existingCheck['email'] as String?;
          if (mounted) {
            setState(() => _isLoading = false);
            _showAccountExistsDialog(mobile, existingEmail);
          }
          return;
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        _animateToStep(3);
        _showSnackBar('✅ Mobile verified!' + (phoneLinkSuccess ? ' Phone linked.' : ''), isError: false);
      }
      return;
    }

    // ══════ NON-GOOGLE SIGNUP PATH ══════
    // verifyOtp(forRegistration: true) validates OTP, then deletes the temporary
    // phone user and signs out, freeing the phone number for linking later.
    final result = await _mobileOtpService.verifyOtp(otp: otp, forRegistration: true);
    
    if (result['success'] != true) {
      setState(() => _isLoading = false);
      _showSnackBar(result['error'] ?? (_isHindi ? 'गलत OTP! फिर से कोशिश करें' : 'Wrong OTP! Please try again'), isError: true);
      return;
    }

    final credential = result['credential'] as PhoneAuthCredential?;
    _verifiedPhoneCredential = credential;

    // Check if phone is already linked to an existing Google/Password account
    final existingAccount = result['existingAccount'] as bool? ?? false;
    if (existingAccount) {
      final existingEmail = result['existingEmail'] as String?;
      if (mounted) {
        setState(() => _isLoading = false);
        _showAccountExistsDialog(mobile, existingEmail);
      }
      return;
    }

    // Phone verified + temp user cleaned up → proceed to details step
    if (mounted) {
      setState(() => _isLoading = false);
      _animateToStep(3);
      _showSnackBar('✅ Mobile verified!', isError: false);
    }
  }

  void _showAccountExistsDialog(String mobile, String? email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
            const SizedBox(height: 24),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_search_rounded, size: 40, color: Colors.orange.shade600),
            ),
            const SizedBox(height: 20),
            const Text(
              'Account Already Exists',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textDark),
            ),
            const SizedBox(height: 8),
            Text(
              _isHindi ? 'इस मोबाइल नंबर से पहले से अकाउंट है' : 'An account already exists with this mobile number',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone_android_rounded, color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 12),
                      Text('+91 $mobile', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                    ],
                  ),
                  if (email != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.email_rounded, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(email, style: TextStyle(color: Colors.blue.shade700))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded),
                    SizedBox(width: 8),
                    Text('Go to Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Resend OTP
  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;
    
    setState(() => _isLoading = true);
    
    _mobileOtpService.onCodeSent = (verId, token) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _startResendCountdown();
      _showSnackBar('✅ OTP फिर से भेजा गया!', isError: false);
    };
    
    _mobileOtpService.onError = (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar(error, isError: true);
    };
    
    if (_verifiedMobile == null) return;
    await _mobileOtpService.sendOtp(phoneNumber: _verifiedMobile!, purpose: 'registration');
  }

  // Create Account
  Future<void> _createAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    
    if (!_termsAccepted) {
      _showSnackBar(_isHindi ? 'कृपया Terms & Conditions स्वीकार करें' : 'Please accept Terms & Conditions', isError: true);
      return;
    }
    
    if (!widget.isGoogleUser) {
      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnackBar('Passwords do not match!', isError: true);
        return;
      }
      if (_passwordController.text.length < 6) {
        _showSnackBar('Password must be at least 6 characters', isError: true);
        return;
      }
    }
    
    setState(() => _isLoading = true);
    HapticFeedback.heavyImpact();
    
    try {
      final syncService = FirestoreSyncService.instance;
      Map<String, dynamic> result;
      
      if (widget.isGoogleUser) {
        result = await syncService.registerAdminWithGoogle(
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
          dairyName: _dairyNameController.text.trim(),
          mobile: _verifiedMobile ?? _mobileController.text.trim(),
          address: _addressController.text.trim(),
          city: _cityController.text.trim(),
          pincode: _pincodeController.text.trim(),
          managerMobile: _managerMobileController.text.trim(),
          tagline: _taglineController.text.trim(),
          signatureLabel: _signatureLabelController.text.trim(),
          phoneCredential: _verifiedPhoneCredential,
        );
      } else {
        result = await syncService.registerAdmin(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          dairyName: _dairyNameController.text.trim(),
          ownerName: _nameController.text.trim(),
          mobile: _verifiedMobile ?? _mobileController.text.trim(),
          address: _addressController.text.trim(),
          city: _cityController.text.trim(),
          pincode: _pincodeController.text.trim(),
          managerMobile: _managerMobileController.text.trim(),
          tagline: _taglineController.text.trim(),
          signatureLabel: _signatureLabelController.text.trim(),
          phoneCredential: _verifiedPhoneCredential,
        );
      }
      
      if (result['success'] == true) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _animateToStep(4);
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
        final error = result['error'] as String? ?? 'Registration failed';
        _showSnackBar('Error: $error', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('Error: $e', isError: true);
    }
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.article_rounded, color: primaryGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Text(_isHindi ? 'नियम व शर्तें' : 'Terms & Conditions', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              _isHindi
                  ? '''Dudh Passbook - नियम व शर्तें

अंतिम अपडेट: जनवरी 2025

1. सेवा का उपयोग
Dudh Passbook एक डेयरी प्रबंधन ऐप है। इस ऐप का उपयोग करके, आप इन नियमों व शर्तों से सहमत होते हैं।

2. खाता पंजीकरण
• आपको सही और पूरी जानकारी देनी होगी।
• अपने खाते की सुरक्षा आपकी जिम्मेदारी है।
• एक मोबाइल नंबर से एक ही खाता बनाया जा सकता है।

3. डेटा और गोपनीयता
• आपका डेटा सुरक्षित रूप से क्लाउड पर संग्रहीत किया जाता है।
• हम आपकी अनुमति के बिना आपका डेटा किसी तीसरे पक्ष को नहीं देंगे।
• आप कभी भी अपना डेटा डाउनलोड या हटा सकते हैं।

4. उपयोग प्रतिबंध
• ऐप का दुरुपयोग न करें।
• अवैध गतिविधियों के लिए उपयोग न करें।
• अन्य उपयोगकर्ताओं के डेटा तक पहुंचने का प्रयास न करें।

5. सेवा की उपलब्धता
• हम सेवा की 24/7 उपलब्धता का प्रयास करते हैं लेकिन गारंटी नहीं दे सकते।
• रखरखाव के लिए सेवा अस्थायी रूप से बंद हो सकती है।

6. खाता समाप्ति
• हम किसी भी समय आपके खाते को समाप्त कर सकते हैं यदि नियमों का उल्लंघन होता है।
• आप कभी भी अपना खाता हटा सकते हैं।

7. दायित्व की सीमा
• ऐप "जैसा है" के आधार पर प्रदान किया जाता है।
• हम डेटा हानि या सेवा में रुकावट के लिए जिम्मेदार नहीं हैं।

8. संपर्क
सहायता के लिए: help@dudhpassbook.com'''
                  : '''Dudh Passbook - Terms & Conditions

Last Updated: January 2025

1. Acceptance of Terms
By using Dudh Passbook, you agree to these Terms & Conditions. If you do not agree, please do not use the app.

2. Account Registration
• You must provide accurate and complete information during registration.
• You are responsible for maintaining the security of your account.
• One account per mobile number is allowed.

3. Data & Privacy
• Your data is securely stored on cloud servers.
• We will not share your data with third parties without your consent.
• You can download or delete your data at any time.

4. Usage Restrictions
• Do not misuse the app or its services.
• Do not use the app for any illegal activities.
• Do not attempt to access other users' data.

5. Service Availability
• We strive for 24/7 availability but cannot guarantee uninterrupted service.
• Service may be temporarily suspended for maintenance.

6. Account Termination
• We reserve the right to terminate accounts that violate these terms.
• You may delete your account at any time.

7. Limitation of Liability
• The app is provided "as is" without warranties.
• We are not liable for any data loss or service interruptions.

8. Contact
For support: help@dudhpassbook.com''',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.6),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_isHindi ? 'समझ गया' : 'Got it'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.privacy_tip_rounded, color: primaryGreen, size: 22),
            ),
            const SizedBox(width: 12),
            Text(_isHindi ? 'गोपनीयता नीति' : 'Privacy Policy', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              _isHindi
                  ? '''Dudh Passbook - गोपनीयता नीति

अंतिम अपडेट: जनवरी 2025

1. जानकारी जो हम एकत्र करते हैं
• व्यक्तिगत जानकारी: नाम, ईमेल, मोबाइल नंबर, पता।
• डेयरी डेटा: किसान विवरण, दूध एंट्री, पेमेंट रिकॉर्ड।
• डिवाइस की जानकारी: डिवाइस आईडी, ऑपरेटिंग सिस्टम।

2. हम जानकारी का उपयोग कैसे करते हैं
• ऐप की सेवाएं प्रदान करने के लिए।
• आपके अनुभव को बेहतर बनाने के लिए।
• क्लाउड बैकअप और डेटा सिंक के लिए।
• ग्राहक सहायता प्रदान करने के लिए।

3. डेटा सुरक्षा
• आपका डेटा Firebase/Google Cloud पर एन्क्रिप्टेड रूप में संग्रहीत होता है।
• हम उद्योग-मानक सुरक्षा उपायों का उपयोग करते हैं।
• केवल प्रमाणित उपयोगकर्ता ही अपने डेटा तक पहुंच सकते हैं।

4. डेटा साझाकरण
• हम आपका निजी डेटा किसी तीसरे पक्ष को नहीं बेचते।
• डेटा केवल आपकी सहमति से या कानूनी आवश्यकता पर साझा किया जा सकता है।

5. आपके अधिकार
• आप अपना डेटा देख, संशोधित या हटा सकते हैं।
• आप अपना खाता कभी भी बंद कर सकते हैं।
• खाता बंद करने पर आपका डेटा 30 दिनों में हटा दिया जाएगा।

6. कुकीज़ और एनालिटिक्स
• हम ऐप के प्रदर्शन को बेहतर बनाने के लिए एनालिटिक्स का उपयोग कर सकते हैं।
• कोई विज्ञापन ट्रैकिंग नहीं की जाती।

7. बच्चों की गोपनीयता
• यह ऐप 13 वर्ष से कम आयु के बच्चों के लिए नहीं है।

8. नीति में परिवर्तन
• हम इस नीति को समय-समय पर अपडेट कर सकते हैं।
• परिवर्तन ऐप में सूचित किए जाएंगे।

9. संपर्क
गोपनीयता संबंधी प्रश्नों के लिए: help@dudhpassbook.com'''
                  : '''Dudh Passbook - Privacy Policy

Last Updated: January 2025

1. Information We Collect
• Personal Information: Name, email, mobile number, address.
• Dairy Data: Farmer details, milk entries, payment records.
• Device Information: Device ID, operating system version.

2. How We Use Information
• To provide and maintain app services.
• To improve your experience.
• For cloud backup and data synchronization.
• To provide customer support.

3. Data Security
• Your data is stored encrypted on Firebase/Google Cloud.
• We use industry-standard security measures.
• Only authenticated users can access their data.

4. Data Sharing
• We do not sell your personal data to third parties.
• Data may only be shared with your consent or as required by law.

5. Your Rights
• You can view, modify, or delete your data at any time.
• You can close your account at any time.
• Upon account deletion, your data will be removed within 30 days.

6. Cookies & Analytics
• We may use analytics to improve app performance.
• No advertising tracking is performed.

7. Children\'s Privacy
• This app is not intended for children under 13 years of age.

8. Changes to Policy
• We may update this policy from time to time.
• Changes will be notified within the app.

9. Contact
For privacy-related questions: help@dudhpassbook.com''',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.6),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_isHindi ? 'समझ गया' : 'Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            if (_currentStep != 4)
              _buildAppBar(),
            
            // Progress Indicator
            if (_currentStep != 4)
              _buildProgressIndicator(),
            
            // Main Content
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: _buildCurrentStep(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _isLoading ? null : () {
              if (_currentStep == 1) {
                Navigator.pop(context);
              } else if (_currentStep == 2) {
                _animateToStep(1);
              } else if (_currentStep == 3) {
                _animateToStep(2);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                _currentStep == 1 ? Icons.close_rounded : Icons.arrow_back_rounded,
                color: textDark,
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
                  _currentStep == 1 ? 'Create Account' :
                  _currentStep == 2 ? 'Verify OTP' : 'Complete Profile',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentStep == 1
                      ? (_isHindi ? 'अकाउंट बनाएं' : 'Create your account')
                      : _currentStep == 2
                          ? (_isHindi ? 'OTP सत्यापित करें' : 'Verify your OTP')
                          : (_isHindi ? 'प्रोफ़ाइल पूरा करें' : 'Complete your profile'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (widget.isGoogleUser)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.network(
                    'https://www.google.com/favicon.ico',
                    width: 14,
                    height: 14,
                    errorBuilder: (_, __, ___) => Icon(Icons.g_mobiledata, size: 14, color: Colors.blue.shade700),
                  ),
                  const SizedBox(width: 4),
                  Text('Google', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          Row(
            children: [
              _buildProgressStep(1, 'Mobile', Icons.phone_android_rounded),
              _buildProgressLine(_currentStep >= 2),
              _buildProgressStep(2, 'OTP', Icons.message_rounded),
              _buildProgressLine(_currentStep >= 3),
              _buildProgressStep(3, 'Details', Icons.person_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStep(int step, String label, IconData icon) {
    final isActive = _currentStep >= step;
    final isCompleted = _currentStep > step;
    
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [primaryGreen, primaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isActive ? null : Colors.grey.shade200,
            shape: BoxShape.circle,
            boxShadow: isActive
                ? [BoxShadow(color: primaryGreen.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
                : Icon(icon, color: isActive ? Colors.white : Colors.grey.shade400, size: 20),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? primaryGreen : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 24, left: 4, right: 4),
        decoration: BoxDecoration(
          color: isActive ? primaryGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 1:
        return _buildMobileStep();
      case 2:
        return _buildOtpStep();
      case 3:
        return _buildDetailsStep();
      case 4:
        return _buildSuccessStep();
      default:
        return _buildMobileStep();
    }
  }

  // ===== STEP 1: Mobile Number Entry =====
  Widget _buildMobileStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        
        // Icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [primaryGreen.withOpacity(0.15), primaryGreen.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.phone_android_rounded, size: 48, color: primaryGreen),
        ),
        const SizedBox(height: 28),
        
        // Google verified badge (if Google user)
        if (widget.isGoogleUser) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_rounded, color: Colors.green.shade600, size: 22),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Verified ✓',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 14),
                    ),
                    Text(
                      widget.prefillEmail ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        
        // Main Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your mobile number',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  _isHindi ? 'OTP भेजकर वेरीफाई करेंगे' : 'We\'ll send a 6-digit OTP to verify',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
                ),
                const SizedBox(height: 24),
                
                // Mobile input with flag
                Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
                              errorBuilder: (_, __, ___) => const Text('🇮🇳', style: TextStyle(fontSize: 16)),
                            ),
                            const SizedBox(width: 8),
                            const Text('+91', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textDark)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _mobileController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 2),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            hintText: '9876543210',
                            hintStyle: TextStyle(color: Colors.grey, letterSpacing: 2),
                            border: InputBorder.none,
                            counterText: '',
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 8),
                Text(
                  '10 digit mobile number',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                
                const SizedBox(height: 24),
                
                // Send OTP Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Send OTP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 22),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Security note
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_rounded, color: Colors.blue.shade600, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isHindi ? 'आपका मोबाइल नंबर सुरक्षित है' : 'Your mobile number is secure and will not be shared',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== STEP 2: OTP Verification =====
  Widget _buildOtpStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        
        // Icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade100, Colors.blue.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.message_rounded, size: 48, color: Colors.blue.shade600),
        ),
        const SizedBox(height: 24),
        
        // OTP sent badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 18),
              const SizedBox(width: 8),
              Text(
                'OTP sent to +91 $_verifiedMobile',
                style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        
        // Main Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  'Enter 6-digit OTP',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  '6 अंकों का OTP दर्ज करें',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                
                // OTP Input
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 20),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '• • • • • •',
                      hintStyle: TextStyle(color: Colors.grey.shade400, letterSpacing: 14, fontSize: 24),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Resend OTP
                _resendCountdown > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Resend OTP in ${_resendCountdown}s',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _isLoading ? null : _resendOtp,
                        icon: Icon(Icons.refresh_rounded, color: primaryGreen, size: 18),
                        label: Text('Resend OTP', style: TextStyle(color: primaryGreen, fontWeight: FontWeight.w600)),
                      ),
                
                const SizedBox(height: 24),
                
                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Verify OTP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              Icon(Icons.verified_rounded, size: 22),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Wrong number?
        TextButton.icon(
          onPressed: _isLoading ? null : () => _animateToStep(1),
          icon: Icon(Icons.edit_rounded, size: 16, color: Colors.grey.shade600),
          label: Text('Wrong number? Edit', style: TextStyle(color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  // ===== STEP 3: Profile Details Form =====
  Widget _buildDetailsStep() {
    return Column(
      children: [
        // Verified badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade50, Colors.blue.shade50],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.verified_rounded, color: Colors.green.shade700, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mobile Verified ✓',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 14),
                    ),
                    Text(
                      '+91 $_verifiedMobile',
                      style: TextStyle(fontSize: 13, color: Colors.green.shade600),
                    ),
                  ],
                ),
              ),
              if (widget.isGoogleUser)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Google', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        
        // Form Card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: Personal Info
                  _buildSectionTitle('Personal Information', Icons.person_rounded),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'Enter your full name',
                    icon: Icons.badge_rounded,
                    enabled: !widget.isGoogleUser,
                    isLocked: widget.isGoogleUser,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'your@email.com',
                    icon: Icons.email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !widget.isGoogleUser,
                    isLocked: widget.isGoogleUser,
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // Section: Dairy Details
                  _buildSectionTitle('Dairy Details', Icons.store_rounded),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _dairyNameController,
                    label: 'Dairy Name',
                    hint: 'e.g., Krishna Dairy',
                    icon: Icons.store_mall_directory_rounded,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _addressController,
                    label: 'Full Address',
                    hint: 'Enter complete address',
                    icon: Icons.location_on_rounded,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildInputField(
                          controller: _cityController,
                          label: 'City',
                          hint: 'City name',
                          icon: Icons.location_city_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInputField(
                          controller: _pincodeController,
                          label: 'Pincode',
                          hint: '6 digits',
                          icon: Icons.pin_drop_rounded,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // Section: Optional
                  _buildSectionTitle('Optional Details', Icons.add_circle_outline_rounded, isOptional: true),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _managerMobileController,
                    label: 'Helpline Number',
                    hint: '10 digit number (optional)',
                    icon: Icons.support_agent_rounded,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    isRequired: false,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildInputField(
                    controller: _taglineController,
                    label: 'Tagline',
                    hint: 'e.g., शुद्धता ही हमारी पहचान',
                    icon: Icons.format_quote_rounded,
                    isRequired: false,
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // Password Section (Only for non-Google users)
                  if (!widget.isGoogleUser) ...[
                    _buildSectionTitle('Create Password', Icons.lock_rounded),
                    const SizedBox(height: 16),
                    
                    _buildInputField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Min 6 characters',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildInputField(
                      controller: _confirmPasswordController,
                      label: 'Confirm Password',
                      hint: 'Re-enter password',
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscureText: _obscureConfirm,
                      onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'No password required!',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You will login with Google',
                                  style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Terms & Conditions
                  GestureDetector(
                    onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _termsAccepted ? primaryGreen.withOpacity(0.05) : bgColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _termsAccepted ? primaryGreen.withOpacity(0.3) : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _termsAccepted ? primaryGreen : Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _termsAccepted ? primaryGreen : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: _termsAccepted
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                                children: [
                                  TextSpan(text: _isHindi ? 'मैं ' : 'I agree to the '),
                                  TextSpan(
                                    text: _isHindi ? 'नियम व शर्तें' : 'Terms & Conditions',
                                    style: TextStyle(color: primaryGreen, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                                    recognizer: _termsRecognizer,
                                  ),
                                  TextSpan(text: _isHindi ? ' और ' : ' and '),
                                  TextSpan(
                                    text: _isHindi ? 'गोपनीयता नीति' : 'Privacy Policy',
                                    style: TextStyle(color: primaryGreen, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                                    recognizer: _privacyRecognizer,
                                  ),
                                  TextSpan(text: _isHindi ? ' स्वीकार करता/करती हूं' : ''),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // Create Account Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _createAccount,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Create Account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 22),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===== STEP 4: Success =====
  Widget _buildSuccessStep() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          
          // Success Animation
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade100, Colors.green.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.shade200,
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: Icon(Icons.check_rounded, size: 80, color: Colors.green.shade600),
          ),
          const SizedBox(height: 40),
          
          const Text(
            'Account Created! 🎉',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textDark),
          ),
          const SizedBox(height: 8),
          Text(
            _isHindi ? 'अकाउंट सफलतापूर्वक बन गया!' : 'Account created successfully!',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          
          // Account Details Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildSuccessRow(Icons.store_rounded, 'Dairy', _dairyNameController.text),
                const Divider(height: 24),
                _buildSuccessRow(Icons.person_rounded, 'Owner', _nameController.text),
                const Divider(height: 24),
                _buildSuccessRow(Icons.phone_android_rounded, 'Mobile', '+91 $_verifiedMobile'),
                const Divider(height: 24),
                _buildSuccessRow(Icons.email_rounded, 'Email', _emailController.text),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Login Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.login_rounded),
                    SizedBox(width: 10),
                    Text('Go to Login', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSuccessRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: primaryGreen, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : '-',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, {bool isOptional = false}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: primaryGreen, size: 18),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark),
        ),
        if (isOptional) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Optional', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ),
        ],
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool obscureText = false,
    bool enabled = true,
    bool isLocked = false,
    bool isRequired = true,
    int maxLines = 1,
    int? maxLength,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
            if (isRequired)
              Text(' *', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold)),
            if (isLocked) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_rounded, size: 14, color: Colors.grey.shade500),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: isPassword && obscureText,
          enabled: enabled,
          maxLines: maxLines,
          maxLength: maxLength,
          style: TextStyle(fontSize: 15, color: enabled ? textDark : Colors.grey.shade600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: enabled ? primaryGreen : Colors.grey.shade400, size: 20),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            filled: true,
            fillColor: enabled ? bgColor : Colors.grey.shade100,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: primaryGreen, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.red.shade400, width: 1),
            ),
          ),
          validator: isRequired
              ? (value) {
                  if (value == null || value.isEmpty) return 'This field is required';
                  return null;
                }
              : null,
        ),
      ],
    );
  }
}
