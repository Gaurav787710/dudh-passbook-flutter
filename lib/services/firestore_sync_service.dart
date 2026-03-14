import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../database/database_helper.dart';
import '../models/farmer.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';
import '../models/advance.dart';

/// =============================================
/// FIRESTORE SYNC SERVICE
/// Syncs data between local SQLite and Firestore
/// Compatible with Dudh Passbook Website
/// =============================================
class FirestoreSyncService {
  static final FirestoreSyncService instance = FirestoreSyncService._init();
  FirestoreSyncService._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _db = DatabaseHelper.instance;

  String? _dairyId;
  bool _isSyncing = false;
  DateTime? _lastSyncAt;
  
  /// Minimum interval between full syncs (prevents excessive API calls)
  static const _syncCooldown = Duration(seconds: 30);

  // Real-time listeners
  StreamSubscription<QuerySnapshot>? _farmersListener;
  StreamSubscription<QuerySnapshot>? _milkEntriesListener;
  StreamSubscription<QuerySnapshot>? _paymentsListener;
  StreamSubscription<DocumentSnapshot>? _rateSettingsListener;
  bool _isListening = false;

  // Callback for UI updates
  Function()? onDataChanged;

  // =============================================
  // INITIALIZATION & AUTH
  // =============================================

  /// Get current dairy ID (Firebase UID)
  String? get dairyId => _dairyId ?? _auth.currentUser?.uid;

  /// Set dairy ID (for staff users)
  void setDairyId(String id) {
    _dairyId = id;
  }

  /// Check if user is authenticated with Firebase
  bool get isAuthenticated => _auth.currentUser != null;

  /// Get current Firebase user
  User? get currentUser => _auth.currentUser;

  // =============================================
  // GHOST EMAIL HELPERS
  // =============================================
  /// Admin ghost email: {mobile}@dudhpassbook.com
  static String _adminGhostEmail(String mobile) => '$mobile@dudhpassbook.com';

  /// Staff ghost email: staff_{mobile}@dudhpassbook.com
  static String _staffGhostEmail(String mobile) => 'staff_$mobile@dudhpassbook.com';

