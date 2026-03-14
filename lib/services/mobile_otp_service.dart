import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service for Mobile OTP verification using Firebase Phone Authentication
/// This automatically sends SMS OTP to the user's phone number
class MobileOtpService {
  static final MobileOtpService _instance = MobileOtpService._internal();
  static MobileOtpService get instance => _instance;
  MobileOtpService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Store verification ID for OTP verification
  String? _verificationId;
  int? _resendToken;
  DateTime? _verificationIssuedAt;
  
  // Lock to prevent multiple simultaneous sendOtp() calls
  bool _isOtpRequestInProgress = false;
  
  // Callback functions
  Function(String verificationId, int? resendToken)? onCodeSent;
  Function(String error)? onError;
  Function(PhoneAuthCredential credential)? onAutoVerified;

  /// Format phone number to include country code
  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (!cleaned.startsWith('91') && cleaned.length == 10) {
      cleaned = '91$cleaned';
    }
    return '+$cleaned';
  }

  /// Send OTP to mobile number
  /// Uses Completer to wait for the actual Firebase callback before returning result
  Future<Map<String, dynamic>> sendOtp({
    required String phoneNumber,
    required String purpose,
  }) async {
    try {
      // FIX #1: Prevent multiple simultaneous requests
      if (_isOtpRequestInProgress) {
        print('[OTP] ⚠️ OTP request already in progress! Ignoring duplicate');
        return {'success': false, 'error': 'OTP request already in progress.'};
      }
      _isOtpRequestInProgress = true;
      
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      // FIX #5: Always clear old verificationId on new request.
      // When user clicks "Send OTP" or "Resend", we NEED a fresh session.
      // The old verificationId is tied to the old OTP code - can't reuse.
      _verificationId = null;
      _verificationIssuedAt = null;
      
      // Use a Completer so we return result only AFTER Firebase callback fires
      final completer = Completer<Map<String, dynamic>>();
      bool completed = false;
      
      print('[OTP] 📤 Requesting OTP for: $formattedPhone');
      
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        // FIX #2 (part 1): Firebase timeout = 120 seconds (2 minutes)
        timeout: const Duration(seconds: 120),
        forceResendingToken: _resendToken,
        
        // FIX #1 (THE BIGGEST FIX): DO NOT IGNORE AUTO-VERIFICATION!
        // When Android auto-reads SMS, Firebase marks session USED server-side.
        // We MUST accept it, otherwise manual verify will fail with "session-expired".
        verificationCompleted: (PhoneAuthCredential credential) {
          print('[OTP] ✅ AUTO-VERIFICATION: Firebase auto-verified the phone!');
          print('[OTP]    Accepting auto-verification and signing in immediately.');
          // Let the screen handle the auto-verified credential
          onAutoVerified?.call(credential);
        },
        
        // Called when verification fails
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = _getErrorMessage(e.code);
          print('[OTP] ❌ Verification failed: ${e.code} - ${e.message}');
          onError?.call(errorMessage);
          if (!completed) {
            completed = true;
            completer.complete({'success': false, 'error': errorMessage});
          }
        },
        
        // Called when code is sent successfully - THIS SETS VERIFICATION ID
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _verificationIssuedAt = DateTime.now();
          print('[OTP] ✅ codeSent: verificationId stored (len=${verificationId.length})');
          onCodeSent?.call(verificationId, resendToken);
          if (!completed) {
            completed = true;
            completer.complete({
              'success': true,
              'message': 'OTP भेजा गया / OTP sent successfully',
            });
          }
        },
        
        // Auto-retrieval timeout - just log, don't touch state
        codeAutoRetrievalTimeout: (String verificationId) {
          print('[OTP] ⏱️ Auto-retrieval timeout fired (harmless, ignoring)');
        },
      );
      
      // FIX #2 (part 2): Completer timeout MUST match Firebase timeout!
      // Was 30s, now 120s. If codeSent takes 35s on slow network, we won't timeout prematurely.
      final result = await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => {
          'success': false,
          'error': 'OTP भेजने में समय लगा। कृपया फिर से कोशिश करें।',
        },
      );
      
      print('[OTP] 📊 State after sendOtp: verificationId=${_verificationId != null ? "SET ✓" : "NULL ✗"}');
      return result;
      
    } catch (e) {
      print('[OTP] 🔴 Exception in sendOtp: $e');
      return {'success': false, 'error': e.toString()};
    } finally {
      _isOtpRequestInProgress = false;
    }
  }

  /// Verify the OTP entered by user.
  /// 
  /// [forRegistration] — When true (signup flow), the temporary phone user
  /// created during validation is immediately deleted and signed out so the
  /// phone number is freed for linking to the real account later.
  /// When false (login flow), the phone user stays signed in.
  Future<Map<String, dynamic>> verifyOtp({
    required String otp,
    String? verificationId,
    bool forRegistration = false,
  }) async {
    try {
      final verId = verificationId ?? _verificationId;
      
      print('[OTP] 🔍 VERIFY OTP ATTEMPT:');
      print('[OTP]    verificationId: ${verId != null ? "SET ✓ (len=${verId.length})" : "NULL ✗"}');
      print('[OTP]    Time since issued: ${_verificationIssuedAt != null ? "${DateTime.now().difference(_verificationIssuedAt!).inSeconds}s" : "N/A"}');
      
      if (verId == null) {
        print('[OTP] ❌ verificationId is NULL!');
        print('[OTP]    Possible: auto-verification already consumed the session');
        print('[OTP]    Possible: codeSent callback never fired');
        return {
          'success': false,
          'error': 'OTP session not found. Please request OTP again.',
        };
      }

      if (otp.isEmpty || otp.length != 6) {
        return {
          'success': false,
          'error': 'कृपया 6 अंकों का OTP डालें।',
        };
      }
      
      // Create credential with verification ID and OTP
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verId,
        smsCode: otp,
      );
      
      print('[OTP] 🔐 Credential created, calling signInWithCredential...');
      
      // Sign in with Firebase to VALIDATE the OTP
      final userCredential = await _auth.signInWithCredential(credential);
      print('[OTP] ✅ Firebase sign-in successful, uid=${userCredential.user?.uid}');
      
      if (userCredential.user == null) {
        return {'success': false, 'error': 'OTP verification failed.'};
      }

      if (forRegistration) {
        // ── REGISTRATION FLOW ──
        final tempUser = userCredential.user!;
        final hasExistingProvider = tempUser.providerData.any(
          (info) => info.providerId == 'google.com' || info.providerId == 'password',
        );

        if (hasExistingProvider) {
          final existingEmail = tempUser.email;
          try { await _auth.signOut(); } catch (_) {}
          return {
            'success': true,
            'credential': credential,
            'existingAccount': true,
            'existingEmail': existingEmail,
          };
        } else {
          try { await tempUser.delete(); } catch (_) {}
          try { await _auth.signOut(); } catch (_) {}
          return {
            'success': true,
            'credential': credential,
            'existingAccount': false,
          };
        }
      }

      // ── LOGIN FLOW (default) ──
      return {
        'success': true,
        'message': 'OTP verified successfully! ✅',
        'credential': credential,
        'user': userCredential.user,
      };
    } catch (e) {
      String errorMessage = 'Invalid OTP';
      
      if (e is FirebaseAuthException) {
        errorMessage = _getErrorMessage(e.code);
        print('[OTP] 🔴 Firebase error: ${e.code} - ${e.message}');
        
        if (e.code == 'session-expired') {
          print('[OTP] ❌ SESSION-EXPIRED: Auto-retrieval likely consumed the session');
          print('[OTP]    The phone auto-read the SMS and Firebase used it already');
          print('[OTP]    Solution: Auto-verification should handle login directly');
          errorMessage = 'OTP session expired. The code was auto-verified. Please try again.';
        }
      } else {
        print('[OTP] 🔴 Exception: $e');
      }
      
      return {'success': false, 'error': errorMessage};
    }
  }

  /// Create a PhoneAuthCredential from OTP without signing in.
  PhoneAuthCredential? createCredential(String otp) {
    if (_verificationId == null) return null;
    return PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );
  }

  /// Sign in with phone credential
  Future<Map<String, dynamic>> signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await _auth.signInWithCredential(credential);
      return {'success': true, 'user': userCredential.user};
    } catch (e) {
      String errorMessage = 'Verification failed';
      if (e is FirebaseAuthException) errorMessage = _getErrorMessage(e.code);
      return {'success': false, 'error': errorMessage};
    }
  }

  /// Link phone credential to existing user
  Future<Map<String, dynamic>> linkPhoneToUser(PhoneAuthCredential credential) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return {'success': false, 'error': 'No user logged in'};
      await user.linkWithCredential(credential);
      return {'success': true, 'message': 'Phone linked successfully'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Clear stored verification data
  void clearVerification() {
    _verificationId = null;
    _resendToken = null;
  }

  /// Get user-friendly error messages (bilingual)
  String _getErrorMessage(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'गलत मोबाइल नंबर। / Invalid phone number.';
      case 'too-many-requests':
        return 'बहुत ज्यादा requests। कुछ देर बाद कोशिश करें। / Too many requests.';
      case 'invalid-verification-code':
        return 'गलत OTP। कृपया सही OTP डालें। / Invalid OTP.';
      case 'session-expired':
        return 'OTP expire हो गया। नया OTP मांगें। / OTP expired. Request new.';
      case 'quota-exceeded':
        return 'SMS limit पूरी। कुछ देर बाद कोशिश करें। / SMS quota exceeded.';
      case 'operation-not-allowed':
        return 'Phone auth enabled नहीं है। / Phone auth not enabled.';
      case 'invalid-credential':
        return 'गलत OTP। कृपया सही OTP डालें। / Invalid OTP code.';
      default:
        return 'कुछ गलत हो गया। फिर से कोशिश करें। / Something went wrong.';
    }
  }

  /// Get current verification ID
  String? get verificationId => _verificationId;
}