  /// Ensure _members doc exists for the current admin (creates if missing)
  /// This allows Firestore rules to work for existing accounts
  Future<void> _ensureMembersDoc() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final dId = _dairyId ?? user.uid;
    final isAdmin = user.uid == dId;
    try {
      final doc = await _firestore.collection('_members').doc(dId).get();
      if (!doc.exists && isAdmin) {
        // Only admin can create _members doc (Firestore rule: write if uid == dairyId)
        await _firestore.collection('_members').doc(dId).set({
          'uids': [user.uid],
        });
      } else if (doc.exists && isAdmin) {
        // Ensure admin's own UID is in the list
        final uids = List<String>.from((doc.data()?['uids'] as List?) ?? []);
        if (!uids.contains(user.uid)) {
          await _firestore.collection('_members').doc(dId).update({
            'uids': FieldValue.arrayUnion([user.uid]),
          });
        }
      }
      // Staff: do NOT try to write _members — they lack permission.
      // Their UID is added by admin during registerStaff().
    } catch (_) {
      // Non-critical — rules still allow owner via uid==dairyId fallback
    }
  }

  /// Create a secondary FirebaseAuth instance for staff account management
  /// (avoids signing out the current admin)
  Future<FirebaseAuth> _getSecondaryAuth() async {
    try {
      final app = Firebase.app('staffAuth');
      return FirebaseAuth.instanceFor(app: app);
    } catch (_) {
      final app = await Firebase.initializeApp(
        name: 'staffAuth',
        options: Firebase.app().options,
      );
      return FirebaseAuth.instanceFor(app: app);
    }
  }

  /// Initialize sync service with dairy ID
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _dairyId = prefs.getString('firebaseDairyId') ?? _auth.currentUser?.uid;
    final lastSync = prefs.getInt('lastFirestoreSync');
    if (lastSync != null) {
      _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(lastSync);
    }
  }

  /// Save sync state to preferences
  Future<void> _saveSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    if (_dairyId != null) {
      await prefs.setString('firebaseDairyId', _dairyId!);
    }
    if (_lastSyncAt != null) {
      await prefs.setInt(
        'lastFirestoreSync',
        _lastSyncAt!.millisecondsSinceEpoch,
      );
    }
  }

  // =============================================
  // FIREBASE AUTH METHODS
  // =============================================

  /// Register new admin user with email/password
  Future<Map<String, dynamic>> registerAdmin({
    required String email,
    required String password,
    required String dairyName,
    required String ownerName,
    required String mobile,
    String? address,
    String? city,
    String? pincode,
    String? managerMobile,
    String? tagline,
    String? signatureLabel,
    PhoneAuthCredential? phoneCredential,
  }) async {
    try {
      // Create Firebase Auth user with GHOST EMAIL (mobile@dudhpassbook.com)
      final ghostEmail = _adminGhostEmail(mobile);
      final credential = await _auth.createUserWithEmailAndPassword(
        email: ghostEmail,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return {'success': false, 'error': 'Failed to create user'};
      }

      // Now check if mobile already registered
      // Check ALL sources: public_lookups, dairies, and users
      if (mobile.isNotEmpty) {
        bool mobileExists = false;
        String? existingEmail;

        // Check 1: public_lookups (public read)
        try {
          final publicDoc = await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .get();
          if (publicDoc.exists) {
            final existingUserId = publicDoc.data()?['userId'] as String?;
            if (existingUserId != null && existingUserId != user.uid) {
              mobileExists = true;
              existingEmail = publicDoc.data()?['email'] as String?;
            }
          }
        } catch (e) {
          debugPrint('[FirestoreSyncService] public_lookups check error: $e');
        }

        // Check 2: dairies collection (public read)
        if (!mobileExists) {
          try {
            final dairyCheck = await _firestore
                .collection('dairies')
                .where('mobile', isEqualTo: mobile)
                .limit(1)
                .get();
            if (dairyCheck.docs.isNotEmpty && dairyCheck.docs.first.id != user.uid) {
              mobileExists = true;
              existingEmail = dairyCheck.docs.first.data()['email'] as String?;
            }
          } catch (e) {
            debugPrint('[FirestoreSyncService] dairies check error: $e');
          }
        }

        // Check 3: users collection
        if (!mobileExists) {
          try {
            final mobileCheck = await _firestore
                .collection('users')
                .where('mobile', isEqualTo: mobile)
                .limit(1)
                .get();
            if (mobileCheck.docs.isNotEmpty && mobileCheck.docs.first.id != user.uid) {
              mobileExists = true;
              existingEmail = mobileCheck.docs.first.data()['email'] as String?;
            }
          } catch (e) {
            debugPrint('[FirestoreSyncService] users check error: $e');
          }
        }

        if (mobileExists) {
          // Mobile already exists - delete the auth user and return error
          await user.delete();
          return {
            'success': false,
            'error': 'This mobile number is already registered with ${existingEmail ?? "another account"}. Please login instead.',
          };
        }
      }

      _dairyId = user.uid;

      // Create user document in Firestore with all new fields
      await _firestore.collection('users').doc(user.uid).set({
        'email': email,
        'name': ownerName,
        'dairyName': dairyName,
        'mobile': mobile,
        'address': address ?? '',
        'city': city ?? '',
        'pincode': pincode ?? '',
        'managerMobile': managerMobile ?? '',
        'tagline': tagline ?? '',
        'signatureLabel': signatureLabel ?? '',
        'dairyId': user.uid,
        'role': 'admin',
        'authProvider': 'email',
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      // Create dairy document with all fields
      // BUG FIX: Include email field so Forgot Password and account lookup can find it
      await _firestore.collection('dairies').doc(user.uid).set({
        'email': email,
        'name': dairyName,
        'ownerName': ownerName,
        'ownerId': user.uid,
        'mobile': mobile,
        'address': address ?? '',
        'city': city ?? '',
        'pincode': pincode ?? '',
        'managerMobile': managerMobile ?? '',
        'tagline': tagline ?? '',
        'signatureLabel': signatureLabel ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // BUG FIX: Wrap public_lookups in try-catch to handle permission errors gracefully
      // This prevents registration failure if public_lookups rules are not properly set
      try {
        if (mobile.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .set({'userId': user.uid, 'name': ownerName, 'createdAt': FieldValue.serverTimestamp()});
        }
        await _firestore
            .collection('public_lookups')
            .doc('user_${user.uid}')
            .set({'createdAt': FieldValue.serverTimestamp()});
      } catch (e) {
        // Log but don't fail - public_lookups is optional for basic functionality
      }

      // Create _members doc for Firestore rule access control
      try {
        await _firestore.collection('_members').doc(user.uid).set({
          'uids': [user.uid],
        });
      } catch (e) {
        // Non-critical
      }

      // ── Link phone number to Firebase Auth user ──
      // So that Firebase Auth Identifier shows both email AND phone
      if (phoneCredential != null) {
        try {
          await user.linkWithCredential(phoneCredential);
        } catch (e) {
          // Phone linking is non-critical — account works without it
          // May fail if phone is already linked to another account
        }
      }

      await _saveSyncState();

      return {'success': true, 'user': user, 'dairyId': user.uid};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message ?? 'Registration failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Register new admin user who signed in with Google
  /// This method creates Firestore documents for an already authenticated Google user
  /// BUG FIX: User is already authenticated from login screen, don't sign in again
  Future<Map<String, dynamic>> registerAdminWithGoogle({
    required String email,
    required String name,
    required String dairyName,
    required String mobile,
    String? address,
    String? city,
    String? pincode,
    String? managerMobile,
    String? tagline,
    String? signatureLabel,
    PhoneAuthCredential? phoneCredential,
  }) async {
    try {
      // BUG FIX: User should already be authenticated from Google Sign-In in login screen
      // Don't sign in again - just use current user
      User? user = _auth.currentUser;

      // If not authenticated, try to sign in with Google
      if (user == null) {
        final GoogleSignIn googleSignIn = GoogleSignIn();
        final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          return {'success': false, 'error': 'Google Sign-In cancelled'};
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _auth.signInWithCredential(credential);
        user = userCredential.user;
      }

      if (user == null) {
        return {
          'success': false,
          'error': 'Failed to authenticate with Google',
        };
      }

      // Check if user document already exists in Firestore (prevents duplicate registration)
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        // User already registered - don't create again
        return {
          'success': false,
          'error': 'Account already exists. Please login instead.',
        };
      }

      // Check if mobile already registered with another user
      // Check ALL sources: users, dairies, and public_lookups
      if (mobile.isNotEmpty) {
        bool mobileExists = false;
        String? existingEmail;

        // Check 1: public_lookups (public read, most reliable)
        try {
          final publicDoc = await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .get();
          if (publicDoc.exists) {
            final existingUserId = publicDoc.data()?['userId'] as String?;
            if (existingUserId != null && existingUserId != user.uid) {
              mobileExists = true;
              existingEmail = publicDoc.data()?['email'] as String?;
            }
          }
        } catch (e) {
          debugPrint('[FirestoreSyncService] public_lookups check error: $e');
        }

        // Check 2: dairies collection
        if (!mobileExists) {
          try {
            final dairyCheck = await _firestore
                .collection('dairies')
                .where('mobile', isEqualTo: mobile)
                .limit(1)
                .get();
            if (dairyCheck.docs.isNotEmpty && dairyCheck.docs.first.id != user.uid) {
              mobileExists = true;
              existingEmail = dairyCheck.docs.first.data()['email'] as String?;
            }
          } catch (e) {
            debugPrint('[FirestoreSyncService] dairies check error: $e');
          }
        }

        // Check 3: users collection
        if (!mobileExists) {
          try {
            final mobileCheck = await _firestore
                .collection('users')
                .where('mobile', isEqualTo: mobile)
                .limit(1)
                .get();
            if (mobileCheck.docs.isNotEmpty && mobileCheck.docs.first.id != user.uid) {
              mobileExists = true;
              existingEmail = mobileCheck.docs.first.data()['email'] as String?;
            }
          } catch (e) {
            debugPrint('[FirestoreSyncService] users check error: $e');
          }
        }

        if (mobileExists) {
          return {
            'success': false,
            'error': 'This mobile number is already registered with ${existingEmail ?? "another account"}. Please login instead.',
          };
        }
      }

      _dairyId = user.uid;

      // Link phone credential to Google account if provided
      if (phoneCredential != null) {
        try {
          await user.linkWithCredential(phoneCredential);
        } catch (e) {
          debugPrint('[FirestoreSyncService] Phone linking error (non-fatal): $e');
        }
      }

      // Create user document in Firestore with all fields
      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email ?? email,
        'name': user.displayName ?? name,
        'dairyName': dairyName,
        'mobile': mobile,
        'address': address ?? '',
        'city': city ?? '',
        'pincode': pincode ?? '',
        'managerMobile': managerMobile ?? '',
        'tagline': tagline ?? '',
        'signatureLabel': signatureLabel ?? '',
        'dairyId': user.uid,
        'role': 'admin',
        'authProvider': 'google',
        'googlePhotoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      // Create dairy document with all fields
      // BUG FIX: Include email field so Forgot Password and account lookup can find it
      await _firestore.collection('dairies').doc(user.uid).set({
        'email': user.email ?? email,
        'name': dairyName,
        'ownerName': user.displayName ?? name,
        'ownerId': user.uid,
        'mobile': mobile,
        'address': address ?? '',
        'city': city ?? '',
        'pincode': pincode ?? '',
        'managerMobile': managerMobile ?? '',
        'tagline': tagline ?? '',
        'signatureLabel': signatureLabel ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // BUG FIX: Wrap public_lookups in try-catch to handle permission errors gracefully
      // This prevents registration failure if public_lookups rules are not set
      try {
        if (mobile.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .set({
                'userId': user.uid,
                'name': user.displayName ?? name,
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
        await _firestore
            .collection('public_lookups')
            .doc('user_${user.uid}')
            .set({
              'createdAt': FieldValue.serverTimestamp(),
            });
      } catch (e) {
        // Log but don't fail - public_lookups is optional for basic login
      }

      // Create _members doc for Firestore rule access control
      try {
        await _firestore.collection('_members').doc(user.uid).set({
          'uids': [user.uid],
        });
      } catch (e) {
        // Non-critical
      }

      // Don't sign out - user is now registered and authenticated
      // They can continue using the app
      await _saveSyncState();

      return {
        'success': true,
        'dairyId': user.uid,
        'userData': {
          'name': user.displayName ?? name,
          'email': user.email ?? email,
          'dairyName': dairyName,
          'mobile': mobile,
          'role': 'admin',
        },
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message ?? 'Registration failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Register new staff member (saves to Firestore only, not Firebase Auth)
  /// Staff login will be validated against Firestore staff collection
  /// Also creates public lookup entries for login without authentication
  Future<Map<String, dynamic>> registerStaff({
    required String name,
    required String mobile,
    required String password,
    String? fatherName,
    String? email,
    String? address,
    String? aadhar,
    String? pan,
    String? bankAccount,
    String? ifsc,
  }) async {
    if (dairyId == null) {
      return {'success': false, 'error': 'Not authenticated as admin'};
    }

    try {
      // ── GLOBAL UNIQUE CHECK ──
      // Check if this mobile is already used by ANY dairy (not just this one)
      // Use public_lookups since staff collection queries require member permissions
      
      // 1. Check if mobile is registered as ANY staff member (any dairy)
      final staffLookup = await _firestore
          .collection('public_lookups')
          .doc('staff_mobile_$mobile')
          .get();

      if (staffLookup.exists) {
        final existingDairyId = staffLookup.data()?['dairyId'];
        if (existingDairyId == dairyId) {
          return {'success': false, 'error': 'यह मोबाइल नंबर आपकी डेयरी में पहले से रजिस्टर्ड है। / This mobile is already registered in your dairy.'};
        } else {
          return {'success': false, 'error': 'यह मोबाइल नंबर किसी अन्य डेयरी में रजिस्टर्ड है। कृपया दूसरा नंबर इस्तेमाल करें। / This mobile is registered with another dairy. Use a different number.'};
        }
      }

      // 2. Check public_lookups for mobile (could be an owner)
      final ownerLookup = await _firestore
          .collection('public_lookups')
          .doc('mobile_$mobile')
          .get();

      if (ownerLookup.exists) {
        return {'success': false, 'error': 'यह मोबाइल नंबर एक डेयरी ओनर के रूप में रजिस्टर्ड है। / This mobile is registered as a dairy owner.'};
      }

      // Create Firebase Auth account for staff via secondary app (doesn't sign out admin)
      String? staffAuthUid;
      try {
        final secondaryAuth = await _getSecondaryAuth();
        final ghostEmail = _staffGhostEmail(mobile);
        final staffCred = await secondaryAuth.createUserWithEmailAndPassword(
          email: ghostEmail,
          password: password,
        );
        staffAuthUid = staffCred.user?.uid;
        await secondaryAuth.signOut();
      } catch (e) {
        return {'success': false, 'error': 'Failed to create staff auth account: $e'};
      }

      // Create staff document in Firestore
      final docRef = await _firestore.collection('staff').add({
        'name': name,
        'mobile': mobile,
        'password': password, // Kept in owner-only staff doc for admin management
        'email': email,
        'fatherName': fatherName,
        'address': address,
        'aadhar': aadhar,
        'pan': pan,
        'bankAccount': bankAccount,
        'ifsc': ifsc,
        'role': 'staff',
        'dairyId': dairyId,
        'firebaseAuthUid': staffAuthUid,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });

      // Create public lookup entry for staff (NO PASSWORD — just metadata)
      final staffLookupData = {
        'staffId': docRef.id,
        'dairyId': dairyId,
        'name': name,
        'mobile': mobile,
        'role': 'staff',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Create mobile lookup
      await _firestore
          .collection('public_lookups')
          .doc('staff_mobile_$mobile')
          .set(staffLookupData);

      // Create email lookup if email provided
      if (email != null && email.isNotEmpty) {
        await _firestore
            .collection('public_lookups')
            .doc('staff_email_$email')
            .set({...staffLookupData, 'email': email});
      }

      // Add staff UID to _members for Firestore rule access
      try {
        if (staffAuthUid != null) {
          await _firestore.collection('_members').doc(dairyId).update({
            'uids': FieldValue.arrayUnion([staffAuthUid]),
          });
        }
      } catch (e) {
        // If _members doc doesn't exist yet, create it
        try {
          await _firestore.collection('_members').doc(dairyId).set({
            'uids': [dairyId!, if (staffAuthUid != null) staffAuthUid],
          });
        } catch (e) {
          debugPrint('[FirestoreSyncService] _members doc creation error: $e');
        }
      }

      return {
        'success': true,
        'staffId': docRef.id,
        'message': 'Staff created successfully',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Delete staff member from Firestore
  Future<Map<String, dynamic>> deleteStaff({required String mobile}) async {
    if (dairyId == null) {
      return {'success': false, 'error': 'Not authenticated as admin'};
    }

    try {
      // Find staff by mobile in Firestore
      final staffQuery = await _firestore
          .collection('staff')
          .where('dairyId', isEqualTo: dairyId)
          .where('mobile', isEqualTo: mobile)
          .get();

      if (staffQuery.docs.isEmpty) {
        // Staff not found in Firestore, consider it already deleted
        return {'success': true, 'message': 'Staff deleted (was not in cloud)'};
      }

      // Get staff data before deleting
      final staffData = staffQuery.docs.first.data();
      final staffEmail = staffData['email'] as String?;
      final staffAuthUid = staffData['firebaseAuthUid'] as String?;
      final staffPassword = staffData['password'] as String?;

      // Delete Firebase Auth account for staff via secondary app
      if (staffAuthUid != null && staffPassword != null) {
        try {
          final secondaryAuth = await _getSecondaryAuth();
          final ghostEmail = _staffGhostEmail(mobile);
          await secondaryAuth.signInWithEmailAndPassword(
            email: ghostEmail,
            password: staffPassword,
          );
          await secondaryAuth.currentUser?.delete();
          await secondaryAuth.signOut();
        } catch (e) {
          // Non-critical — staff auth might already be deleted
        }
      }

      // Remove staff UID from _members
      if (staffAuthUid != null) {
        try {
          await _firestore.collection('_members').doc(dairyId).update({
            'uids': FieldValue.arrayRemove([staffAuthUid]),
          });
        } catch (e) {
          debugPrint('[FirestoreSyncService] _members removal error: $e');
        }
      }

      // Delete the staff document
      for (var doc in staffQuery.docs) {
        await doc.reference.delete();
      }

      // Delete public lookup entries
      try {
        await _firestore
            .collection('public_lookups')
            .doc('staff_mobile_$mobile')
            .delete();
        if (staffEmail != null && staffEmail.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('staff_email_$staffEmail')
              .delete();
        }
      } catch (e) {
      }

      return {'success': true, 'message': 'Staff deleted successfully'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Update staff member in Firestore
  /// Also handles Firebase Auth password changes via secondary app
  Future<Map<String, dynamic>> updateStaff({
    required String mobile,
    required String name,
    String? fatherName,
    String? email,
    String? address,
    String? aadhar,
    String? pan,
    String? bankAccount,
    String? ifsc,
    String? newPassword,
  }) async {
    if (dairyId == null) {
      return {'success': false, 'error': 'Not authenticated as admin'};
    }

    try {
      // Find staff by mobile in Firestore
      final staffQuery = await _firestore
          .collection('staff')
          .where('dairyId', isEqualTo: dairyId)
          .where('mobile', isEqualTo: mobile)
          .get();

      if (staffQuery.docs.isEmpty) {
        return {'success': false, 'error': 'Staff not found in cloud'};
      }

      final staffDoc = staffQuery.docs.first;
      final oldStaffData = staffDoc.data();
      final oldEmail = oldStaffData['email'] as String?;

      // Update the staff document
      final updateData = <String, dynamic>{
        'name': name,
        'fatherName': fatherName,
        'email': email,
        'address': address,
        'aadhar': aadhar,
        'pan': pan,
        'bankAccount': bankAccount,
        'ifsc': ifsc,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Handle password change via Firebase Auth (secondary app)
      if (newPassword != null && newPassword.isNotEmpty) {
        updateData['password'] = newPassword;
        final oldPassword = oldStaffData['password'] as String?;
        if (oldPassword != null) {
          try {
            final secondaryAuth = await _getSecondaryAuth();
            final ghostEmail = _staffGhostEmail(mobile);
            // Sign in as staff to update password
            await secondaryAuth.signInWithEmailAndPassword(
              email: ghostEmail,
              password: oldPassword,
            );
            await secondaryAuth.currentUser?.updatePassword(newPassword);
            await secondaryAuth.signOut();
          } catch (e) {
            // If sign-in fails (old password wrong in Auth), delete + recreate
            try {
              final secondaryAuth = await _getSecondaryAuth();
              final ghostEmail = _staffGhostEmail(mobile);
              // Delete old account if possible, create new
              try {
                await secondaryAuth.signInWithEmailAndPassword(
                  email: ghostEmail,
                  password: oldPassword,
                );
                final oldUid = secondaryAuth.currentUser?.uid;
                await secondaryAuth.currentUser?.delete();
                // Remove old UID from _members
                if (oldUid != null) {
                  await _firestore.collection('_members').doc(dairyId).update({
                    'uids': FieldValue.arrayRemove([oldUid]),
                  });
                }
              } catch (e) {
                debugPrint('[FirestoreSyncService] old auth cleanup error: $e');
              }
              // Create fresh account
              final newCred = await secondaryAuth.createUserWithEmailAndPassword(
                email: ghostEmail,
                password: newPassword,
              );
              final newUid = newCred.user?.uid;
              updateData['firebaseAuthUid'] = newUid;
              // Add new UID to _members
              if (newUid != null) {
                await _firestore.collection('_members').doc(dairyId).update({
                  'uids': FieldValue.arrayUnion([newUid]),
                });
              }
              await secondaryAuth.signOut();
            } catch (e) {
              debugPrint('[FirestoreSyncService] staff auth recreate error: $e');
            }
          }
        }
      }

      for (var doc in staffQuery.docs) {
        await doc.reference.update(updateData);
      }

      // Update public lookup entries (NO PASSWORD)
      try {
        final lookupData = {
          'staffId': staffDoc.id,
          'dairyId': dairyId,
          'name': name,
          'mobile': mobile,
          'role': 'staff',
          'isActive': true,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Update mobile lookup
        await _firestore
            .collection('public_lookups')
            .doc('staff_mobile_$mobile')
            .set(lookupData, SetOptions(merge: true));

        // Handle email lookup changes
        if (oldEmail != null && oldEmail != email) {
          await _firestore
              .collection('public_lookups')
              .doc('staff_email_$oldEmail')
              .delete();
        }
        if (email != null && email.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('staff_email_$email')
              .set({...lookupData, 'email': email}, SetOptions(merge: true));
        }

      } catch (e) {
      }

      return {'success': true, 'message': 'Staff updated successfully'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Login for staff using Firebase Auth with ghost email
  Future<Map<String, dynamic>> loginStaff({
    required String mobileOrEmail,
    required String password,
  }) async {
    try {
      // Determine ghost email from mobile input
      final cleanInput = mobileOrEmail.replaceAll(RegExp(r'\D'), '');
      String ghostEmail;
      if (cleanInput.length == 10) {
        ghostEmail = _staffGhostEmail(cleanInput);
      } else {
        // If not a mobile number, try ghost email with the input as-is
        ghostEmail = _staffGhostEmail(mobileOrEmail);
      }

      // STEP 1: Try Firebase Auth sign-in with ghost email
      try {
        final cred = await _auth.signInWithEmailAndPassword(
          email: ghostEmail,
          password: password,
        );
        final user = cred.user;
        if (user != null) {
          // Authenticated! Now find staff data from Firestore
          Map<String, dynamic>? staffData;
          String? staffDocId;

          // Try finding by firebaseAuthUid
          final staffQuery = await _firestore
              .collection('staff')
              .where('firebaseAuthUid', isEqualTo: user.uid)
              .where('isActive', isEqualTo: true)
              .limit(1)
              .get();

          if (staffQuery.docs.isNotEmpty) {
            staffData = staffQuery.docs.first.data();
            staffDocId = staffQuery.docs.first.id;
          } else {
            // Fallback: find by mobile
            final mobileQuery = await _firestore
                .collection('staff')
                .where('mobile', isEqualTo: cleanInput.length == 10 ? cleanInput : mobileOrEmail)
                .where('isActive', isEqualTo: true)
                .limit(1)
                .get();
            if (mobileQuery.docs.isNotEmpty) {
              staffData = mobileQuery.docs.first.data();
              staffDocId = mobileQuery.docs.first.id;
            }
          }

          if (staffData != null) {
            _dairyId = staffData['dairyId'] as String?;
            await _saveSyncState();

            // Ensure staff UID is in _members for Firestore rule access.
            // This self-heals if registerStaff failed to add the UID,
            // or if staff was created before the _members system.
            if (_dairyId != null) {
              try {
                await _firestore.collection('_members').doc(_dairyId).update({
                  'uids': FieldValue.arrayUnion([user.uid]),
                });
              } catch (e) {
                debugPrint('[loginStaff] _members self-add failed: $e');
              }
            }

            return {
              'success': true,
              'dairyId': _dairyId,
              'userData': {...staffData, 'id': staffDocId, 'role': 'staff'},
            };
          } else {
            await _auth.signOut();
            return {
              'success': false,
              'error': 'Staff data not found in Firestore / स्टाफ डेटा नहीं मिला',
            };
          }
        }
      } on FirebaseAuthException catch (e) {
        if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
          return {'success': false, 'error': e.message ?? 'Wrong password / गलत पासवर्ड'};
        }
        // Fall through to legacy lookup
      }

      // STEP 2: Legacy staff without Firebase Auth cannot work.
      // Firestore security rules require request.auth to be set,
      // so credential-only login is not viable.
      // If we reach here, staff account has no Firebase Auth — guide them.
      debugPrint('[FirestoreSyncService] Staff login failed — no Firebase Auth account');

      return {
        'success': false,
        'error': 'Staff account not found or wrong password / स्टाफ अकाउंट नहीं मिला या गलत पासवर्ड\n\nAdmin से अपना अकाउंट दोबारा बनवाएं',
      };
    } catch (e) {
      return {'success': false, 'error': 'Login error: ${e.toString()}'};
    }
  }

  // =============================================
  // RATE SETTINGS SYNC
  // =============================================

  /// Sync rate settings to Firestore (called by admin when saving)
  Future<void> syncRateSettings({
    required double buffaloPerKgFatRate,
    required double cowEfuRate,
    required double cowDefaultSnf,
    // SNF deduction settings (optional, will use defaults if not provided)
    double? buffaloSnf88to89Deduction,
    double? buffaloSnf85to87Deduction,
    double? buffaloSnf84Penalty,
    double? buffaloLowQualityPenalty,
    double? cowSnf83to84Deduction,
    double? cowSnf81to82Deduction,
    double? cowHighFatDeduction,
    double? cowSnf80Penalty,
    double? cowLowFatPenalty,
  }) async {
    if (dairyId == null) {
      return;
    }

    try {
      await _firestore.collection('dairy_settings').doc(dairyId).set({
        'buffaloPerKgFatRate': buffaloPerKgFatRate,
        'cowEfuRate': cowEfuRate,
        'cowDefaultSnf': cowDefaultSnf,
        // SNF settings
        'buffaloSnf88to89Deduction': buffaloSnf88to89Deduction ?? 2.0,
        'buffaloSnf85to87Deduction': buffaloSnf85to87Deduction ?? 4.0,
        'buffaloSnf84Penalty': buffaloSnf84Penalty ?? 75.0,
        'buffaloLowQualityPenalty': buffaloLowQualityPenalty ?? 75.0,
        'cowSnf83to84Deduction': cowSnf83to84Deduction ?? 2.0,
        'cowSnf81to82Deduction': cowSnf81to82Deduction ?? 4.0,
        'cowHighFatDeduction': cowHighFatDeduction ?? 15.0,
        'cowSnf80Penalty': cowSnf80Penalty ?? 75.0,
        'cowLowFatPenalty': cowLowFatPenalty ?? 50.0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      rethrow;
    }
  }

  /// Load rate settings from Firestore (for staff login)
  /// Returns null if not found or error
  Future<Map<String, double>?> loadRateSettings() async {
    if (dairyId == null) {
      return null;
    }

    try {
      final doc = await _firestore
          .collection('dairy_settings')
          .doc(dairyId)
          .get();

      if (!doc.exists) {
        return null;
      }

      final data = doc.data()!;
      return {
        'buffaloPerKgFatRate':
            (data['buffaloPerKgFatRate'] as num?)?.toDouble() ?? 820.0,
        'cowEfuRate': (data['cowEfuRate'] as num?)?.toDouble() ?? 382.69,
        'cowDefaultSnf': (data['cowDefaultSnf'] as num?)?.toDouble() ?? 8.5,
        // SNF settings
        'buffaloSnf88to89Deduction': (data['buffaloSnf88to89Deduction'] as num?)?.toDouble() ?? 2.0,
        'buffaloSnf85to87Deduction': (data['buffaloSnf85to87Deduction'] as num?)?.toDouble() ?? 4.0,
        'buffaloSnf84Penalty': (data['buffaloSnf84Penalty'] as num?)?.toDouble() ?? 75.0,
        'buffaloLowQualityPenalty': (data['buffaloLowQualityPenalty'] as num?)?.toDouble() ?? 75.0,
        'cowSnf83to84Deduction': (data['cowSnf83to84Deduction'] as num?)?.toDouble() ?? 2.0,
        'cowSnf81to82Deduction': (data['cowSnf81to82Deduction'] as num?)?.toDouble() ?? 4.0,
        'cowHighFatDeduction': (data['cowHighFatDeduction'] as num?)?.toDouble() ?? 15.0,
        'cowSnf80Penalty': (data['cowSnf80Penalty'] as num?)?.toDouble() ?? 75.0,
        'cowLowFatPenalty': (data['cowLowFatPenalty'] as num?)?.toDouble() ?? 50.0,
      };
    } catch (e) {
      return null;
    }
  }

  /// Sync rate settings from Firestore to local SharedPreferences
  /// Called during fullSync to keep local device in sync with server
  Future<void> _syncRateSettingsToLocal() async {
    final firestoreSettings = await loadRateSettings();
    if (firestoreSettings == null) {
      // No settings in Firestore yet — upload current local settings
      final prefs = await SharedPreferences.getInstance();
      final localRate = prefs.getDouble('buffaloPerKgFatRate');
      if (localRate != null) {
        await syncRateSettings(
          buffaloPerKgFatRate: localRate,
          cowEfuRate: prefs.getDouble('cowEfuRate') ?? 382.69,
          cowDefaultSnf: prefs.getDouble('cowDefaultSnf') ?? 8.5,
          buffaloSnf88to89Deduction: prefs.getDouble('buffaloSnf88to89Deduction'),
          buffaloSnf85to87Deduction: prefs.getDouble('buffaloSnf85to87Deduction'),
          buffaloSnf84Penalty: prefs.getDouble('buffaloSnf84Penalty'),
          buffaloLowQualityPenalty: prefs.getDouble('buffaloLowQualityPenalty'),
          cowSnf83to84Deduction: prefs.getDouble('cowSnf83to84Deduction'),
          cowSnf81to82Deduction: prefs.getDouble('cowSnf81to82Deduction'),
          cowHighFatDeduction: prefs.getDouble('cowHighFatDeduction'),
          cowSnf80Penalty: prefs.getDouble('cowSnf80Penalty'),
          cowLowFatPenalty: prefs.getDouble('cowLowFatPenalty'),
        );
      }
      return;
    }

    // Firestore has settings — save to local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    for (final entry in firestoreSettings.entries) {
      await prefs.setDouble(entry.key, entry.value);
    }
  }

  /// Find admin email by mobile or userId from Firestore users collection
  /// Uses a public lookup collection that doesn't require authentication
  Future<String?> _findAdminEmailByMobileOrId(String input) async {
    try {
      // Check if input looks like an email
      if (input.contains('@')) {
        return input; // Already an email
      }

      // BUG FIX: Try multiple lookup methods with fallbacks

      // 1. Try public_lookups first (if available)
      try {
        // Try mobile lookup first
        var mobileQuery = await _firestore
            .collection('public_lookups')
            .doc('mobile_$input')
            .get();

        if (mobileQuery.exists) {
          return mobileQuery.data()?['email'] as String?;
        }

        // Try userId lookup
        var userIdQuery = await _firestore
            .collection('public_lookups')
            .doc('user_$input')
            .get();

        if (userIdQuery.exists) {
          return userIdQuery.data()?['email'] as String?;
        }
      } catch (e) {
      }

      // 2. FALLBACK: Search in dairies collection directly (PRIMARY SOURCE)
      // This is more reliable because dairies is always populated when account is created
      try {
        var dairiesQuery = await _firestore
            .collection('dairies')
            .where('mobile', isEqualTo: input)
            .limit(1)
            .get();

        if (dairiesQuery.docs.isNotEmpty) {
          return dairiesQuery.docs.first.data()['email'] as String?;
        }

        // Try by ownerId (userId/dairyId)
        final dairyDoc = await _firestore
            .collection('dairies')
            .doc(input)
            .get();
        if (dairyDoc.exists) {
          return dairyDoc.data()?['email'] as String?;
        }
      } catch (e) {
        // Permission denied is expected if rules don't allow this query
      }

      // 3. FALLBACK: Try users collection
      try {
        var query = await _firestore
            .collection('users')
            .where('mobile', isEqualTo: input)
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          return query.docs.first.data()['email'] as String?;
        }

        // Try to find by userId
        final userDoc = await _firestore.collection('users').doc(input).get();
        if (userDoc.exists) {
          return userDoc.data()?['email'] as String?;
        }
      } catch (e) {
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Login with email/mobile/userId and password
  Future<Map<String, dynamic>> login({
    required String emailOrMobileOrId,
    required String password,
  }) async {
    try {
      String? email;
      UserCredential? cred;

      // Step 1: Determine email — ghost email first for mobile, direct for @
      final cleanInput = emailOrMobileOrId.replaceAll(RegExp(r'\D'), '');
      if (cleanInput.length == 10) {
        // Mobile number → try ghost email first
        email = _adminGhostEmail(cleanInput);
        try {
          cred = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
            // Ghost email not found — legacy account, try old lookup
            final legacyEmail = await _findAdminEmailByMobileOrId(emailOrMobileOrId);
            if (legacyEmail != null && legacyEmail != email) {
              cred = await _auth.signInWithEmailAndPassword(
                email: legacyEmail,
                password: password,
              );
            } else {
              return {'success': false, 'error': 'Account not found / अकाउंट नहीं मिला'};
            }
          } else {
            rethrow;
          }
        }
      } else if (emailOrMobileOrId.contains('@')) {
        email = emailOrMobileOrId;
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // Dairy ID or other format → old lookup
        email = await _findAdminEmailByMobileOrId(emailOrMobileOrId);
        if (email == null) {
          return {'success': false, 'error': 'Account not found with this email/mobile/ID'};
        }
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = cred.user;
      if (user == null) {
        return {'success': false, 'error': 'Login failed'};
      }

      // Get user data from Firestore (check users collection first, then staff)
      var userDoc = await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic>? userData = userDoc.data();

      // If not found in users, check staff collection
      if (userData == null) {
        final staffDoc = await _firestore
            .collection('staff')
            .doc(user.uid)
            .get();
        userData = staffDoc.data();
      }

      _dairyId = userData?['dairyId'] ?? user.uid;
      await _saveSyncState();

      // Ensure _members doc exists for this admin
      await _ensureMembersDoc();

      // Ensure public_lookups has this user's mobile for future lookups
      try {
        final mobile = userData?['mobile'] as String? ?? '';
        if (mobile.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .set({
                'userId': user.uid,
                'name': userData?['name'] ?? userData?['ownerName'],
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      } catch (e) {
        // Non-critical
      }

      return {
        'success': true,
        'user': user,
        'dairyId': _dairyId,
        'userData': userData,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': e.message ?? 'Login failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign in with Google
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // Trigger Google Sign-In flow
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        return {'success': false, 'error': 'Google Sign-In cancelled'};
      }

      // Get Google auth credentials
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credentials
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        return {'success': false, 'error': 'Google Sign-In failed'};
      }

      // Check if user document exists in Firestore
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic>? userData;

      if (!userDoc.exists) {
        // Account does not exist in Firestore but Firebase Auth user exists
        // DON'T sign out - keep the user logged in and ask for additional info
        // Return needsSetup flag so UI can show setup dialog
        return {
          'success': false,
          'needsSetup': true,
          'user': user,
          'googleEmail': user.email,
          'googleName': user.displayName,
          'googlePhotoUrl': user.photoURL,
          'googleUid': user.uid,
          'error': 'Please complete your account setup.',
        };
      } else {
        userData = userDoc.data();
      }

      _dairyId = user.uid;
      await _saveSyncState();

      // Ensure _members doc exists for this admin
      await _ensureMembersDoc();

      // Ensure public_lookups has this user's mobile for future lookups
      // (older accounts may not have this entry)
      try {
        final mobile = userData?['mobile'] as String? ?? '';
        if (mobile.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .set({
                'userId': user.uid,
                'name': userData?['name'] ?? userData?['ownerName'] ?? user.displayName,
                'createdAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      } catch (e) {
        // Non-critical - don't fail login
      }

      return {
        'success': true,
        'user': user,
        'dairyId': user.uid,
        'userData': userData,
        'isNewUser': false,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Complete Google account setup - creates Firestore documents for already authenticated Google user
  Future<Map<String, dynamic>> completeGoogleAccountSetup({
    required String dairyName,
    required String mobile,
    String? address,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'No authenticated user found'};
      }

      // Try to check if mobile already registered (may fail due to security rules for new users)
      if (mobile.isNotEmpty) {
        try {
          final mobileCheck = await _firestore
              .collection('users')
              .where('mobile', isEqualTo: mobile)
              .limit(1)
              .get();

          if (mobileCheck.docs.isNotEmpty) {
            return {
              'success': false,
              'error': 'Mobile number already registered with another account',
            };
          }
        } catch (e) {
          // Permission denied - skip duplicate check, Firestore rules will handle it
        }
      }

      // Create user document
      final userData = {
        'email': user.email,
        'name': user.displayName ?? 'User',
        'dairyName': dairyName,
        'mobile': mobile,
        'address': address,
        'dairyId': user.uid,
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'photoUrl': user.photoURL,
      };
      await _firestore.collection('users').doc(user.uid).set(userData);

      // Create dairy document
      await _firestore.collection('dairies').doc(user.uid).set({
        'name': dairyName,
        'ownerName': user.displayName ?? 'User',
        'ownerId': user.uid,
        'email': user.email,
        'mobile': mobile,
        'address': address,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Populate public_lookups for future mobile lookups
      try {
        if (mobile.isNotEmpty) {
          await _firestore
              .collection('public_lookups')
              .doc('mobile_$mobile')
              .set({
                'userId': user.uid,
                'name': user.displayName ?? 'User',
                'createdAt': FieldValue.serverTimestamp(),
              });
        }
        await _firestore
            .collection('public_lookups')
            .doc('user_${user.uid}')
            .set({'createdAt': FieldValue.serverTimestamp()});
      } catch (e) {
        // Non-critical
      }

      // Create _members doc for Firestore rule access control
      try {
        await _firestore.collection('_members').doc(user.uid).set({
          'uids': [user.uid],
        });
      } catch (e) {
        // Non-critical
      }

      _dairyId = user.uid;
      await _saveSyncState();

      return {
        'success': true,
        'user': user,
        'dairyId': user.uid,
        'userData': userData,
        'isNewUser': true,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign in with Google and create account if not exists
  Future<Map<String, dynamic>> signInWithGoogleAndCreate({
    required String dairyName,
    required String mobile,
    String? address,
  }) async {
    try {
      // Trigger Google Sign-In flow
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();

      if (googleUser == null) {
        return {'success': false, 'error': 'Google Sign-In cancelled'};
      }

      // Get Google auth credentials
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credentials FIRST (needed for Firestore access)
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        return {'success': false, 'error': 'Google Sign-In failed'};
      }

      // Try to check if mobile already registered (may fail due to security rules)
      if (mobile.isNotEmpty) {
        try {
          final mobileCheck = await _firestore
              .collection('users')
              .where('mobile', isEqualTo: mobile)
              .limit(1)
              .get();

          if (mobileCheck.docs.isNotEmpty) {
            // Mobile already exists - sign out and return error
            await _auth.signOut();
            await googleSignIn.signOut();
            return {
              'success': false,
              'error': 'Mobile number already registered with another account',
            };
          }
        } catch (e) {
          // Permission denied - skip duplicate check
        }
      }

      // Create user document
      final userData = {
        'email': user.email,
        'name': user.displayName ?? 'User',
        'dairyName': dairyName,
        'mobile': mobile,
        'address': address,
        'dairyId': user.uid,
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'photoUrl': user.photoURL,
      };
      await _firestore.collection('users').doc(user.uid).set(userData);

      // Create dairy document
      await _firestore.collection('dairies').doc(user.uid).set({
        'name': dairyName,
        'ownerName': user.displayName ?? 'User',
        'ownerId': user.uid,
        'email': user.email,
        'mobile': mobile,
        'address': address,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _dairyId = user.uid;
      await _saveSyncState();

      return {
        'success': true,
        'user': user,
        'dairyId': user.uid,
        'userData': userData,
        'isNewUser': true,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Send password reset email
  Future<Map<String, dynamic>> sendPasswordResetEmail(
    String emailOrMobile,
  ) async {
    try {
      // Find email if user entered mobile
      String? email = await _findAdminEmailByMobileOrId(emailOrMobile);

      if (email == null) {
        return {
          'success': false,
          'error': 'Account not found with this email/mobile',
        };
      }

      await _auth.sendPasswordResetEmail(email: email);
      return {
        'success': true,
        'email': email,
        'message': 'Password reset link sent to $email',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Reset password with OTP verification
  /// First verify OTP, then update password in Firebase Auth
  Future<Map<String, dynamic>> resetPasswordWithOtp({
    required String email,
    required String newPassword,
  }) async {
    try {
      // For Firebase Auth, we need the user to be signed in to change password
      // Since user forgot password, we can't sign them in
      // So we use Firebase's password reset flow with action code
      // But for OTP-based reset, we need to verify OTP first (done in UI)
      // Then we need to use Admin SDK or a Cloud Function

      // Alternative approach: Delete and recreate the user (not ideal)
      // Best approach: Use Firebase Cloud Functions to update password

      // For now, we'll send a password reset link after OTP verification
      // This is secure because OTP was already verified
      await _auth.sendPasswordResetEmail(email: email);

      return {
        'success': true,
        'message': 'Password reset link sent to $email',
        'email': email,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Find account by mobile number
  /// FIXED: Check public_lookups FIRST (no auth required), then dairies/users
  Future<Map<String, dynamic>> findAccountByMobile(String mobile) async {
    try {
      // ── PRIORITY 1: public_lookups (public read, works without auth) ──
      try {
        final publicDoc = await _firestore
            .collection('public_lookups')
            .doc('mobile_$mobile')
            .get();

        if (publicDoc.exists) {
          final data = publicDoc.data()!;
          return {
            'success': true,
            'email': data['email'],
            'userId': data['userId'],
            'name': data['name'],
          };
        }
      } catch (e) {
        // Continue to next fallback
      }

      // ── PRIORITY 2: dairies collection (requires auth) ──
      try {
        final dairiesQuery = await _firestore
            .collection('dairies')
            .where('mobile', isEqualTo: mobile)
            .limit(1)
            .get();

        if (dairiesQuery.docs.isNotEmpty) {
          final dairyData = dairiesQuery.docs.first.data();
          return {
            'success': true,
            'email': dairyData['email'] ?? dairyData['ownerEmail'],
            'userId': dairiesQuery.docs.first.id,
            'name': dairyData['dairyName'] ?? dairyData['name'],
          };
        }
      } catch (e) {
        // Permission denied is expected if user is not signed in
      }

      // ── PRIORITY 3: users collection (requires auth) ──
      try {
        final usersQuery = await _firestore
            .collection('users')
            .where('mobile', isEqualTo: mobile)
            .limit(1)
            .get();

        if (usersQuery.docs.isNotEmpty) {
          final userData = usersQuery.docs.first.data();
          return {
            'success': true,
            'email': userData['email'],
            'userId': usersQuery.docs.first.id,
            'name': userData['name'] ?? userData['dairyName'],
          };
        }
      } catch (e) {
        // Continue
      }

      return {'success': false, 'error': 'Account not found'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Update password after OTP verification
  /// Uses ghost email pattern: {mobile}@dudhpassbook.com
  Future<Map<String, dynamic>> updatePasswordAfterOtpVerification({
    required String email,
    required String newPassword,
    PhoneAuthCredential? phoneCredential,
    String? mobile,
  }) async {
    try {
      User? user = _auth.currentUser;

      if (user == null) {
        // No user signed in — try ghost email reset approach
        final targetEmail = (mobile != null && mobile.isNotEmpty)
            ? _adminGhostEmail(mobile)
            : email;
        if (targetEmail.isNotEmpty) {
          // Ghost email is not a real email, can't send reset link
          // Try signIn + updatePassword approach
          return {'success': false, 'error': 'No user signed in. Please try OTP login first.'};
        }
        return {'success': false, 'error': 'No user signed in'};
      }

      // If user is signed in (via phone OTP), we can directly update password
      final hasPasswordProvider = user.providerData.any(
        (info) => info.providerId == 'password',
      );

      if (hasPasswordProvider) {
        // Already has password provider → update it
        try {
          await user.updatePassword(newPassword);
          return {
            'success': true,
            'message': 'Password updated successfully!',
            'passwordSet': true,
          };
        } catch (e) {
          // May need reauthentication — fall through
        }
      }
      
      // No password provider — need to link email/password
      // Use ghost email derived from mobile (or from user data)
      String ghostEmail = '';
      if (mobile != null && mobile.isNotEmpty) {
        ghostEmail = _adminGhostEmail(mobile);
      } else if (email.isNotEmpty && email.contains('@dudhpassbook.com')) {
        ghostEmail = email;
      } else {
        // Try to find mobile from user data
        try {
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          final userMobile = userDoc.data()?['mobile'] as String? ?? '';
          if (userMobile.isNotEmpty) {
            ghostEmail = _adminGhostEmail(userMobile);
          }
        } catch (_) {}
      }
      
      if (ghostEmail.isNotEmpty) {
        try {
          final emailCredential = EmailAuthProvider.credential(
            email: ghostEmail,
            password: newPassword,
          );
          await user.linkWithCredential(emailCredential);
          return {
            'success': true,
            'message': 'Password set successfully!',
            'passwordSet': true,
          };
        } catch (e) {
          // Linking might fail if ghost email already used → try updatePassword
          try {
            await user.updatePassword(newPassword);
            return {
              'success': true,
              'message': 'Password updated successfully!',
              'passwordSet': true,
            };
          } catch (_) {}
        }
      }

      // Final fallback for Google users: send reset to real email
      if (email.isNotEmpty && !email.contains('@dudhpassbook.com')) {
        try {
          await _auth.sendPasswordResetEmail(email: email);
          return {
            'success': true,
            'message': 'Password reset link sent to $email.',
            'emailSent': true,
            'email': email,
          };
        } catch (e) {
          return {'success': false, 'error': 'Failed to send reset email: $e'};
        }
      }

      return {'success': false, 'error': 'Could not set password'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get user profile data directly from Firestore server
  Future<Map<String, dynamic>?> getUserProfileFromServer() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        return userDoc.data();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Find a user by mobile number in Firestore (for OTP login)
  Future<Map<String, dynamic>?> findUserByMobile(String mobile) async {
    try {
      // ── PRIORITY 1: public_lookups → direct user doc read (no composite index needed) ──
      try {
        final publicDoc = await _firestore
            .collection('public_lookups')
            .doc('mobile_$mobile')
            .get();

        if (publicDoc.exists) {
          final userId = publicDoc.data()?['userId'] as String?;
          if (userId != null && userId.isNotEmpty) {
            final userDoc = await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final data = userDoc.data()!;
              return {
                'success': true,
                'userData': {
                  ...data,
                  'id': userDoc.id,
                },
                'dairyId': data['dairyId'] ?? userDoc.id,
              };
            }
          }
        }
      } catch (e) {
        // Continue to next fallback
      }

      // ── PRIORITY 2: dairies collection by mobile (single field, no composite index) ──
      try {
        final dairiesQuery = await _firestore
            .collection('dairies')
            .where('mobile', isEqualTo: mobile)
            .limit(1)
            .get();

        if (dairiesQuery.docs.isNotEmpty) {
          final dairyDoc = dairiesQuery.docs.first;
          final dairyData = dairyDoc.data();
          final userId = dairyDoc.id;

          // Try to get the full user document
          try {
            final userDoc = await _firestore.collection('users').doc(userId).get();
            if (userDoc.exists && userDoc.data() != null) {
              final data = userDoc.data()!;
              return {
                'success': true,
                'userData': {...data, 'id': userId},
                'dairyId': data['dairyId'] ?? userId,
              };
            }
          } catch (_) {}

          // If user doc not found, use dairy data as fallback
          return {
            'success': true,
            'userData': {
              ...dairyData,
              'id': userId,
              'role': 'admin',
              'name': dairyData['ownerName'] ?? dairyData['name'] ?? 'User',
            },
            'dairyId': userId,
          };
        }
      } catch (e) {
        // Permission denied or other error
      }

      // ── PRIORITY 3: users collection — simple mobile query (no role filter) ──
      try {
        final querySnapshot = await _firestore
            .collection('users')
            .where('mobile', isEqualTo: mobile)
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final doc = querySnapshot.docs.first;
          final data = doc.data();
          return {
            'success': true,
            'userData': {...data, 'id': doc.id},
            'dairyId': data['dairyId'] ?? doc.id,
          };
        }
      } catch (e) {
        // Continue
      }

      // ── PRIORITY 4: Try +91 prefix ──
      try {
        final querySnapshot2 = await _firestore
            .collection('users')
            .where('mobile', isEqualTo: '+91$mobile')
            .limit(1)
            .get();

        if (querySnapshot2.docs.isNotEmpty) {
          final doc = querySnapshot2.docs.first;
          final data = doc.data();
          return {
            'success': true,
            'userData': {...data, 'id': doc.id},
            'dairyId': data['dairyId'] ?? doc.id,
          };
        }
      } catch (e) {
        // Continue
      }

      return null; // User not found
    } catch (e) {
      return null;
    }
  }

  /// Update user profile in Firebase
  Future<Map<String, dynamic>> updateUserProfile({
    String? dairyName,
    String? ownerName,
    String? address,
    String? village,
    String? city,
    String? state,
    String? pincode,
    String? mobile,
    String? email,
    String? managerMobile,
    String? tagline,
    String? signatureLabel,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'Not authenticated'};
      }

      // Build update data
      final Map<String, dynamic> updateData = {
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (dairyName != null && dairyName.isNotEmpty) {
        updateData['dairyName'] = dairyName;
      }
      if (ownerName != null && ownerName.isNotEmpty) {
        updateData['name'] = ownerName;
      }
      if (address != null) updateData['address'] = address;
      if (village != null) updateData['village'] = village;
      if (city != null) updateData['city'] = city;
      if (state != null) updateData['state'] = state;
      if (pincode != null) updateData['pincode'] = pincode;
      if (mobile != null && mobile.isNotEmpty) updateData['mobile'] = mobile;
      if (email != null) updateData['email'] = email;
      if (managerMobile != null) updateData['managerMobile'] = managerMobile;
      if (tagline != null) updateData['tagline'] = tagline;
      if (signatureLabel != null) updateData['signatureLabel'] = signatureLabel;

      // Update user document
      await _firestore.collection('users').doc(user.uid).update(updateData);

      // Also update dairy document if exists
      try {
        final dairyDoc = await _firestore
            .collection('dairies')
            .doc(user.uid)
            .get();
        if (dairyDoc.exists) {
          final dairyUpdateData = <String, dynamic>{
            'updatedAt': FieldValue.serverTimestamp(),
          };
          if (dairyName != null && dairyName.isNotEmpty) {
            dairyUpdateData['name'] = dairyName;
          }
          if (ownerName != null && ownerName.isNotEmpty) {
            dairyUpdateData['ownerName'] = ownerName;
          }
          if (mobile != null && mobile.isNotEmpty) {
            dairyUpdateData['mobile'] = mobile;
          }
          if (address != null) dairyUpdateData['address'] = address;
          if (village != null) dairyUpdateData['village'] = village;
          if (city != null) dairyUpdateData['city'] = city;
          if (state != null) dairyUpdateData['state'] = state;
          if (pincode != null) dairyUpdateData['pincode'] = pincode;
          if (email != null) dairyUpdateData['email'] = email;
          if (managerMobile != null) {
            dairyUpdateData['managerMobile'] = managerMobile;
          }
          if (tagline != null) dairyUpdateData['tagline'] = tagline;
          if (signatureLabel != null) {
            dairyUpdateData['signatureLabel'] = signatureLabel;
          }

          await _firestore
              .collection('dairies')
              .doc(user.uid)
              .update(dairyUpdateData);
        }
      } catch (e) {
        // Dairy document might not exist, that's okay
      }

      return {'success': true, 'message': 'Profile updated successfully'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // =============================================
  // SECURE LOGOUT — COMPLETE STATE TEARDOWN
  // =============================================

  /// Whether a logout is currently in progress (prevents double-logout)
  bool _isLoggingOut = false;

  /// Low-level logout: tears down ALL in-memory state + auth.
  /// For a full secure logout (DB + prefs + cache), use [performSecureLogout].
  Future<void> logout() async {
    // 1. Stop all realtime Firestore listeners FIRST
    stopRealtimeSync();

    // 2. Clear callback to avoid calling into disposed widgets
    onDataChanged = null;

    // 3. Reset sync guards so next login starts clean
    _isSyncing = false;
    _lastSyncAt = null;

    // 4. Sign out from Google (ignore errors)
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    } catch (_) {}

    // 5. Sign out from Firebase Auth
    try {
      await _auth.signOut();
    } catch (_) {}

    // 6. Clear dairy ID
    _dairyId = null;
  }

  /// Production-safe, centralized logout.
  /// Call from ANY screen — handles everything:
  ///   - Stops realtime listeners & clears in-memory state
  ///   - Signs out Firebase Auth + Google
  ///   - Resets SQLite database (delete + recreate)
  ///   - Clears SharedPreferences (preserves UI settings like language/theme)
  ///   - Clears Firestore local persistence cache
  Future<void> performSecureLogout() async {
    if (_isLoggingOut) return; // prevent double-tap
    _isLoggingOut = true;
    try {
      // Step 1: Core logout (listeners, auth, in-memory)
      await logout();

      // Step 2: Reset SQLite database — delete file + recreate empty tables
      try {
        await _db.resetDatabase();
      } catch (e) {
        debugPrint('[SecureLogout] DB reset error: $e');
      }

      // Step 3: Clear SharedPreferences (preserve UI settings)
      try {
        final prefs = await SharedPreferences.getInstance();
        // Keys to PRESERVE across logouts
        final preserveKeys = {
          'language_code', 'language_selected', 'theme_mode',
          'quickEntryMode', 'autoCalculateRate', 'showFatSnfWarning',
          'showEntryConfirmation', 'defaultShift',
          'minFatWarningBuffalo', 'maxFatWarningBuffalo',
          'minFatWarningCow', 'maxFatWarningCow',
          'soundOnEntry', 'printAfterBilling',
        };
        final allKeys = prefs.getKeys().toSet();
        for (final key in allKeys) {
          if (!preserveKeys.contains(key)) {
            await prefs.remove(key);
          }
        }
      } catch (e) {
        debugPrint('[SecureLogout] Prefs clear error: $e');
      }

      // Step 4: Clear Firestore local cache to prevent stale data on next login
      try {
        await _firestore.clearPersistence();
      } catch (e) {
        // clearPersistence may throw if there are active listeners — safe to ignore
        // since we already stopped all listeners in step 1
        debugPrint('[SecureLogout] Firestore cache clear: $e');
      }
    } finally {
      _isLoggingOut = false;
    }
  }

  // =============================================
  // FULL SYNC - BIDIRECTIONAL
  // =============================================

  /// Perform full bidirectional sync
  /// If isNewUser is true, only download data (don't upload local data to avoid data pollution)
  Future<Map<String, dynamic>> fullSync({
    int? localDairyId,
    bool isNewUser = false,
    bool force = false,
  }) async {
    if (_isLoggingOut) {
      return {'success': false, 'error': 'Logout in progress — sync blocked'};
    }
    if (_isSyncing) {
      return {'success': false, 'error': 'Sync already in progress'};
    }
    // Throttle: skip if last sync was within cooldown period (unless forced)
    if (!force && _lastSyncAt != null && 
        DateTime.now().difference(_lastSyncAt!) < _syncCooldown) {
      return {'success': true, 'message': 'Skipped — synced recently', 'uploaded': 0, 'downloaded': 0};
    }
    if (!isAuthenticated || dairyId == null) {
      return {'success': false, 'error': 'Not authenticated'};
    }

    _isSyncing = true;
    int uploaded = 0;
    int downloaded = 0;

    try {
      // Ensure _members doc exists for this admin (migration for existing accounts)
      await _ensureMembersDoc();

      // Get local dairyId from SQLite
      final prefs = await SharedPreferences.getInstance();
      final sqliteDairyId = localDairyId ?? prefs.getInt('dairyId');

      // Sync Farmers
      final farmerResult = await _syncFarmers(
        sqliteDairyId,
        downloadOnly: isNewUser,
      );
      uploaded += farmerResult['uploaded'] ?? 0;
      downloaded += farmerResult['downloaded'] ?? 0;

      // Sync Milk Entries
      final entryResult = await _syncMilkEntries(
        sqliteDairyId,
        downloadOnly: isNewUser,
      );
      uploaded += entryResult['uploaded'] ?? 0;
      downloaded += entryResult['downloaded'] ?? 0;

      // Sync Payments - CRITICAL: Don't upload local payments for new user
      final paymentResult = await _syncPayments(
        sqliteDairyId,
        downloadOnly: isNewUser,
      );
      uploaded += paymentResult['uploaded'] ?? 0;
      downloaded += paymentResult['downloaded'] ?? 0;

      // Sync Staff
      final staffResult = await _syncStaff(
        sqliteDairyId,
        downloadOnly: isNewUser,
      );
      uploaded += staffResult['uploaded'] ?? 0;
      downloaded += staffResult['downloaded'] ?? 0;

      // Sync Rate Settings (Firestore → local SharedPreferences)
      try {
        await _syncRateSettingsToLocal();
      } catch (_) {}

      _lastSyncAt = DateTime.now();
      await _saveSyncState();

      _isSyncing = false;
      return {
        'success': true,
        'uploaded': uploaded,
        'downloaded': downloaded,
        'lastSyncAt': _lastSyncAt,
      };
    } catch (e) {
      _isSyncing = false;
      return {'success': false, 'error': e.toString()};
    }
  }

  // =============================================
  // FARMERS SYNC
  // =============================================

  Future<Map<String, int>> _syncFarmers(
    int? sqliteDairyId, {
    bool downloadOnly = false,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    // Get local farmers
    final localFarmers = await _db.getAllFarmers(dairyId: sqliteDairyId);
    final localFarmerMap = {for (var f in localFarmers) f.code: f};

    // Get Firestore farmers
    final snapshot = await _firestore
        .collection('farmers')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    final remoteFarmerMap = <String, Map<String, dynamic>>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      remoteFarmerMap[data['code'] ?? ''] = data;
    }

    // Upload local farmers not in Firestore (SKIP if downloadOnly)
    if (!downloadOnly) {
      for (var farmer in localFarmers) {
        if (!remoteFarmerMap.containsKey(farmer.code)) {
          await _uploadFarmer(farmer);
          uploaded++;
        } else {
          // Update if local is newer
          final remote = remoteFarmerMap[farmer.code]!;
          final remoteUpdated = (remote['updatedAt'] as Timestamp?)?.toDate();
          if (remoteUpdated == null ||
              farmer.createdAt.isAfter(remoteUpdated)) {
            await _updateFirestoreFarmer(remote['firestoreId'], farmer);
            uploaded++;
          }
        }
      }
    }

    // Download remote farmers not in local
    for (var entry in remoteFarmerMap.entries) {
      if (!localFarmerMap.containsKey(entry.key)) {
        await _downloadFarmer(entry.value, sqliteDairyId);
        downloaded++;
      }
    }

    return {'uploaded': uploaded, 'downloaded': downloaded};
  }

  Future<void> _uploadFarmer(Farmer farmer) async {
    await _firestore.collection('farmers').add({
      'code': farmer.code,
      'name': farmer.name,
      'fatherName': farmer.fatherName,
      'mobile': farmer.mobile,
      'cattleType': farmer.cattleType,
      'defaultCattleType': farmer.cattleType,
      'useFixedRate': farmer.useFixedRate,
      'fixedRate': farmer.fixedRate,
      'cowFixedRate': farmer.cowFixedRate,
      'buffaloFixedRate': farmer.buffaloFixedRate,
      'currentBalance': farmer.currentBalance,
      'dairyId': dairyId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isActive': farmer.isActive,
      'serverId': farmer.id,
    });
  }

  Future<void> _updateFirestoreFarmer(String docId, Farmer farmer) async {
    await _firestore.collection('farmers').doc(docId).update({
      'name': farmer.name,
      'fatherName': farmer.fatherName,
      'mobile': farmer.mobile,
      'cattleType': farmer.cattleType,
      'useFixedRate': farmer.useFixedRate,
      'fixedRate': farmer.fixedRate,
      'cowFixedRate': farmer.cowFixedRate,
      'buffaloFixedRate': farmer.buffaloFixedRate,
      'currentBalance': farmer.currentBalance,
      'isActive': farmer.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _downloadFarmer(
    Map<String, dynamic> data,
    int? sqliteDairyId,
  ) async {
    final farmer = Farmer(
      code: data['code'] ?? '',
      name: data['name'] ?? '',
      fatherName: data['fatherName'],
      mobile: data['mobile'] ?? '',
      cattleType: data['cattleType'] ?? data['defaultCattleType'] ?? 'cow',
      useFixedRate: data['useFixedRate'] ?? false,
      fixedRate: (data['fixedRate'] as num?)?.toDouble(),
      cowFixedRate: (data['cowFixedRate'] as num?)?.toDouble(),
      buffaloFixedRate: (data['buffaloFixedRate'] as num?)?.toDouble(),
      currentBalance: (data['currentBalance'] as num?)?.toDouble() ?? 0.0,
      isActive: data['isActive'] ?? true,
      dairyId: sqliteDairyId,
    );
    await _db.insertFarmer(farmer);
  }

  // =============================================
  // MILK ENTRIES SYNC
  // =============================================

  Future<Map<String, int>> _syncMilkEntries(
    int? sqliteDairyId, {
    bool downloadOnly = false,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    // Get local entries (last 30 days for sync)
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final localEntries = await _db.getMilkEntries(
      startDate: thirtyDaysAgo,
      endDate: DateTime.now(),
      dairyId: sqliteDairyId,
    );

    // Get Firestore entries - only filter by dairyId to avoid index requirement
    final snapshot = await _firestore
        .collection('milkEntries')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    // ---- ONE-TIME DEDUP CLEANUP of Firestore milkEntries ----
    // Remove docs that are true duplicates: same syncId OR same composite key
    int dedupDeleted = 0;
    try {
      final seenSignatures = <String, String>{}; // uniqueKey → first doc id
      final docsToDelete = <String>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final syncId = data['syncId'] as String?;
        String signature;
        if (syncId != null && syncId.isNotEmpty) {
          signature = 'sid_$syncId';
        } else {
          // Legacy: composite key for docs without syncId (includes cattleType)
          final dateTime = data['dateTime'] ?? data['date'] ?? '';
          final cattleType = data['cattleType'] ?? 'cow';
          signature = '${data['farmerCode']}_${dateTime}_${data['shift']}_$cattleType';
        }
        if (seenSignatures.containsKey(signature)) {
          docsToDelete.add(doc.id);
        } else {
          seenSignatures[signature] = doc.id;
        }
      }
      for (var docId in docsToDelete) {
        await _firestore.collection('milkEntries').doc(docId).delete();
      }
      dedupDeleted = docsToDelete.length;
      if (dedupDeleted > 0) {
        debugPrint('🧹 Cleaned $dedupDeleted duplicate milkEntry(ies) from Firestore');
      }
    } catch (e) {
      debugPrint('[syncMilkEntries] dedup cleanup error: $e');
    }

    // Re-fetch after cleanup to get accurate state (only if we deleted dupes)
    final cleanSnapshot = dedupDeleted > 0
        ? await _firestore.collection('milkEntries').where('dairyId', isEqualTo: dairyId).get()
        : snapshot;

    // Build sets using syncId (UUID) as primary dedup key, with legacy fallback
    final localSyncIds = <String>{};
    final localLegacyKeys = <String>{};
    for (var entry in localEntries) {
      localSyncIds.add(entry.syncId);
      // Legacy key fallback for entries without syncId in Firestore (includes cattleType)
      final legacyKey = '${entry.farmerCode}_${entry.dateTime.toIso8601String()}_${entry.shift}_${entry.cattleType}';
      localLegacyKeys.add(legacyKey);
    }

    final remoteSyncIds = <String>{};
    final remoteEntries = <Map<String, dynamic>>[];
    for (var doc in cleanSnapshot.docs) {
      final data = doc.data();
      // Filter by date client-side
      final timestamp = data['timestamp'] as int? ?? 0;
      if (timestamp < thirtyDaysAgo.millisecondsSinceEpoch) continue;

      data['firestoreId'] = doc.id;
      final syncId = data['syncId'] as String?;
      if (syncId != null) remoteSyncIds.add(syncId);
      remoteEntries.add(data);
    }

    // Upload local entries not in Firestore (SKIP if downloadOnly)
    if (!downloadOnly) {
      for (var entry in localEntries) {
        if (!remoteSyncIds.contains(entry.syncId)) {
          await _uploadMilkEntry(entry);
          uploaded++;
        }
      }
    }

    // Download remote entries not in local
    for (var data in remoteEntries) {
      final remoteSyncId = data['syncId'] as String?;
      if (remoteSyncId != null && localSyncIds.contains(remoteSyncId)) continue;
      // Legacy fallback: check by composite key (includes cattleType)
      final dateTime = data['dateTime'] ?? '';
      final cattleType = data['cattleType'] ?? 'cow';
      final legacyKey = '${data['farmerCode']}_${dateTime}_${data['shift']}_$cattleType';
      if (localLegacyKeys.contains(legacyKey)) continue;
      await _downloadMilkEntry(data, sqliteDairyId);
      downloaded++;
    }

    return {'uploaded': uploaded, 'downloaded': downloaded};
  }

  Future<void> _uploadMilkEntry(MilkEntry entry) async {
    final date =
        '${entry.dateTime.year}-${entry.dateTime.month.toString().padLeft(2, '0')}-${entry.dateTime.day.toString().padLeft(2, '0')}';

    // BUG FIX: Use syncId as document ID + set() instead of add() to make uploads
    // idempotent. If the same entry is uploaded twice (e.g., during account switch),
    // it overwrites the same document instead of creating a duplicate.
    await _firestore.collection('milkEntries').doc(entry.syncId).set({
      'farmerId': entry.farmerCode, // Use code as ID for cross-platform
      'farmerCode': entry.farmerCode,
      'farmerName': entry.farmerName,
      'date': date,
      'dateTime': entry.dateTime.toIso8601String(),
      'shift': entry.shift,
      'cattleType': entry.cattleType,
      'quantity': entry.quantity,
      'fat': entry.fat,
      'snf': entry.snf ?? 0,
      'rate': entry.rate,
      'amount': entry.amount,
      'totalAmount': entry.amount,
      'isPending': entry.isPending,
      'status': entry.isPending ? 'PENDING' : 'COMPLETED',
      'isLabTested': entry.isLabTested,
      'collectorName': entry.collectorName,
      'createdByUserId': entry.createdByUserId,
      'createdByUserName': entry.createdByUserName,
      'dairyId': dairyId,
      'syncId': entry.syncId,
      'timestamp': entry.dateTime.millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _downloadMilkEntry(
    Map<String, dynamic> data,
    int? sqliteDairyId,
  ) async {
    // IGNORE cloud farmerId (could be a String from website) — always use local lookup
    String? farmerCode = data['farmerCode'] as String?;
    final farmerName = data['farmerName'] as String?;

    // Fallback: if farmerCode is missing (website format), find farmer by name
    if ((farmerCode == null || farmerCode.isEmpty) && farmerName != null) {
      final farmerByName = await _db.getFarmerByName(
        farmerName,
        dairyId: sqliteDairyId,
      );
      if (farmerByName != null) {
        farmerCode = farmerByName.code;
      }
    }

    if (farmerCode == null || farmerCode.isEmpty) return;

    // Find farmer by code — use LOCAL farmer.id, not cloud farmerId
    final farmer = await _db.getFarmerByCode(
      farmerCode,
      dairyId: sqliteDairyId,
    );
    if (farmer == null) return; // Skip if farmer not found locally

    DateTime dateTime;
    try {
      dateTime = DateTime.parse(
        data['dateTime'] ?? data['date'] ?? DateTime.now().toIso8601String(),
      );
    } catch (e) {
      dateTime = DateTime.now();
    }

    final entry = MilkEntry(
      farmerId: farmer.id!, // Always use LOCAL farmer ID, never cloud farmerId
      farmerCode: farmerCode,
      farmerName: farmerName ?? farmer.name,
      dateTime: dateTime,
      shift: data['shift'] ?? 'morning',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      fat: (data['fat'] as num?)?.toDouble() ?? 0,
      snf: (data['snf'] as num?)?.toDouble(),
      rate: (data['rate'] as num?)?.toDouble() ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? (data['totalAmount'] as num?)?.toDouble() ?? 0,
      cattleType: data['cattleType'] ?? 'cow',
      isPending: data['isPending'] ?? data['status'] == 'PENDING',
      isLabTested: data['isLabTested'] ?? true,
      collectorName: data['collectorName'],
      createdByUserId: (data['createdByUserId'] as num?)?.toInt(),
      createdByUserName: data['createdByUserName'],
      dairyId: sqliteDairyId,
      syncId: data['syncId'] as String?,
    );

    await _db.insertMilkEntry(entry);
  }

  // =============================================
  // PAYMENTS SYNC
  // =============================================

  Future<Map<String, int>> _syncPayments(
    int? sqliteDairyId, {
    bool downloadOnly = false,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    // Get Firestore payments
    final snapshot = await _firestore
        .collection('payments')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    // Helper: Normalize any date value to YYYY-MM-DD string
    String normalizeDateStr(dynamic dateValue) {
      if (dateValue == null) return '';
      if (dateValue is Timestamp) {
        final dt = dateValue.toDate();
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      }
      if (dateValue is DateTime) {
        return '${dateValue.year}-${dateValue.month.toString().padLeft(2, '0')}-${dateValue.day.toString().padLeft(2, '0')}';
      }
      if (dateValue is String) {
        try {
          final dt = DateTime.parse(dateValue);
          return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        } catch (_) {
          if (dateValue.contains('T')) return dateValue.split('T')[0];
          if (dateValue.contains(' ')) return dateValue.split(' ')[0];
          return dateValue;
        }
      }
      return dateValue.toString();
    }

    // ---- ONE-TIME DEDUP CLEANUP of Firestore payments ----
    // Only remove docs that are true duplicates: same syncId (actual duplicate upload).
    // Docs WITHOUT syncId use compound-key dedup (legacy data only).
    // Two docs with DIFFERENT syncIds are NEVER duplicates, even with same content.
    try {
      final seenSignatures = <String, String>{}; // uniqueKey -> first doc id
      final docsToDelete = <String>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final syncId = data['syncId'] as String?;
        String signature;
        if (syncId != null && syncId.isNotEmpty) {
          // syncId is globally unique — use it directly
          signature = 'sid_$syncId';
        } else {
          // Legacy: compound key for docs created before syncId was added
          dynamic dateVal = data['date'] ?? data['paymentDate'];
          String dateStr = '';
          if (dateVal is Timestamp) {
            final dt = dateVal.toDate();
            dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          } else if (dateVal is DateTime) {
            dateStr = '${dateVal.year}-${dateVal.month.toString().padLeft(2, '0')}-${dateVal.day.toString().padLeft(2, '0')}';
          } else if (dateVal is String) {
            try {
              final dt = DateTime.parse(dateVal);
              dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            } catch (_) {
              dateStr = dateVal.contains('T') ? dateVal.split('T')[0] : dateVal;
            }
          }
          final amt = (data['netAmount'] ?? data['amount']);
          final amtStr = (amt is num) ? amt.toStringAsFixed(2) : (amt ?? '0').toString();
          final fromDateStr = normalizeDateStr(data['fromDate']);
          final toDateStr = normalizeDateStr(data['toDate']);
          final mode = (data['paymentMode'] ?? '').toString();
          final totalLiters = (data['totalLiters'] is num) ? (data['totalLiters'] as num).toStringAsFixed(2) : '0.00';
          signature = '${data['farmerCode'] ?? ''}_${dateStr}_${data['type'] ?? 'PAYMENT'}_${amtStr}_${fromDateStr}_${toDateStr}_${mode}_$totalLiters';
        }
        
        if (seenSignatures.containsKey(signature)) {
          docsToDelete.add(doc.id);
        } else {
          seenSignatures[signature] = doc.id;
        }
      }
      for (var docId in docsToDelete) {
        await _firestore.collection('payments').doc(docId).delete();
      }
      if (docsToDelete.isNotEmpty) {
        debugPrint('🧹 Cleaned ${docsToDelete.length} duplicate payment(s) from Firestore');
      }
    } catch (e) {
      debugPrint('⚠️ Dedup cleanup error: $e');
    }

    // ---- LOCAL DEDUP CLEANUP ----
    // Only dedup rows that share the same syncId (actual duplicate inserts).
    // Rows with different syncIds (or no syncId) and same content are legitimate duplicates.
    try {
      final db = await _db.database;
      final allLocalPayments = await db.query('payments',
          where: 'dairyId = ?', whereArgs: [sqliteDairyId], orderBy: 'id ASC');
      final seenPayKeys = <String, int>{}; // uniqueKey -> first row id
      final payIdsToDelete = <int>[];
      for (var row in allLocalPayments) {
        final syncId = (row['syncId'] ?? '').toString();
        String key;
        if (syncId.isNotEmpty) {
          // syncId is unique per payment — use it directly
          key = 'sid_$syncId';
        } else {
          // Legacy: compound key for rows without syncId
          final dateStr = (row['paymentDate'] ?? '').toString();
          String normalizedDate = dateStr;
          try {
            final dt = DateTime.parse(dateStr);
            normalizedDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          } catch (_) {}
          final amt = (row['netAmount'] is num) ? (row['netAmount'] as num).toStringAsFixed(2) : (row['netAmount'] ?? '0').toString();
          final fromDate = (row['fromDate'] ?? '').toString();
          final toDate = (row['toDate'] ?? '').toString();
          final mode = (row['paymentMode'] ?? '').toString();
          final liters = (row['totalLiters'] is num) ? (row['totalLiters'] as num).toStringAsFixed(2) : '0.00';
          key = '${row['farmerCode']}_${normalizedDate}_${row['type'] ?? 'PAYMENT'}_${amt}_${fromDate}_${toDate}_${mode}_$liters';
        }
        if (seenPayKeys.containsKey(key)) {
          payIdsToDelete.add(row['id'] as int);
        } else {
          seenPayKeys[key] = row['id'] as int;
        }
      }
      for (var id in payIdsToDelete) {
        await db.delete('payments', where: 'id = ?', whereArgs: [id]);
      }
      if (payIdsToDelete.isNotEmpty) {
        debugPrint('🧹 Cleaned ${payIdsToDelete.length} duplicate local payment(s)');
      }

      // Dedup local advances: advances don't have syncId, so use their primary key (id)
      // to avoid deleting legitimate same-content advances. Only remove if exact same id.
      // (No dedup needed — each row has a unique auto-increment id)
    } catch (e) {
      debugPrint('⚠️ Local dedup cleanup error: $e');
    }

    // Re-read local payments after cleanup
    final cleanLocalPayments = await _db.getPayments(dairyId: sqliteDairyId);

    // Re-fetch after cleanup to get clean snapshot
    final cleanSnapshot = await _firestore
        .collection('payments')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    // Build a unique key for payments.
    // IMPORTANT: Uses multiple fields to distinguish legitimate same-amount, same-day payments.
    // farmerCode + date + type + amount + fromDate + toDate + paymentMode + totalLiters
    String makeKey(String farmerCode, dynamic dateVal, String type, dynamic amount,
        {String? fromDate, String? toDate, String? paymentMode, dynamic totalLiters}) {
      final dateStr = normalizeDateStr(dateVal);
      final amt = (amount is num) ? amount.toStringAsFixed(2) : (amount ?? '0').toString();
      final from = normalizeDateStr(fromDate);
      final to = normalizeDateStr(toDate);
      final mode = paymentMode ?? '';
      final liters = (totalLiters is num) ? totalLiters.toStringAsFixed(2) : '0.00';
      return '${farmerCode}_${dateStr}_${type}_${amt}_${from}_${to}_${mode}_$liters';
    }

    // ---------- MULTISET-BASED SYNC ----------
    // A multiset (Map<key, count>) allows two ₹500 payments on the same day
    // to both exist — each gets counted separately.

    // Build remote multiset
    final remoteMultiset = <String, int>{};
    final remotePaymentsByKey = <String, List<Map<String, dynamic>>>{};
    for (var doc in cleanSnapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      final key = makeKey(
        data['farmerCode'] ?? '',
        data['date'] ?? data['paymentDate'],
        data['type'] ?? 'PAYMENT',
        data['netAmount'] ?? data['amount'],
        fromDate: data['fromDate']?.toString(),
        toDate: data['toDate']?.toString(),
        paymentMode: data['paymentMode']?.toString(),
        totalLiters: data['totalLiters'],
      );
      remoteMultiset[key] = (remoteMultiset[key] ?? 0) + 1;
      remotePaymentsByKey.putIfAbsent(key, () => []).add(data);
    }

    // Build local multiset from BOTH payments AND advances
    final localMultiset = <String, int>{};
    final localPaymentsByKey = <String, List<Payment>>{};
    for (var payment in cleanLocalPayments) {
      final key = makeKey(
        payment.farmerCode,
        payment.paymentDate,
        payment.type,
        payment.netAmount,
        fromDate: payment.fromDate?.toIso8601String(),
        toDate: payment.toDate?.toIso8601String(),
        paymentMode: payment.paymentMode,
        totalLiters: payment.totalLiters,
      );
      localMultiset[key] = (localMultiset[key] ?? 0) + 1;
      localPaymentsByKey.putIfAbsent(key, () => []).add(payment);
    }

    // Also include local advances in multiset
    final localAdvances = await _db.getAdvances(dairyId: sqliteDairyId);
    final localAdvancesByKey = <String, List<dynamic>>{};
    for (var advance in localAdvances) {
      final key = makeKey(
        advance.farmerCode,
        advance.date,
        'ADVANCE',
        advance.amount,
      );
      localMultiset[key] = (localMultiset[key] ?? 0) + 1;
      localAdvancesByKey.putIfAbsent(key, () => []).add(advance);
    }

    // Upload: for each key, if local count > remote count, upload the difference
    if (!downloadOnly) {
      for (var key in localMultiset.keys) {
        final localCount = localMultiset[key] ?? 0;
        final remoteCount = remoteMultiset[key] ?? 0;
        final toUpload = localCount - remoteCount;
        if (toUpload > 0) {
          // Upload Payment objects first, then advances
          final payments = localPaymentsByKey[key] ?? [];
          final advances = localAdvancesByKey[key] ?? [];
          int uploadedSoFar = 0;
          
          // Upload payments
          for (var p in payments) {
            if (uploadedSoFar >= toUpload) break;
            await _uploadPayment(p);
            uploaded++;
            uploadedSoFar++;
          }
          // Upload advances
          for (var advance in advances) {
            if (uploadedSoFar >= toUpload) break;
            await _firestore.collection('payments').add({
              'syncId': const Uuid().v4(),
              'farmerId': advance.farmerCode,
              'farmerCode': advance.farmerCode,
              'farmerName': advance.farmerName,
              'date': advance.date.toIso8601String(),
              'type': 'ADVANCE',
              'amount': advance.amount,
              'netAmount': advance.amount,
              'remarks': advance.remarks,
              'isPaid': advance.isPaid,
              'dairyId': dairyId,
              'timestamp': advance.date.millisecondsSinceEpoch,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            uploaded++;
            uploadedSoFar++;
          }
        }
      }
    }

    // Download: for each key, if remote count > local count, download the difference
    for (var key in remoteMultiset.keys) {
      final remoteCount = remoteMultiset[key] ?? 0;
      final localCount = localMultiset[key] ?? 0;
      final toDownload = remoteCount - localCount;
      if (toDownload > 0) {
        final remoteDocs = remotePaymentsByKey[key] ?? [];
        // Download only the extra remote docs (skip the first `localCount` ones)
        for (var i = localCount; i < remoteDocs.length && (i - localCount) < toDownload; i++) {
          await _downloadPayment(remoteDocs[i], sqliteDairyId);
          downloaded++;
        }
      }
    }

    return {'uploaded': uploaded, 'downloaded': downloaded};
  }

  Future<void> _uploadPayment(Payment payment) async {
    await _firestore.collection('payments').add({
      'syncId': payment.syncId,
      'farmerId': payment.farmerCode,
      'farmerCode': payment.farmerCode,
      'farmerName': payment.farmerName,
      'date': payment.paymentDate.toIso8601String(),
      'paymentDate': payment.paymentDate.toIso8601String(),
      'type': payment.type,
      'amount': payment.netAmount,
      'fromDate': payment.fromDate?.toIso8601String(),
      'toDate': payment.toDate?.toIso8601String(),
      'totalAmount': payment.amount,
      'advanceDeduction': payment.advanceDeduction,
      'netAmount': payment.netAmount,
      'totalLiters': payment.totalLiters,
      'paymentMode': payment.paymentMode,
      'transactionId': payment.transactionId,
      'notes': payment.notes,
      'isPaid': payment.isPaid,
      'dairyId': dairyId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _downloadPayment(
    Map<String, dynamic> data,
    int? sqliteDairyId,
  ) async {
    // IGNORE cloud farmerId (could be a String from website) — always use local lookup
    String? farmerCode = data['farmerCode'] as String?;
    final farmerName = data['farmerName'] as String?;

    // Fallback: if farmerCode is missing (website format), find farmer by name
    if ((farmerCode == null || farmerCode.isEmpty) && farmerName != null) {
      final farmerByName = await _db.getFarmerByName(
        farmerName,
        dairyId: sqliteDairyId,
      );
      if (farmerByName != null) {
        farmerCode = farmerByName.code;
      }
    }

    if (farmerCode == null || farmerCode.isEmpty) return;

    // Find farmer by code — use LOCAL farmer.id, not cloud farmerId
    final farmer = await _db.getFarmerByCode(
      farmerCode,
      dairyId: sqliteDairyId,
    );
    if (farmer == null) return;

    // Helper to parse date from Firestore (could be Timestamp, String, or DateTime)
    DateTime parseFirestoreDate(dynamic value, {DateTime? fallback}) {
      if (value == null) return fallback ?? DateTime.now();
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return fallback ?? DateTime.now();
        }
      }
      return fallback ?? DateTime.now();
    }

    // ALL types (PAYMENT and ADVANCE) are stored in the 'payments' table.
    // The UI reads from payments table and filters by type.
    final paymentDate = parseFirestoreDate(data['date'] ?? data['paymentDate']);
    final fromDate = parseFirestoreDate(data['fromDate'], fallback: paymentDate);
    final toDate = parseFirestoreDate(data['toDate'], fallback: paymentDate);
    final type = data['type'] ?? 'PAYMENT';

    final netAmt = (data['netAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0;
    final totalAmt = (data['totalAmount'] as num?)?.toDouble() ?? netAmt;

    final payment = Payment(
      farmerId: farmer.id!, // Always use LOCAL farmer ID, never cloud farmerId
      farmerCode: farmerCode,
      farmerName: farmerName ?? farmer.name,
      paymentDate: paymentDate,
      fromDate: fromDate,
      toDate: toDate,
      type: type,
      amount: totalAmt,
      advanceDeduction: (data['advanceDeduction'] as num?)?.toDouble() ?? 0,
      netAmount: netAmt,
      totalLiters: (data['totalLiters'] as num?)?.toDouble() ?? 0,
      paymentMode: data['paymentMode'] ?? 'cash',
      transactionId: data['transactionId'],
      notes: data['notes'] ?? data['remarks'],
      isPaid: data['isPaid'] ?? false,
      dairyId: sqliteDairyId,
      syncId: data['syncId'] as String?,
    );
    await _db.insertPayment(payment);
  }

  // =============================================
  // STAFF SYNC
  // =============================================

  Future<Map<String, int>> _syncStaff(
    int? sqliteDairyId, {
    bool downloadOnly = false,
  }) async {
    int uploaded = 0;
    int downloaded = 0;

    // Get local staff
    final localStaff = await _db.getAllUsers(dairyId: sqliteDairyId);

    // Get Firestore staff
    final snapshot = await _firestore
        .collection('staff')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    final localStaffMobiles = <String?>{};
    for (var s in localStaff) {
      if (s['role'] == 'staff') {
        localStaffMobiles.add(s['mobile'] as String?);
      }
    }

    final remoteStaffMap = <String, Map<String, dynamic>>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      data['firestoreId'] = doc.id;
      remoteStaffMap[data['mobile'] ?? ''] = data;
    }

    // Upload local staff not in Firestore (SKIP if downloadOnly)
    if (!downloadOnly) {
      for (var staff in localStaff) {
        if (staff['role'] != 'staff') continue;
        final mobile = staff['mobile'] as String?;
        if (mobile != null && !remoteStaffMap.containsKey(mobile)) {
          await _uploadStaff(staff);
          uploaded++;
        }
      }
    }

    // Download remote staff not in local
    for (var entry in remoteStaffMap.entries) {
      if (!localStaffMobiles.contains(entry.key)) {
        await _downloadStaff(entry.value, sqliteDairyId);
        downloaded++;
      }
    }

    return {'uploaded': uploaded, 'downloaded': downloaded};
  }

  Future<void> _uploadStaff(Map<String, dynamic> staff) async {
    final mobile = staff['mobile'] as String? ?? '';
    final password = staff['password'] as String? ?? '';

    // Create Firebase Auth account for this staff via secondary app
    String? staffAuthUid;
    if (mobile.isNotEmpty && password.isNotEmpty) {
      try {
        final secondaryAuth = await _getSecondaryAuth();
        final ghostEmail = _staffGhostEmail(mobile);
        final staffCred = await secondaryAuth.createUserWithEmailAndPassword(
          email: ghostEmail,
          password: password,
        );
        staffAuthUid = staffCred.user?.uid;
        await secondaryAuth.signOut();
      } catch (e) {
        debugPrint('[_uploadStaff] Firebase Auth creation failed: $e');
      }
    }

    // Create staff document in Firestore
    final docRef = await _firestore.collection('staff').add({
      'name': staff['name'],
      'mobile': mobile,
      'username': mobile,
      'password': password,
      'role': 'staff',
      'dairyId': dairyId,
      'createdAt': FieldValue.serverTimestamp(),
      'isActive': staff['isActive'] ?? true,
      'firebaseAuthUid': staffAuthUid,
    });

    // Create public lookup entry for staff
    await _firestore.collection('public_lookups')
        .doc('staff_mobile_$mobile')
        .set({
      'staffId': docRef.id,
      'dairyId': dairyId,
      'name': staff['name'],
      'mobile': mobile,
      'role': 'staff',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Add to _members so Firestore rules pass for this staff
    if (staffAuthUid != null) {
      try {
        await _firestore.collection('_members').doc(dairyId).update({
          'uids': FieldValue.arrayUnion([staffAuthUid]),
        });
      } catch (e) {
        try {
          await _firestore.collection('_members').doc(dairyId).set({
            'uids': [dairyId!, staffAuthUid],
          });
        } catch (_) {}
      }
    }
  }

  Future<void> _downloadStaff(
    Map<String, dynamic> data,
    int? sqliteDairyId,
  ) async {
    await _db.createUser(
      name: data['name'] ?? '',
      mobile: data['mobile'] ?? '',
      password: data['password'] ?? '1234', // Default password
      role: 'staff',
      dairyId: sqliteDairyId,
    );
  }

  // =============================================
  // SINGLE ITEM OPERATIONS
  // =============================================

  /// Add farmer to both local and Firestore
  Future<void> addFarmerWithSync(Farmer farmer, int? sqliteDairyId) async {
    // Add to local database
    farmer.dairyId = sqliteDairyId;
    await _db.insertFarmer(farmer);

    // Add to Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      await _uploadFarmer(farmer);
    }
  }

  /// Update pending entry status
  Future<void> updatePendingEntry({
    required String farmerCode,
    required String dateTime,
    required String shift,
    required double fat,
    required double snf,
    required double rate,
    required double amount,
  }) async {
    // Update in Firestore
    if (isAuthenticated && dairyId != null) {
      final query = await _firestore
          .collection('milkEntries')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: farmerCode)
          .where('dateTime', isEqualTo: dateTime)
          .where('shift', isEqualTo: shift)
          .get();

      for (var doc in query.docs) {
        await doc.reference.update({
          'fat': fat,
          'snf': snf,
          'rate': rate,
          'amount': amount,
          'totalAmount': amount,
          'isPending': false,
          'status': 'COMPLETED',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  /// Update farmer in both local and Firestore
  Future<void> updateFarmerWithSync(Farmer farmer, int? sqliteDairyId) async {
    // Update in local database
    farmer.dairyId = sqliteDairyId;
    await _db.updateFarmer(farmer);

    // Update in Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      // Find existing farmer document
      final query = await _firestore
          .collection('farmers')
          .where('dairyId', isEqualTo: dairyId)
          .where('code', isEqualTo: farmer.code)
          .get();

      if (query.docs.isNotEmpty) {
        await _updateFirestoreFarmer(query.docs.first.id, farmer);
      } else {
        // Farmer doesn't exist in Firestore, create it
        await _uploadFarmer(farmer);
      }
    }
  }

  /// Add payment to both local and Firestore
  Future<void> addPaymentWithSync(Payment payment, int? sqliteDairyId) async {
    // Add to local database
    payment.dairyId = sqliteDairyId;
    await _db.insertPayment(payment);

    // Add to Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      await _uploadPayment(payment);
    }
  }

  // =============================================
  // FIREBASE-FIRST PAYMENT METHODS (Financial Safety)
  // =============================================

  /// Fetch ALL payments directly from Firestore (source of truth).
  /// Used by payment screen to avoid local SQLite staleness.
  Future<List<Payment>> fetchPaymentsFromFirestore(int? sqliteDairyId) async {
    if (!isAuthenticated || dairyId == null) {
      // Fallback to local only when not authenticated
      return _db.getPayments(dairyId: sqliteDairyId);
    }

    final snapshot = await _firestore
        .collection('payments')
        .where('dairyId', isEqualTo: dairyId)
        .get();

    final List<Payment> payments = [];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final farmerCode = data['farmerCode'] as String?;
      if (farmerCode == null || farmerCode.isEmpty) continue;

      // Resolve local farmer ID from code
      final farmer = await _db.getFarmerByCode(farmerCode, dairyId: sqliteDairyId);
      if (farmer == null) continue;

      // Parse dates safely
      DateTime parseDate(dynamic val, {DateTime? fallback}) {
        if (val == null) return fallback ?? DateTime.now();
        if (val is Timestamp) return val.toDate();
        if (val is DateTime) return val;
        if (val is String) {
          try { return DateTime.parse(val); } catch (_) {}
        }
        return fallback ?? DateTime.now();
      }

      final paymentDate = parseDate(data['date'] ?? data['paymentDate']);
      final fromDate = parseDate(data['fromDate'], fallback: paymentDate);
      final toDate = parseDate(data['toDate'], fallback: paymentDate);
      final type = (data['type'] ?? 'PAYMENT') as String;
      final netAmt = (data['netAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0;
      final totalAmt = (data['totalAmount'] as num?)?.toDouble() ?? netAmt;

      payments.add(Payment(
        farmerId: farmer.id!,
        farmerCode: farmerCode,
        farmerName: data['farmerName'] ?? farmer.name,
        paymentDate: paymentDate,
        fromDate: fromDate,
        toDate: toDate,
        type: type,
        amount: totalAmt,
        advanceDeduction: (data['advanceDeduction'] as num?)?.toDouble() ?? 0,
        netAmount: netAmt,
        totalLiters: (data['totalLiters'] as num?)?.toDouble() ?? 0,
        paymentMode: (data['paymentMode'] ?? 'cash') as String,
        transactionId: data['transactionId'] as String?,
        notes: data['notes'] ?? data['remarks'],
        isPaid: data['isPaid'] == true,
        dairyId: sqliteDairyId,
        syncId: data['syncId'] as String?,
      ));
    }

    // Also update local cache for offline fallback
    _refreshLocalPaymentCache(payments, sqliteDairyId);

    return payments;
  }

  /// Write payment to Firestore FIRST, then cache locally only on success.
  /// Throws on network failure — caller must handle.
  Future<void> addPaymentFirestoreFirst(Payment payment, int? sqliteDairyId) async {
    payment.dairyId = sqliteDairyId;

    if (!isAuthenticated || dairyId == null) {
      throw Exception('Not authenticated — cannot save payment securely');
    }

    // FIREBASE FIRST — single source of truth
    await _uploadPayment(payment);

    // Only cache locally AFTER Firebase write succeeds
    await _db.insertPayment(payment);
  }

  /// Mark unpaid advances as paid — Firestore FIRST, then local cache.
  /// Uses Firestore batch write for atomicity.
  Future<void> markAdvancesPaidFirestoreFirst(
    int farmerId,
    String farmerCode,
    int? sqliteDairyId,
  ) async {
    if (!isAuthenticated || dairyId == null) {
      throw Exception('Not authenticated — cannot update advances securely');
    }

    // FIREBASE FIRST: query + batch update for atomicity
    final query = await _firestore
        .collection('payments')
        .where('dairyId', isEqualTo: dairyId)
        .where('farmerCode', isEqualTo: farmerCode)
        .where('type', isEqualTo: 'ADVANCE')
        .where('isPaid', isEqualTo: false)
        .get();

    if (query.docs.isNotEmpty) {
      final batch = _firestore.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {
          'isPaid': true,
          'paidAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit(); // Atomic — all or nothing
    }

    // Only update local AFTER Firestore succeeds
    await _db.markAdvancesPaid(farmerId);
    try {
      final db = await _db.database;
      await db.update(
        'payments',
        {'isPaid': 1},
        where: 'farmerId = ? AND type = ? AND (isPaid = 0 OR isPaid IS NULL)',
        whereArgs: [farmerId, 'ADVANCE'],
      );
    } catch (_) {}
  }

  /// Delete payment from Firestore FIRST, then remove local cache.
  Future<void> deletePaymentFirestoreFirst(Payment payment, int? sqliteDairyId) async {
    if (!isAuthenticated || dairyId == null) {
      throw Exception('Not authenticated — cannot delete payment securely');
    }

    // Delete from Firestore first — match by syncId for precision
    bool deleted = false;
    if (payment.syncId.isNotEmpty) {
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('syncId', isEqualTo: payment.syncId)
          .get();
      for (var doc in query.docs) {
        await doc.reference.delete();
        deleted = true;
      }
    }

    // Fallback to date+code match if syncId not found
    if (!deleted) {
      final dt = payment.paymentDate;
      final dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: payment.farmerCode)
          .where('type', isEqualTo: payment.type)
          .get();
      for (var doc in query.docs) {
        final data = doc.data();
        String remoteDate = '';
        final dateVal = data['date'] ?? data['paymentDate'];
        if (dateVal is Timestamp) {
          final rdt = dateVal.toDate();
          remoteDate = '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (dateVal is String) {
          remoteDate = dateVal.split('T')[0];
        }
        if (remoteDate == dateStr) {
          await doc.reference.delete();
          break;
        }
      }
    }

    // Only remove local cache after Firestore succeeds
    if (payment.id != null) {
      await _db.deletePayment(payment.id!);
    }
  }

  /// Update payment on Firestore FIRST, then update local cache.
  Future<void> updatePaymentFirestoreFirst(Payment payment, int? sqliteDairyId) async {
    payment.dairyId = sqliteDairyId;

    if (!isAuthenticated || dairyId == null) {
      throw Exception('Not authenticated — cannot update payment securely');
    }

    // Find the Firestore doc — prefer syncId match
    DocumentReference? targetRef;
    if (payment.syncId.isNotEmpty) {
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('syncId', isEqualTo: payment.syncId)
          .get();
      if (query.docs.isNotEmpty) {
        targetRef = query.docs.first.reference;
      }
    }

    // Fallback to date+code match
    if (targetRef == null) {
      final dt = payment.paymentDate;
      final dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: payment.farmerCode)
          .where('type', isEqualTo: payment.type)
          .get();
      for (var doc in query.docs) {
        final data = doc.data();
        String remoteDate = '';
        final dateVal = data['date'] ?? data['paymentDate'];
        if (dateVal is Timestamp) {
          final rdt = dateVal.toDate();
          remoteDate = '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (dateVal is String) {
          remoteDate = dateVal.split('T')[0];
        }
        if (remoteDate == dateStr) {
          targetRef = doc.reference;
          break;
        }
      }
    }

    if (targetRef != null) {
      await targetRef.update({
        'amount': payment.netAmount,
        'totalAmount': payment.amount,
        'advanceDeduction': payment.advanceDeduction,
        'netAmount': payment.netAmount,
        'notes': payment.notes,
        'isPaid': payment.isPaid == true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Only update local after Firestore succeeds
    await _db.updatePayment(payment);
  }

  /// Refresh local payment cache from Firestore-fetched data (for offline fallback).
  /// Replaces all local payments for this dairy with the Firestore snapshot.
  Future<void> _refreshLocalPaymentCache(List<Payment> firestorePayments, int? sqliteDairyId) async {
    try {
      final db = await _db.database;
      // Clear existing local payments for this dairy
      await db.delete('payments', where: 'dairyId = ?', whereArgs: [sqliteDairyId]);
      // Re-insert all from the Firestore snapshot
      for (var payment in firestorePayments) {
        await db.insert('payments', payment.toMap());
      }
    } catch (_) {}
  }

  /// Add advance to both local and Firestore
  Future<void> addAdvanceWithSync(Advance advance, int? sqliteDairyId) async {
    // Add to local database
    advance.dairyId = sqliteDairyId;
    await _db.insertAdvance(advance);

    // Add to Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      await _firestore.collection('payments').add({
        'syncId': const Uuid().v4(),
        'farmerId': advance.farmerCode,
        'farmerCode': advance.farmerCode,
        'farmerName': advance.farmerName,
        'date': advance.date.toIso8601String(),
        'type': 'ADVANCE',
        'amount': advance.amount,
        'netAmount': advance.amount,
        'remarks': advance.remarks,
        'isPaid': advance.isPaid,
        'dairyId': dairyId,
        'timestamp': advance.date.millisecondsSinceEpoch,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Delete farmer from both local and Firestore (cascading: also deletes associated milk entries and payments)
  Future<void> deleteFarmerWithSync(Farmer farmer, int? sqliteDairyId) async {
    // Delete associated milk entries and payments from local database
    if (farmer.id != null) {
      final db = await _db.database;
      await db.delete('milk_entries', where: 'farmerId = ?', whereArgs: [farmer.id]);
      await db.delete('payments', where: 'farmerId = ?', whereArgs: [farmer.id]);
      try { await db.delete('advances', where: 'farmerId = ?', whereArgs: [farmer.id]); } catch (_) {}
      await _db.deleteFarmer(farmer.id!);
    }

    // Delete from Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      // Delete farmer's milk entries from Firestore
      try {
        final entriesQuery = await _firestore
            .collection('milk_entries')
            .where('dairyId', isEqualTo: dairyId)
            .where('farmerCode', isEqualTo: farmer.code)
            .get();
        for (var doc in entriesQuery.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
      }

      // Delete farmer's payments from Firestore
      try {
        final paymentsQuery = await _firestore
            .collection('payments')
            .where('dairyId', isEqualTo: dairyId)
            .where('farmerCode', isEqualTo: farmer.code)
            .get();
        for (var doc in paymentsQuery.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
      }

      // Delete farmer document from Firestore
      final query = await _firestore
          .collection('farmers')
          .where('dairyId', isEqualTo: dairyId)
          .where('code', isEqualTo: farmer.code)
          .get();

      for (var doc in query.docs) {
        await doc.reference.delete();
      }
    }
  }

  /// Add milk entry to both local and Firestore
  Future<int> addMilkEntryWithSync(MilkEntry entry, int? sqliteDairyId) async {
    // Add to local database
    entry.dairyId = sqliteDairyId;
    final localId = await _db.insertMilkEntry(entry);

    // Add to Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      await _uploadMilkEntry(entry);
    }

    return localId;
  }

  /// Update milk entry in both local and Firestore
  Future<void> updateMilkEntryWithSync(
    MilkEntry entry,
    int? sqliteDairyId,
  ) async {
    // Update in local database
    entry.dairyId = sqliteDairyId;
    await _db.updateMilkEntry(entry);

    // Update in Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      // Find existing entry document by matching key fields
      final date =
          '${entry.dateTime.year}-${entry.dateTime.month.toString().padLeft(2, '0')}-${entry.dateTime.day.toString().padLeft(2, '0')}';

      final query = await _firestore
          .collection('milkEntries')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: entry.farmerCode)
          .where('date', isEqualTo: date)
          .where('shift', isEqualTo: entry.shift)
          .where('cattleType', isEqualTo: entry.cattleType)
          .get();

      if (query.docs.isNotEmpty) {
        // Update existing document
        await query.docs.first.reference.update({
          'quantity': entry.quantity,
          'fat': entry.fat,
          'snf': entry.snf ?? 0,
          'rate': entry.rate,
          'amount': entry.amount,
          'totalAmount': entry.amount,
          'isPending': entry.isPending,
          'status': entry.isPending ? 'PENDING' : 'COMPLETED',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Entry doesn't exist in Firebase, upload it
        await _uploadMilkEntry(entry);
      }
    }
  }

  /// Delete milk entry from both local and Firestore
  Future<void> deleteMilkEntryWithSync(
    MilkEntry entry,
    int? sqliteDairyId,
  ) async {
    // Delete from local database
    if (entry.id != null) {
      await _db.deleteMilkEntry(entry.id!);
    }

    // Delete from Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      final date =
          '${entry.dateTime.year}-${entry.dateTime.month.toString().padLeft(2, '0')}-${entry.dateTime.day.toString().padLeft(2, '0')}';

      final query = await _firestore
          .collection('milkEntries')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: entry.farmerCode)
          .where('date', isEqualTo: date)
          .where('shift', isEqualTo: entry.shift)
          .where('cattleType', isEqualTo: entry.cattleType)
          .get();

      if (query.docs.isNotEmpty) {
        await query.docs.first.reference.delete();
      }
    }
  }

  /// Update payment in both local and Firestore
  Future<void> updatePaymentWithSync(Payment payment, int? sqliteDairyId) async {
    // Update in local database
    payment.dairyId = sqliteDairyId;
    await _db.updatePayment(payment);

    // Update in Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      final dt = payment.paymentDate;
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: payment.farmerCode)
          .where('type', isEqualTo: payment.type)
          .get();

      for (var doc in query.docs) {
        final data = doc.data();
        String remoteDate = '';
        if (data['date'] is Timestamp) {
          final rdt = (data['date'] as Timestamp).toDate();
          remoteDate = '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (data['paymentDate'] is Timestamp) {
          final rdt = (data['paymentDate'] as Timestamp).toDate();
          remoteDate = '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (data['date'] is String) {
          remoteDate = (data['date'] as String).split('T')[0];
        }

        if (remoteDate == dateStr) {
          await doc.reference.update({
            'amount': payment.amount,
            'totalAmount': payment.amount,
            'advanceDeduction': payment.advanceDeduction,
            'netAmount': payment.netAmount,
            'notes': payment.notes,
            'isPaid': payment.isPaid == true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          break; // Only update the first match
        }
      }
    }
  }

  /// Delete payment from both local and Firestore
  Future<void> deletePaymentWithSync(
    Payment payment,
    int? sqliteDairyId,
  ) async {
    // NOTE: Advance Reversal removed because it incorrectly un-pays ALL past advances.
    // It is safer to let the user manually mark advances as unpaid in History if needed.

    // Delete from local database
    if (payment.id != null) {
      await _db.deletePayment(payment.id!);
    }

    // Delete from Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      // Extract date string for matching
      final dt = payment.paymentDate;
      final dateStr =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    
      // Filter by type to avoid deleting wrong records (PAYMENT vs ADVANCE)
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: payment.farmerCode)
          .where('type', isEqualTo: payment.type)
          .get();

      bool deleted = false;
      for (var doc in query.docs) {
        final data = doc.data();
        // Match by date
        String remoteDate = '';
        if (data['date'] is Timestamp) {
          final rdt = (data['date'] as Timestamp).toDate();
          remoteDate =
              '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (data['paymentDate'] is Timestamp) {
          final rdt = (data['paymentDate'] as Timestamp).toDate();
          remoteDate =
              '${rdt.year}-${rdt.month.toString().padLeft(2, '0')}-${rdt.day.toString().padLeft(2, '0')}';
        } else if (data['date'] is String) {
          remoteDate = (data['date'] as String).split('T')[0];
        }

        if (remoteDate == dateStr && !deleted) {
          await doc.reference.delete();
          deleted = true; // Only delete the first match
        }
      }
    }
  }

  /// Mark advances as paid in both local and Firestore
  Future<void> markAdvancesPaidWithSync(
    int farmerId,
    String farmerCode,
    int? sqliteDairyId,
  ) async {
    // Update in local 'advances' table (legacy)
    await _db.markAdvancesPaid(farmerId);

    // Also update in local 'payments' table (where UI reads advances from)
    try {
      final db = await _db.database;
      await db.update(
        'payments',
        {'isPaid': 1},
        where: 'farmerId = ? AND type = ? AND (isPaid = 0 OR isPaid IS NULL)',
        whereArgs: [farmerId, 'ADVANCE'],
      );
    } catch (_) {}

    // Update in Firestore if authenticated
    if (isAuthenticated && dairyId != null) {
      final query = await _firestore
          .collection('payments')
          .where('dairyId', isEqualTo: dairyId)
          .where('farmerCode', isEqualTo: farmerCode)
          .where('type', isEqualTo: 'ADVANCE')
          .where('isPaid', isEqualTo: false)
          .get();

      for (var doc in query.docs) {
        await doc.reference.update({
          'isPaid': true,
          'paidAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // =============================================
  // REAL-TIME SYNC LISTENERS
  // =============================================

  /// Start real-time listeners for all collections
  Future<void> startRealtimeSync(int? sqliteDairyId) async {
    if (_isListening || _isLoggingOut || !isAuthenticated || dairyId == null) return;

    _isListening = true;

    // Listen to farmers collection
    _farmersListener = _firestore
        .collection('farmers')
        .where('dairyId', isEqualTo: dairyId)
        .snapshots()
        .listen(
          (snapshot) async {
            await _handleFarmersChanges(snapshot, sqliteDairyId);
          },
          onError: (e) {
            debugPrint('[RealtimeSync] farmers listener error: $e');
          },
        );

    // Listen to milk entries collection
    _milkEntriesListener = _firestore
        .collection('milkEntries')
        .where('dairyId', isEqualTo: dairyId)
        .snapshots()
        .listen(
          (snapshot) async {
            await _handleMilkEntriesChanges(snapshot, sqliteDairyId);
          },
          onError: (e) {
            debugPrint('[RealtimeSync] milkEntries listener error: $e');
          },
        );

    // Listen to payments collection
    _paymentsListener = _firestore
        .collection('payments')
        .where('dairyId', isEqualTo: dairyId)
        .snapshots()
        .listen(
          (snapshot) async {
            await _handlePaymentsChanges(snapshot, sqliteDairyId);
          },
          onError: (e) {
            debugPrint('[RealtimeSync] payments listener error: $e');
          },
        );

    // Listen to rate settings changes (dairy_settings document)
    _rateSettingsListener = _firestore
        .collection('dairy_settings')
        .doc(dairyId)
        .snapshots()
        .listen(
          (snapshot) async {
            await _handleRateSettingsChange(snapshot);
          },
          onError: (e) {
            debugPrint('[RealtimeSync] dairy_settings listener error: $e');
          },
        );
  }

  /// Stop real-time listeners
  void stopRealtimeSync() {
    _farmersListener?.cancel();
    _milkEntriesListener?.cancel();
    _paymentsListener?.cancel();
    _rateSettingsListener?.cancel();
    _farmersListener = null;
    _milkEntriesListener = null;
    _paymentsListener = null;
    _rateSettingsListener = null;
    _isListening = false;
  }

  /// Handle farmer changes from Firestore
  Future<void> _handleFarmersChanges(
    QuerySnapshot snapshot,
    int? sqliteDairyId,
  ) async {
    for (var change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final code = data['code'] as String?;
      if (code == null || code.isEmpty) continue;

      if (change.type == DocumentChangeType.added ||
          change.type == DocumentChangeType.modified) {
        // Check if farmer exists locally
        final existingFarmer = await _db.getFarmerByCode(
          code,
          dairyId: sqliteDairyId,
        );

        if (existingFarmer == null) {
          // Add new farmer from Firestore
          await _downloadFarmer(data, sqliteDairyId);
          onDataChanged?.call();
        } else if (change.type == DocumentChangeType.modified) {
          // Update existing farmer
          final updatedFarmer = Farmer(
            id: existingFarmer.id,
            code: code,
            name: data['name'] ?? existingFarmer.name,
            fatherName: data['fatherName'],
            mobile: data['mobile'] ?? existingFarmer.mobile,
            cattleType:
                data['cattleType'] ??
                data['defaultCattleType'] ??
                existingFarmer.cattleType,
            useFixedRate: data['useFixedRate'] ?? existingFarmer.useFixedRate,
            fixedRate: (data['fixedRate'] as num?)?.toDouble(),
            cowFixedRate: (data['cowFixedRate'] as num?)?.toDouble() ?? existingFarmer.cowFixedRate,
            buffaloFixedRate: (data['buffaloFixedRate'] as num?)?.toDouble() ?? existingFarmer.buffaloFixedRate,
            currentBalance:
                (data['currentBalance'] as num?)?.toDouble() ??
                existingFarmer.currentBalance,
            isActive: data['isActive'] ?? existingFarmer.isActive,
            dairyId: sqliteDairyId,
          );
          await _db.updateFarmer(updatedFarmer);
          onDataChanged?.call();
        }
      } else if (change.type == DocumentChangeType.removed) {
        // Delete farmer locally
        final existingFarmer = await _db.getFarmerByCode(
          code,
          dairyId: sqliteDairyId,
        );
        if (existingFarmer != null && existingFarmer.id != null) {
          await _db.deleteFarmer(existingFarmer.id!);
          onDataChanged?.call();
        }
      }
    }
  }

  /// Handle milk entry changes from Firestore
  Future<void> _handleMilkEntriesChanges(
    QuerySnapshot snapshot,
    int? sqliteDairyId,
  ) async {
    for (var change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      if (change.type == DocumentChangeType.added) {
        // Support both APK format (farmerCode) and Website format (farmerId + farmerName)
        String? farmerCode = data['farmerCode'] as String?;
        final farmerName = data['farmerName'] as String?;

        // Website doesn't send farmerCode, so we need to find farmer by name
        if (farmerCode == null && farmerName != null) {
          // Try to find farmer by name in local database
          final farmer = await _db.getFarmerByName(
            farmerName,
            dairyId: sqliteDairyId,
          );
          if (farmer != null) {
            farmerCode = farmer.code;
          }
        }

        // Get dateTime - website only sends 'date', APK sends 'dateTime'
        String? dateTimeStr = data['dateTime'] as String?;
        if (dateTimeStr == null) {
          // Website format - construct from date + timestamp
          final date = data['date'] as String?;
          final timestamp = data['timestamp'] as int?;
          if (date != null && timestamp != null) {
            dateTimeStr = DateTime.fromMillisecondsSinceEpoch(
              timestamp,
            ).toIso8601String();
          } else if (date != null) {
            dateTimeStr = '${date}T12:00:00.000';
          }
        }

        final shift = data['shift'] as String?;

        if (farmerCode == null || dateTimeStr == null || shift == null) {
          continue;
        }

        // Check if entry exists locally using multiple methods (including cattleType)
        final exists = await _checkMilkEntryExistsFlexible(
          farmerCode,
          farmerName,
          dateTimeStr,
          data['date'] as String?,
          shift,
          data['timestamp'] as int?,
          sqliteDairyId,
          cattleType: data['cattleType'] as String?,
        );

        if (!exists) {
          await _downloadMilkEntryFlexible(data, farmerCode, sqliteDairyId);
          onDataChanged?.call();
        }
      } else if (change.type == DocumentChangeType.modified) {
        // Update existing milk entry from Firebase
        String? farmerCode = data['farmerCode'] as String?;
        final farmerName = data['farmerName'] as String?;
        final shift = data['shift'] as String?;
        final dateStr = data['date'] as String?;

        if (farmerCode == null && farmerName != null) {
          final farmer = await _db.getFarmerByName(
            farmerName,
            dairyId: sqliteDairyId,
          );
          if (farmer != null) farmerCode = farmer.code;
        }

        if (farmerCode != null && dateStr != null && shift != null) {
          // Find local entry by matching key fields (including cattleType)
          final cattleType = data['cattleType'] as String?;
          final entries = await _db.getMilkEntries(dairyId: sqliteDairyId);
          final localEntry = entries.where((e) {
            final localDate =
                '${e.dateTime.year}-${e.dateTime.month.toString().padLeft(2, '0')}-${e.dateTime.day.toString().padLeft(2, '0')}';
            return e.farmerCode == farmerCode &&
                localDate == dateStr &&
                e.shift == shift &&
                (cattleType == null || e.cattleType == cattleType);
          }).firstOrNull;

          if (localEntry != null) {
            final updatedEntry = MilkEntry(
              id: localEntry.id,
              farmerId: localEntry.farmerId, // Use LOCAL farmer ID, ignore cloud farmerId
              farmerCode: farmerCode,
              farmerName: data['farmerName'] ?? localEntry.farmerName,
              dateTime: localEntry.dateTime,
              shift: shift,
              quantity:
                  (data['quantity'] as num?)?.toDouble() ?? localEntry.quantity,
              fat: (data['fat'] as num?)?.toDouble() ?? localEntry.fat,
              snf: (data['snf'] as num?)?.toDouble(),
              rate: (data['rate'] as num?)?.toDouble() ?? localEntry.rate,
              amount:
                  (data['totalAmount'] as num?)?.toDouble() ??
                  (data['amount'] as num?)?.toDouble() ??
                  localEntry.amount,
              cattleType: data['cattleType'] ?? localEntry.cattleType,
              isPending: data['isPending'] ?? data['status'] == 'PENDING',
              syncId: data['syncId'] as String? ?? localEntry.syncId,
              createdByUserId:
                  (data['createdByUserId'] as num?)?.toInt() ??
                  localEntry.createdByUserId,
              createdByUserName:
                  data['createdByUserName'] ?? localEntry.createdByUserName,
              dairyId: sqliteDairyId,
            );
            await _db.updateMilkEntry(updatedEntry);
            onDataChanged?.call();
          }
        }
      } else if (change.type == DocumentChangeType.removed) {
        // Delete milk entry from local database
        String? farmerCode = data['farmerCode'] as String?;
        final farmerName = data['farmerName'] as String?;
        final shift = data['shift'] as String?;
        final dateStr = data['date'] as String?;

        if (farmerCode == null && farmerName != null) {
          final farmer = await _db.getFarmerByName(
            farmerName,
            dairyId: sqliteDairyId,
          );
          if (farmer != null) farmerCode = farmer.code;
        }

        if (farmerCode != null && dateStr != null && shift != null) {
          // Find and delete local entry (match by cattleType too)
          final cattleType = data['cattleType'] as String?;
          final entries = await _db.getMilkEntries(dairyId: sqliteDairyId);
          final localEntry = entries.where((e) {
            final localDate =
                '${e.dateTime.year}-${e.dateTime.month.toString().padLeft(2, '0')}-${e.dateTime.day.toString().padLeft(2, '0')}';
            return e.farmerCode == farmerCode &&
                localDate == dateStr &&
                e.shift == shift &&
                (cattleType == null || e.cattleType == cattleType);
          }).firstOrNull;

          if (localEntry != null && localEntry.id != null) {
            await _db.deleteMilkEntry(localEntry.id!);
            onDataChanged?.call();
          }
        }
      }
    }
  }

  /// Handle payment changes from Firestore
  Future<void> _handlePaymentsChanges(
    QuerySnapshot snapshot,
    int? sqliteDairyId,
  ) async {
    for (var change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final farmerCode = data['farmerCode'] as String?;
      // Handle both String and Timestamp date formats
      String? dateStr;
      final dateValue = data['date'] ?? data['paymentDate'];
      if (dateValue is Timestamp) {
        final dt = dateValue.toDate();
        dateStr =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } else if (dateValue is String) {
        dateStr = dateValue.split('T')[0];
      }
      final type = data['type'] as String?;
      final amount = (data['amount'] as num?)?.toDouble();

      if (farmerCode == null || dateStr == null) continue;

      if (change.type == DocumentChangeType.added) {
        // Check if payment exists locally
        final exists = await _checkPaymentExists(
          farmerCode,
          dateStr,
          type,
          sqliteDairyId,
        );

        if (!exists) {
          await _downloadPayment(data, sqliteDairyId);
          onDataChanged?.call();
        }
      } else if (change.type == DocumentChangeType.modified) {
        // Update existing payment from Firebase
        final payments = await _db.getPaymentsByFarmerCode(
          farmerCode,
          dairyId: sqliteDairyId,
        );
        final localPayment = payments.where((p) {
          String localDate;
          final dt = p.paymentDate;
          localDate =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                  return localDate == dateStr && p.type == type;
        }).firstOrNull;

        if (localPayment != null) {
          final updatedPayment = Payment(
            id: localPayment.id,
            farmerId: localPayment.farmerId, // Use LOCAL farmer ID, ignore cloud farmerId
            farmerCode: farmerCode,
            farmerName: data['farmerName'] ?? localPayment.farmerName,
            amount: (data['totalAmount'] as num?)?.toDouble() ?? amount ?? localPayment.amount,
            paymentDate: localPayment.paymentDate,
            type: type ?? localPayment.type,
            advanceDeduction:
                (data['advanceDeduction'] as num?)?.toDouble() ??
                localPayment.advanceDeduction,
            netAmount:
                (data['netAmount'] as num?)?.toDouble() ??
                localPayment.netAmount,
            totalLiters:
                (data['totalLiters'] as num?)?.toDouble() ??
                localPayment.totalLiters,
            notes: data['remarks'] ?? data['notes'] ?? localPayment.notes,
            isPaid: data['isPaid'] ?? localPayment.isPaid,
            dairyId: sqliteDairyId,
            syncId: data['syncId'] as String? ?? localPayment.syncId,
          );
          await _db.updatePayment(updatedPayment);
          onDataChanged?.call();
        }
      } else if (change.type == DocumentChangeType.removed) {
        // Delete payment from local database
        final payments = await _db.getPaymentsByFarmerCode(
          farmerCode,
          dairyId: sqliteDairyId,
        );
        final localPayment = payments.where((p) {
          String localDate;
          final dt = p.paymentDate;
          localDate =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                  return localDate == dateStr && p.type == type;
        }).firstOrNull;

        if (localPayment != null && localPayment.id != null) {
          await _db.deletePayment(localPayment.id!);
          onDataChanged?.call();
        }
      }
    }
  }

  /// Handle rate settings changes from Firestore (real-time listener)
  /// Updates SharedPreferences when admin changes rates from website or another device
  Future<void> _handleRateSettingsChange(DocumentSnapshot snapshot) async {
    if (!snapshot.exists) return;

    try {
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) return;

      final prefs = await SharedPreferences.getInstance();

      // All rate setting keys and their defaults
      final rateKeys = {
        'buffaloPerKgFatRate': 820.0,
        'cowEfuRate': 382.69,
        'cowDefaultSnf': 8.5,
        'buffaloSnf88to89Deduction': 2.0,
        'buffaloSnf85to87Deduction': 4.0,
        'buffaloSnf84Penalty': 75.0,
        'buffaloLowQualityPenalty': 75.0,
        'cowSnf83to84Deduction': 2.0,
        'cowSnf81to82Deduction': 4.0,
        'cowHighFatDeduction': 15.0,
        'cowSnf80Penalty': 75.0,
        'cowLowFatPenalty': 50.0,
      };

      bool changed = false;
      for (final entry in rateKeys.entries) {
        final remoteValue = (data[entry.key] as num?)?.toDouble();
        if (remoteValue != null) {
          final localValue = prefs.getDouble(entry.key);
          if (localValue != remoteValue) {
            await prefs.setDouble(entry.key, remoteValue);
            changed = true;
          }
        }
      }

      if (changed) {
        print('📊 Rate settings updated from Firestore');
        onDataChanged?.call();
      }
    } catch (e) {
      print('⚠️ Error handling rate settings change: $e');
    }
  }

  /// Flexible check for milk entry - supports both APK and Website formats
  Future<bool> _checkMilkEntryExistsFlexible(
    String farmerCode,
    String? farmerName,
    String dateTimeStr,
    String? dateStr,
    String shift,
    int? timestamp,
    int? dairyId, {
    String? cattleType,
  }) async {
    try {
      final entries = await _db.getMilkEntries(dairyId: dairyId);

      // Parse the date from dateTimeStr
      final entryDate = DateTime.tryParse(dateTimeStr);
      final dateOnly =
          dateStr ??
          (entryDate != null
              ? '${entryDate.year}-${entryDate.month.toString().padLeft(2, '0')}-${entryDate.day.toString().padLeft(2, '0')}'
              : null);

      return entries.any((e) {
        // Match by farmerCode or farmerName
        final farmerMatch =
            e.farmerCode == farmerCode ||
            (farmerName != null && e.farmerName == farmerName);

        // Match by date (ignore time)
        final localDate =
            '${e.dateTime.year}-${e.dateTime.month.toString().padLeft(2, '0')}-${e.dateTime.day.toString().padLeft(2, '0')}';
        final dateMatch = localDate == dateOnly;

        // Match by shift
        final shiftMatch = e.shift == shift;

        // Match by cattleType (cow/buffalo) — critical for multi-device consistency
        final cattleMatch = cattleType == null || e.cattleType == cattleType;

        return farmerMatch && dateMatch && shiftMatch && cattleMatch;
      });
    } catch (e) {
      return false;
    }
  }

  /// Download milk entry with flexible format support
  Future<void> _downloadMilkEntryFlexible(
    Map<String, dynamic> data,
    String farmerCode,
    int? sqliteDairyId,
  ) async {
    // IGNORE cloud farmerId — always use local lookup via farmerCode
    // Find farmer by code — use LOCAL farmer.id, not cloud farmerId
    final farmer = await _db.getFarmerByCode(
      farmerCode,
      dairyId: sqliteDairyId,
    );
    if (farmer == null) {
      return;
    }

    // Parse dateTime - support both formats
    DateTime dateTime;
    try {
      if (data['dateTime'] != null) {
        dateTime = DateTime.parse(data['dateTime']);
      } else if (data['timestamp'] != null) {
        dateTime = DateTime.fromMillisecondsSinceEpoch(
          data['timestamp'] as int,
        );
      } else if (data['date'] != null) {
        dateTime = DateTime.parse(data['date']);
      } else {
        dateTime = DateTime.now();
      }
    } catch (e) {
      dateTime = DateTime.now();
    }

    final entry = MilkEntry(
      farmerId: farmer.id!, // Always use LOCAL farmer ID, never cloud farmerId
      farmerCode: farmerCode,
      farmerName: data['farmerName'] ?? farmer.name,
      dateTime: dateTime,
      shift: data['shift'] ?? 'morning',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      fat: (data['fat'] as num?)?.toDouble() ?? 0,
      snf: (data['snf'] as num?)?.toDouble(),
      rate: (data['rate'] as num?)?.toDouble() ?? 0,
      amount: (data['totalAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0,
      cattleType: data['cattleType'] ?? 'cow',
      isPending: data['isPending'] ?? data['status'] == 'PENDING',
      isLabTested: data['isLabTested'] ?? true,
      collectorName: data['collectorName'],
      createdByUserId: (data['createdByUserId'] as num?)?.toInt(),
      createdByUserName: data['createdByUserName'],
      dairyId: sqliteDairyId,
      syncId: data['syncId'] as String?, // BUG FIX: Preserve syncId from Firestore to prevent duplicate uploads
    );

    await _db.insertMilkEntry(entry);
  }

  /// Check if payment exists in local database
  Future<bool> _checkPaymentExists(
    String farmerCode,
    String dateStr,
    String? type,
    int? dairyId,
  ) async {
    try {
      final payments = await _db.getPayments(dairyId: dairyId);

      // Extract just the date part (YYYY-MM-DD) for comparison
      String extractDateOnly(String str) {
        if (str.contains('T')) {
          return str.split('T')[0];
        }
        // Handle "2026-01-03" format
        if (str.length >= 10) {
          return str.substring(0, 10);
        }
        return str;
      }

      final remoteDateOnly = extractDateOnly(dateStr);

      return payments.any((p) {
        final localDateStr = p.paymentDate.toIso8601String();
        final localDateOnly = extractDateOnly(localDateStr);

        return p.farmerCode == farmerCode &&
            localDateOnly == remoteDateOnly &&
            (type == null || p.type == type);
      });
    } catch (e) {
      return false;
    }
  }

  /// Check if real-time sync is active
  bool get isRealtimeSyncActive => _isListening;
}
