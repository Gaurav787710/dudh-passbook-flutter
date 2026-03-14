# Dudh Passbook - Complete App Documentation

> **App Name:** Dudh Passbook (दूध पासबुक)  
> **Package:** com.dairymaster.pro  
> **Firebase Project:** my-diray-83de8  
> **Language:** Flutter/Dart  
> **Database:** SQLite (local, v10) + Cloud Firestore (cloud)  
> **Auth:** Firebase Auth (Ghost Email, Google Sign-In, Phone OTP)  
> **Auth Domain:** `@dudhpassbook.com` (ghost email — no real email exposed)  
> **Backup:** Google Drive + Local JSON  
> **Supported Languages:** Hindi (default), English  
> **Last Updated:** February 18, 2026  

---

## 📋 TABLE OF CONTENTS

1. [App Startup Flow](#1-app-startup-flow)
2. [Authentication System](#2-authentication-system)
   - [Signup (Account Create)](#21-signup-account-create---4-steps)
   - [Admin Login](#22-admin-login)
   - [Staff Login](#23-staff-login)
   - [Mobile OTP Login](#24-mobile-otp-login)
   - [Google Sign-In](#25-google-sign-in)
   - [Forgot Password](#26-forgot-password)
   - [Demo Mode](#27-demo-mode)
3. [Data Models (SQLite Tables)](#3-data-models-sqlite-tables)
4. [Firestore Collections (Cloud Database)](#4-firestore-collections-cloud-database)
5. [Firestore Security Rules](#5-firestore-security-rules)
6. [SharedPreferences (Local Settings)](#6-sharedpreferences-local-settings)
7. [Core Features - Screen by Screen](#7-core-features---screen-by-screen)
   - [Home Screen](#71-home-screen)
   - [Dashboard](#72-dashboard)
   - [Milk Entry](#73-milk-entry-main-feature)
   - [Farmers Management](#74-farmers-management)
   - [Payment Manager](#75-payment-manager)
   - [Billing & Bill Preview](#76-billing--bill-preview)
   - [Entry History](#77-entry-history)
   - [Reports & Export](#78-reports--export)
   - [Rate Chart](#79-rate-chart)
   - [Staff Management](#710-staff-management)
   - [Profile](#711-profile)
   - [Settings](#712-settings)
   - [Backup & Restore](#713-backup--restore)
8. [Rate Calculation Logic](#8-rate-calculation-logic)
9. [Sync System (App ↔ Cloud)](#9-sync-system-app--cloud)
   - [Full Sync](#91-full-sync)
   - [Realtime Sync (Listeners)](#92-realtime-sync-listeners)
   - [Individual Sync Methods](#93-individual-sync-methods)
   - [Dedup Keys](#94-dedup-keys)
10. [Auto Backup System](#10-auto-backup-system)
11. [Website Integration Guide](#11-website-integration-guide)
12. [Critical Bugs Fixed (Change Log)](#12-critical-bugs-fixed-change-log)
13. [Design Decisions & Trade-offs](#13-design-decisions--trade-offs)
14. [Files Modified (Complete List)](#14-files-modified-complete-list)
15. [Migration Notes for Existing Users](#15-migration-notes-for-existing-users)

---

## 1. App Startup Flow

```
App Launch
    │
    ▼
Firebase.initializeApp()
    │
    ▼
FirestoreSyncService.initialize()
    │
    ▼
WorkManager → Schedule daily auto-backup (midnight)
    │
    ▼
Read SharedPreferences
    │
    ├── language_selected == false → LanguageSelectionScreen → LoginScreen
    │
    ├── isLoggedIn == false → SplashScreen → LoginScreen
    │
    └── isLoggedIn == true → SplashScreen → HomeScreen
```

**SplashScreen:** 700ms animated logo screen → auto-navigates to next screen.

---

## 2. Authentication System

### 🔐 Security Architecture (Ghost Email Pattern)

The app uses a **Ghost Email** pattern — users never see or type real emails. Firebase Auth accounts are created with synthetic emails derived from mobile numbers:

| User Type | Ghost Email Format | Example |
|-----------|-------------------|---------|
| Admin | `{mobile}@dudhpassbook.com` | `9876543210@dudhpassbook.com` |
| Staff | `staff_{mobile}@dudhpassbook.com` | `staff_9876543210@dudhpassbook.com` |
| Google | Uses real Google email | `user@gmail.com` |

**Why Ghost Emails?**
- Users only know their mobile number + password — no email to remember
- Firebase Auth requires email/password, so we manufacture one from the mobile
- The domain `@dudhpassbook.com` is not a real mail server — it's just a Firebase Auth identifier
- No real email is ever exposed in `public_lookups`

**Key Helper Functions (in `firestore_sync_service.dart`):**
```dart
static String _adminGhostEmail(String mobile) => '$mobile@dudhpassbook.com';
static String _staffGhostEmail(String mobile) => 'staff_$mobile@dudhpassbook.com';
```

### 🔐 `_members` Collection (Access Control)

Firebase rules use a `_members/{dairyId}` document to track who can access a dairy's data:

```
📁 _members/{dairyId}
└── uids: [adminUid, staffUid1, staffUid2, ...]  // Array of Firebase UIDs
```

**Firestore Rule Function:**
```javascript
function isMember(dairyId) {
  return request.auth != null &&
    (request.auth.uid == dairyId ||       // Owner always passes (fallback)
     (exists(_members/dairyId) &&         // If _members doc exists...
      _members/dairyId.uids.hasAny([uid]) // ...check if UID is in array
     ));
}
```

**Owner Fallback:** If `uid == dairyId` (admin's UID IS the dairyId), access is granted WITHOUT needing `_members` doc. This ensures existing accounts that don't have a `_members` doc still work.

**Auto-Migration:** `_ensureMembersDoc()` is called on every login and fullSync. It creates the `_members` doc if it doesn't exist yet:
```dart
Future<void> _ensureMembersDoc() async {
  final doc = await _firestore.collection('_members').doc(dId).get();
  if (!doc.exists) {
    await _firestore.collection('_members').doc(dId).set({'uids': [user.uid]});
  }
}
```

---

### 2.1 Signup (Account Create) - 4 Steps

#### Step 1: Mobile Number
- User enters **10-digit mobile number** (India +91)
- App calls `Firebase Phone Auth → verifyPhoneNumber()`
- OTP sent via SMS
- If `isGoogleUser` (came from Google Sign-In), shows "Google Verified ✓" badge

#### Step 2: OTP Verification
- User enters **6-digit OTP**
- App calls `PhoneAuthProvider.credential(verificationId, otp)`
- **Duplicate check (Non-Google user):**
  - Signs in with phone credential temporarily
  - Checks if the Firebase Auth user already has `google.com` or `password` providers
  - If YES → shows "Account Already Exists" → redirect to login
  - If NO (phone-only temp user) → deletes temp user → proceeds
- **Duplicate check (Google user):**
  - Calls `findAccountByMobile(mobile)` to check if mobile is used by a DIFFERENT userId
  - If YES → shows error
- Stores `PhoneAuthCredential` for linking in Step 3

#### Step 3: Profile Details Form

| Field | Required | Notes |
|-------|----------|-------|
| Full Name | Yes | Locked if Google user |
| Email | Yes | Locked if Google user (stored in `users` doc, NOT used for auth) |
| Dairy Name | Yes | |
| Full Address | Yes | |
| City | Yes | |
| Pincode | Yes | 6 digits |
| Helpline Number | No | 10 digits |
| Tagline | No | |
| Password | Yes* | Hidden for Google users |
| Confirm Password | Yes* | Hidden for Google users |
| Terms & Conditions | Yes | Checkbox |

**On Submit — What Happens:**

**For Email/Password user (`registerAdmin()`):**
1. `Firebase Auth → createUserWithEmailAndPassword(ghostEmail, password)` where `ghostEmail = {mobile}@dudhpassbook.com`
2. Mobile uniqueness check across 3 Firestore collections (`public_lookups`, `dairies`, `users`)
3. If duplicate mobile found → deletes Auth user → returns error
4. Creates Firestore documents (see below)
5. Creates `_members/{uid}` doc with `uids: [uid]`
6. Links phone number: `user.linkWithCredential(phoneCredential)`

**For Google user (`registerAdminWithGoogle()`):**
1. Uses already-authenticated Google user (real Google email used for Firebase Auth)
2. Same mobile uniqueness check
3. Creates same Firestore documents with `authProvider: 'google'`
4. Creates `_members/{uid}` doc

**Firestore Documents Created on Signup:**

```
📁 users/{firebase_uid}
├── email: "user@example.com"          ← Real email (profile only, NOT used for auth)
├── name: "User Name"
├── dairyName: "My Dairy"
├── mobile: "9876543210"
├── address: "Full Address"
├── city: "City Name"
├── pincode: "123456"
├── managerMobile: "9876543211" (optional)
├── tagline: "Fresh Milk Daily" (optional)
├── signatureLabel: "" 
├── dairyId: "{firebase_uid}"
├── role: "admin"
├── authProvider: "email" | "google"
├── googlePhotoUrl: "..." (Google only)
├── createdAt: server_timestamp
└── isActive: true

📁 dairies/{firebase_uid}
├── email: "user@example.com"
├── name: "My Dairy" (= dairyName)
├── ownerName: "User Name"
├── ownerId: "{firebase_uid}"
├── mobile: "9876543210"
├── address, city, pincode, managerMobile, tagline, signatureLabel
└── createdAt: server_timestamp

📁 public_lookups/mobile_9876543210
├── userId: "{firebase_uid}"
├── name: "User Name"
└── createdAt: server_timestamp
⚠️ NO email, NO password stored here!

📁 public_lookups/user_{firebase_uid}
└── createdAt: server_timestamp
⚠️ NO email stored here!

📁 _members/{firebase_uid}
└── uids: ["{firebase_uid}"]           ← For Firestore rule access control
```

#### Step 4: Success
- Shows confirmation card → "Go to Login" button
- No data saved to SharedPreferences/SQLite during signup

---

### 2.2 Admin Login

**Input:** Mobile Number / Email / User ID + Password

**Flow (Ghost Email First, Legacy Fallback):**
```
User enters identifier + password
    │
    ▼
Is it a 10-digit mobile number?
    │
    ├─ YES → Try ghost email: signIn("{mobile}@dudhpassbook.com", password)
    │         │
    │         ├─ SUCCESS → Continue to user data lookup
    │         │
    │         └─ FAIL (user-not-found) → Legacy fallback:
    │              _findAdminEmailByMobileOrId(identifier)
    │              │  ├─ Check public_lookups/mobile_{identifier}
    │              │  ├─ Query dairies where mobile == identifier
    │              │  ├─ Query users where mobile == identifier
    │              │  └─ Try returned email with Firebase Auth
    │
    ├─ Contains '@' → Use as email directly → Firebase Auth sign-in
    │
    └─ Other → _findAdminEmailByMobileOrId() → Firebase Auth sign-in
    │
    ▼
Read Firestore users/{uid} (fallback: staff/{uid})
    │
    ▼
_dairyId = userData['dairyId'] ?? user.uid
    │
    ▼
_ensureMembersDoc()  ← Auto-creates _members doc if missing
    │
    ▼
Ensure public_lookups/mobile_{mobile} exists (merge)
    │
    ▼
Data Isolation Check:
    ├─ Read previousFirebaseDairyId from SharedPreferences
    ├─ If DIFFERENT user → resetDatabase() + clear prefs
    └─ If FIRST login → resetDatabase()
    │
    ▼
Save to SharedPreferences (see table below)
    │
    ▼
fullSync(localDairyId, isNewUser: isFirstLogin)
    │  ├─ _ensureMembersDoc()          ← Again at sync start
    │  ├─ Sync Farmers (Firestore ↔ SQLite)
    │  ├─ Sync Milk Entries - last 30 days (Firestore ↔ SQLite)
    │  ├─ Sync Payments (Firestore ↔ SQLite)
    │  ├─ Sync Staff (Firestore ↔ SQLite)
    │  └─ Sync Rate Settings (Firestore → SharedPreferences)
    │
    ▼
Navigate to HomeScreen
```

**SharedPreferences saved after login:**

| Key | Value | Example |
|-----|-------|---------|
| `isLoggedIn` | `true` | |
| `userRole` | `"admin"` or `"staff"` | `"admin"` |
| `userName` | Owner name | `"Gaurav"` |
| `userMobile` | Mobile number | `"9876543210"` |
| `userEmail` | Email | `"user@example.com"` |
| `firebaseDairyId` | Firebase UID (string) | `"abc123def456"` |
| `dairyId` | Integer (hashCode) | `12345678` |
| `userId` | Integer | Admin=`0`, Staff=hashCode |
| `dairyName` | Dairy name | `"My Dairy"` |
| `dairy_address` | Address | `"123 Main Street"` |
| `dairy_city` | City | `"Jaipur"` |
| `dairy_state` | State | `"Rajasthan"` |
| `dairy_pincode` | Pincode | `"302001"` |
| `dairy_contact` | Contact number | `"9876543210"` |
| `managerMobile` | Manager helpline | `"9876543211"` |
| `tagline` | Dairy tagline | `"Fresh Milk"` |
| `signatureLabel` | Signature label | `""` |
| `authProvider` | `"email"` / `"google"` / `"phone"` | `"email"` |
| `previousFirebaseDairyId` | Last logged-in Firebase UID | `"abc123def456"` |
| Rate settings (12 keys) | double values | See Rate Chart section |

---

### 2.3 Staff Login

**Staff now uses Firebase Auth (Ghost Email) with legacy plaintext fallback.**

**Flow:**
```
User enters mobile + password
    │
    ▼
STEP 1: Try Firebase Auth with ghost email
    │  signIn("staff_{mobile}@dudhpassbook.com", password)
    │
    ├─ SUCCESS → Find staff doc by firebaseAuthUid in 'staff' collection
    │            (fallback: find by mobile)
    │            → return staff data + save prefs + navigate
    │
    └─ FAIL (user-not-found) → Fall through to Step 2
    │
    ▼
STEP 2: Legacy fallback (old staff without Firebase Auth)
    │  Read public_lookups/staff_mobile_{input}
    │  OR public_lookups/staff_email_{input}
    │  Compare password with stored password (plaintext in old docs)
    │
    ├─ MATCH → return staff data
    └─ NO MATCH → "Staff account not found or wrong password"
    │
    ▼
Save to SharedPreferences + navigate to HomeScreen
Staff only sees: MilkEntry + EntryHistory (2 tabs instead of 5)
```

**Staff Firestore lookup documents (NEW — no password):**
```
📁 public_lookups/staff_mobile_{phone}
├── staffId: "auto_generated_doc_id"
├── dairyId: "{admin_firebase_uid}"
├── name: "Staff Name"
├── mobile: "9876543210"
├── role: "staff"
├── isActive: true
└── createdAt: server_timestamp
⚠️ NO password stored! Auth is via Firebase Auth ghost email.

📁 public_lookups/staff_email_{email}
└── (same fields as above + email)
```

**Legacy staff lookup docs may still have `password` field** — the app tries Firebase Auth first, and only falls back to plaintext check for old accounts that haven't been migrated.

---

### 2.4 Mobile OTP Login

**3-Step Flow:**

```
Step 1: Enter 10-digit mobile → Send OTP via Firebase Phone Auth
    │
Step 2: Enter 6-digit OTP → Verify → signInWithCredential(phoneCredential)
    │
Step 3: Auto-lookup user data using 6 cascading methods:
    ├─ 1. users/{uid}        → direct doc read
    ├─ 2. dairies/{uid}      → direct doc read
    ├─ 3. public_lookups/mobile_{phone} → get userId → users/{userId}
    ├─ 4. dairies where mobile == phone
    ├─ 5. users where mobile == phone
    └─ 6. users where mobile == '+91{phone}'
    │
    ▼
If NOT found → "Not registered" → redirect to SignupScreen
If found → Save prefs + fullSync + navigate to HomeScreen
```

---

### 2.5 Google Sign-In

```
GoogleSignIn().signIn() → get Google credentials
    │
    ▼
Firebase Auth → signInWithCredential(googleCredential)
    │
    ▼
Check Firestore users/{uid} exists?
    │
    ├─ YES → Normal login flow (save prefs + sync)
    │
    └─ NO (needsSetup: true) → Navigate to SignupScreen
       with prefillEmail, prefillName, isGoogleUser: true
       (user fills Dairy details only, email/name locked)
```

---

### 2.6 Forgot Password

**4-Step Modal Bottom Sheet:**

```
Step 1: Enter mobile number
    ├─ findAccountByMobile() → get associated email
    └─ Send OTP to mobile via Firebase Phone Auth

Step 2: Verify OTP

Step 3: Enter new password + confirm
    ├─ If same Firebase user (phone linked to this account):
    │   ├─ Has password provider → user.updatePassword()
    │   └─ No password provider → user.linkWithCredential(EmailAuth)
    │
    └─ If different user (phone created separate account):
        ├─ Try createUserWithEmailAndPassword (may link to Google)
        └─ Fallback: sendPasswordResetEmail()

Step 4: Success message
```

---

### 2.7 Demo Mode

- Inserts dummy data into SQLite
- No Firebase Auth, no Firestore
- Sets `isDemo: true` in SharedPreferences
- Full app access but no cloud sync

---

## 3. Data Models (SQLite Tables)

> **SQLite DB Version: 10** (migration adds `syncId` column to milk_entries)  
> **File:** `lib/database/database_helper.dart`

### `farmers` table
```sql
CREATE TABLE farmers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL,          -- Unique farmer code (e.g., "001", "002")
  name TEXT NOT NULL,          -- Farmer's name
  fatherName TEXT,             -- Father's name
  mobile TEXT NOT NULL,        -- 10-digit mobile
  cattleType TEXT NOT NULL,    -- "cow" or "buffalo"
  useFixedRate INTEGER NOT NULL, -- 0 or 1
  fixedRate REAL,              -- Fixed rate per liter (if useFixedRate=1)
  currentBalance REAL NOT NULL, -- Running balance
  createdAt TEXT NOT NULL,     -- ISO 8601 datetime
  isActive INTEGER NOT NULL,   -- 0 or 1
  dairyId INTEGER,             -- Links to admin's dairy
  UNIQUE(code, dairyId)        -- Code unique per dairy
);
```

### `milk_entries` table
```sql
CREATE TABLE milk_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  farmerId INTEGER NOT NULL,      -- FK to farmers.id
  farmerCode TEXT NOT NULL,       -- Farmer's code (denormalized)
  farmerName TEXT NOT NULL,       -- Farmer's name (denormalized)
  dateTime TEXT NOT NULL,         -- ISO 8601 datetime
  shift TEXT NOT NULL,            -- "morning" or "evening"
  quantity REAL NOT NULL,         -- Liters of milk
  fat REAL NOT NULL,              -- Fat percentage (e.g., 6.5)
  snf REAL,                       -- SNF percentage (e.g., 8.8)
  rate REAL NOT NULL,             -- Rate per liter (calculated)
  amount REAL NOT NULL,           -- Total amount = quantity × rate (rounded to 2 decimals)
  cattleType TEXT NOT NULL,       -- "cow" or "buffalo"
  collectorName TEXT,             -- Staff who collected
  isLabTested INTEGER NOT NULL,   -- 0 or 1
  isPending INTEGER DEFAULT 0,    -- 1 = Quick Entry (FAT/SNF pending)
  createdByUserId INTEGER,        -- Staff user ID who created
  createdByUserName TEXT,         -- Staff user name
  dairyId INTEGER,                -- Links to admin's dairy
  syncId TEXT                     -- UUID v4 for cloud sync dedup (added in DB v10)
);
```
> **`syncId`** is auto-generated in the `MilkEntry` constructor using `uuid.v4()`. It is the PRIMARY dedup key for cloud sync — if two entries have the same `syncId`, they are considered the same entry. Legacy entries without `syncId` fall back to the composite key `farmerCode+date+shift+quantity+fat`.

### `payments` table
```sql
CREATE TABLE payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  farmerId INTEGER NOT NULL,
  farmerCode TEXT NOT NULL,
  farmerName TEXT NOT NULL,
  paymentDate TEXT NOT NULL,       -- ISO 8601 datetime
  fromDate TEXT,                   -- Billing period start
  toDate TEXT,                     -- Billing period end
  type TEXT DEFAULT 'PAYMENT',     -- "PAYMENT" or "ADVANCE"
  totalAmount REAL NOT NULL,       -- Gross amount (milk total or advance amount)
  advanceDeduction REAL NOT NULL,  -- Advance deducted from this payment
  netAmount REAL NOT NULL,         -- Net payable = totalAmount - advanceDeduction
  totalLiters REAL NOT NULL,       -- Total liters in billing period
  paymentMode TEXT NOT NULL,       -- "cash", "upi", "bank"
  transactionId TEXT,              -- UPI/Bank reference
  notes TEXT,                      -- Remarks
  isPaid INTEGER DEFAULT 0,        -- For advances: 1 = already deducted in a bill
  dairyId INTEGER
);
```

> ⚠️ **CRITICAL DESIGN DECISION:** Both payments AND advances are stored in this SAME `payments` table. Advances are stored as `Payment(type: 'ADVANCE')`. The UI reads from this table and filters by `type`. The separate `advances` table exists but is NOT the source of truth for the UI — it's only used for legacy/secondary bookkeeping.

### `advances` table
```sql
CREATE TABLE advances (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  farmerId INTEGER NOT NULL,
  farmerCode TEXT NOT NULL,
  farmerName TEXT NOT NULL,
  date TEXT NOT NULL,              -- ISO 8601 datetime
  amount REAL NOT NULL,            -- Advance amount
  type TEXT NOT NULL,              -- "advance" or "loan"
  remarks TEXT,
  isPaid INTEGER NOT NULL,         -- 0 = unpaid, 1 = deducted from payment
  dairyId INTEGER
);
```

> ⚠️ **This table is secondary.** The app creates advances using `addPaymentWithSync()` which stores them in the `payments` table (type='ADVANCE'). The `advances` table may also receive a copy, but the **UI reads advances from the `payments` table** WHERE `type = 'ADVANCE'`.
>
> **`Advance.fromMap()` note:** Has `.toDouble()` on `amount` and null-safe defaults on `farmerCode`, `farmerName`, `type` to prevent crashes when DB returns int or null values.

### `rate_chart` table
```sql
CREATE TABLE rate_chart (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  cattleType TEXT NOT NULL,         -- "cow" or "buffalo"
  fatMin REAL NOT NULL,
  fatMax REAL NOT NULL,
  snfMin REAL NOT NULL,
  snfMax REAL NOT NULL,
  rate REAL NOT NULL,
  calculationType TEXT NOT NULL,    -- "fat_only", "fat_snf", "kg_fat_kg_snf"
  dairyId INTEGER
);
```

### `users` table (Staff/Admin)
```sql
CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  mobile TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  role TEXT NOT NULL,               -- "admin" or "staff"
  dairyName TEXT,
  dairyId INTEGER,
  username TEXT,                    -- Same as mobile
  fatherName TEXT,
  email TEXT,
  address TEXT,
  aadhar TEXT,                      -- Aadhaar number
  pan TEXT,                         -- PAN number
  bankAccount TEXT,
  ifsc TEXT,                        -- IFSC code
  createdAt TEXT NOT NULL,
  isActive INTEGER NOT NULL DEFAULT 1
);
```

---

## 4. Firestore Collections (Cloud Database)

### Collection: `users/{firebase_uid}`
| Field | Type | Description |
|-------|------|-------------|
| email | string | User's real email (profile display only, NOT used for auth) |
| name | string | Full name |
| dairyName | string | Dairy name |
| mobile | string | 10-digit mobile |
| address | string | Full address |
| city | string | City |
| pincode | string | 6-digit pincode |
| managerMobile | string | Helpline number (optional) |
| tagline | string | Dairy tagline (optional) |
| signatureLabel | string | Signature label (optional) |
| dairyId | string | Same as doc ID (firebase uid) |
| role | string | "admin" |
| authProvider | string | "email" / "google" |
| googlePhotoUrl | string | Google profile photo URL |
| createdAt | timestamp | Server timestamp |
| isActive | boolean | true/false |

### Collection: `dairies/{firebase_uid}`
| Field | Type | Description |
|-------|------|-------------|
| email | string | Owner's real email (for profile) |
| name | string | Dairy name |
| ownerName | string | Owner's name |
| ownerId | string | Firebase UID |
| mobile | string | Contact number |
| address | string | Full address |
| city | string | City |
| pincode | string | Pincode |
| managerMobile | string | Manager helpline |
| tagline | string | Tagline |
| signatureLabel | string | Signature label |
| createdAt | timestamp | Server timestamp |

### Collection: `_members/{dairyId}` ← NEW
| Field | Type | Description |
|-------|------|-------------|
| uids | array\<string\> | Firebase UIDs of admin + all staff who can access this dairy's data |

> This collection is used by Firestore security rules `isMember()` function. The admin UID is always in the array. Staff UIDs are added when staff is registered and removed when deleted.

### Collection: `public_lookups/{document_id}`

**Admin Mobile Lookup:** `public_lookups/mobile_{phone_number}`
| Field | Type | Description |
|-------|------|-------------|
| userId | string | Firebase UID |
| name | string | User name |
| createdAt | timestamp | |

> ⚠️ **NO `email` field, NO `password` field.** These were removed for security. Only `userId` and `name` are stored.

**Admin UID Lookup:** `public_lookups/user_{firebase_uid}`
| Field | Type | Description |
|-------|------|-------------|
| createdAt | timestamp | |

> ⚠️ **NO `email` field.** Removed for security.

**Staff Mobile Lookup:** `public_lookups/staff_mobile_{phone_number}`
| Field | Type | Description |
|-------|------|-------------|
| staffId | string | Staff doc ID in `staff` collection |
| dairyId | string | Admin's firebase UID |
| name | string | Staff name |
| mobile | string | Mobile number |
| role | string | "staff" |
| isActive | boolean | true/false |
| createdAt | timestamp | |

> ⚠️ **NO `password` field.** Staff auth is now via Firebase Auth ghost email. Old docs may still have `password` for legacy fallback.

**Staff Email Lookup:** `public_lookups/staff_email_{email}`
| Field | Type | Same as staff_mobile + `email` field |

### Collection: `farmers/{auto_id}`
| Field | Type | Description |
|-------|------|-------------|
| code | string | Farmer code (e.g., "001") |
| name | string | Farmer name |
| fatherName | string | Father's name |
| mobile | string | Mobile number |
| cattleType | string | "cow" / "buffalo" |
| defaultCattleType | string | Same as cattleType |
| useFixedRate | boolean | Fixed rate enabled |
| fixedRate | number | Fixed rate value |
| currentBalance | number | Running balance |
| dairyId | string | Admin's firebase UID |
| createdAt | string | ISO 8601 |
| updatedAt | string | ISO 8601 |
| isActive | boolean | true/false |
| serverId | string | Firestore doc ID |

### Collection: `milkEntries/{auto_id}`
| Field | Type | Description |
|-------|------|-------------|
| farmerId | number/string | Farmer's local ID or code |
| farmerCode | string | Farmer code |
| farmerName | string | Farmer name |
| date | string | YYYY-MM-DD |
| dateTime | string | ISO 8601 full datetime |
| shift | string | "morning" / "evening" |
| cattleType | string | "cow" / "buffalo" |
| quantity | number | Liters |
| fat | number | Fat % |
| snf | number | SNF % |
| rate | number | Rate per liter |
| amount | number | Total amount (rounded to 2 decimals) |
| totalAmount | number | Same as amount |
| isPending | boolean | Quick entry pending |
| status | string | "PENDING" / "COMPLETED" |
| isLabTested | boolean | Lab tested |
| collectorName | string | Collector staff name |
| createdByUserId | number | Creator staff ID |
| createdByUserName | string | Creator staff name |
| syncId | string | **UUID v4** — primary dedup key for sync |
| dairyId | string | Admin's firebase UID |
| timestamp | number | Milliseconds since epoch |
| createdAt | timestamp | Server timestamp |
| updatedAt | timestamp | **Server timestamp** — for future incremental sync |

### Collection: `payments/{auto_id}`
| Field | Type | Description |
|-------|------|-------------|
| farmerId | string | Farmer code |
| farmerCode | string | Farmer code |
| farmerName | string | Farmer name |
| date | string | ISO 8601 payment date |
| paymentDate | string | ISO 8601 (same as date) |
| type | string | "PAYMENT" / "ADVANCE" |
| amount | number | Net amount |
| fromDate | string | Billing period start (ISO 8601) |
| toDate | string | Billing period end (ISO 8601) |
| totalAmount | number | Gross amount |
| advanceDeduction | number | Advance deducted |
| netAmount | number | Net payable |
| totalLiters | number | Total liters |
| paymentMode | string | "cash" / "upi" / "bank" |
| transactionId | string | UPI/bank reference |
| notes | string | Remarks |
| remarks | string | Alternate remarks field |
| isPaid | boolean | For ADVANCE: deducted or not |
| dairyId | string | Admin's firebase UID |
| timestamp | number | Milliseconds epoch |
| createdAt | timestamp | Server timestamp |
| updatedAt | timestamp | **Server timestamp** — for future incremental sync |

### Collection: `advances/{auto_id}` (Legacy/Secondary)
| Field | Type | Description |
|-------|------|-------------|
| Same fields as payments | | |
| updatedAt | timestamp | **Server timestamp** |

> ⚠️ This collection exists but the **app primarily uses the `payments` collection** for both payments and advances. The `advances` collection may have copies for backward compatibility.

### Collection: `staff/{auto_id}`
| Field | Type | Description |
|-------|------|-------------|
| name | string | Staff name |
| mobile | string | Mobile number |
| password | string | Login password (stored in owner-only staff doc for admin management) |
| email | string | Email (optional) |
| fatherName | string | Father's name |
| address | string | Address |
| aadhar | string | Aadhaar number |
| pan | string | PAN number |
| bankAccount | string | Bank account number |
| ifsc | string | IFSC code |
| role | string | "staff" |
| dairyId | string | Admin's firebase UID |
| **firebaseAuthUid** | **string** | **Firebase Auth UID of the staff's ghost email account** |
| createdAt | timestamp | |
| isActive | boolean | |

> **`firebaseAuthUid`** is the UID of the Firebase Auth account created via secondary app with ghost email `staff_{mobile}@dudhpassbook.com`. This UID is also added to `_members/{dairyId}.uids` array so Firestore rules grant access. The password is kept in the `staff` doc (readable only by the dairy owner) so the admin can manage staff accounts.

### Collection: `dairy_settings/{firebase_uid}`
| Field | Type | Description |
|-------|------|-------------|
| buffaloPerKgFatRate | number | Buffalo rate per kg fat (default: 820) |
| cowEfuRate | number | Cow EFU rate (default: 382.69) |
| cowDefaultSnf | number | Default cow SNF (default: 8.5) |
| buffaloSnf88to89Deduction | number | % deduction (default: 2) |
| buffaloSnf85to87Deduction | number | % deduction (default: 4) |
| buffaloSnf84Penalty | number | % penalty (default: 75) |
| buffaloLowQualityPenalty | number | % penalty (default: 75) |
| cowSnf83to84Deduction | number | % deduction (default: 2) |
| cowSnf81to82Deduction | number | % deduction (default: 4) |
| cowHighFatDeduction | number | % deduction (default: 15) |
| cowSnf80Penalty | number | % penalty (default: 75) |
| cowLowFatPenalty | number | % penalty (default: 50) |
| updatedAt | timestamp | Last updated |

---

## 5. Firestore Security Rules

> **File:** `firestore.rules` — Deployed via `firebase deploy --only firestore:rules`

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ═══════════════════════════════════════════
    // HELPER: Check if user is a member of dairy
    // Admin (uid == dairyId) ALWAYS passes — no _members doc needed
    // Staff passes if their UID is in _members/{dairyId}.uids array
    // ═══════════════════════════════════════════
    function isMember(dairyId) {
      return request.auth != null &&
        (request.auth.uid == dairyId ||
         (exists(/databases/$(database)/documents/_members/$(dairyId)) &&
          get(/databases/$(database)/documents/_members/$(dairyId)).data.uids.hasAny([request.auth.uid])));
    }

    // Users: Any authenticated → read, owner → write
    users/{userId}:
      read: auth != null
      write: auth.uid == userId

    // Dairies: PUBLIC read (login lookup), owner → write
    dairies/{dairyId}:
      read: true  // PUBLIC — for mobile→email lookup during login
      write: auth.uid == dairyId

    // Public Lookups: PUBLIC read, any authenticated → write
    // ⚠️ No passwords stored here anymore
    public_lookups/{document}:
      read: true
      write: auth != null

    // _members: Any authenticated → read, dairy owner → write
    _members/{dairyId}:
      read: auth != null
      write: auth.uid == dairyId

    // Staff: Owner can CRUD, staff can read own doc via firebaseAuthUid
    staff/{staffId}:
      create: auth != null && resource.data.dairyId == auth.uid
      read: auth != null && (resource.data.dairyId == auth.uid || resource.data.firebaseAuthUid == auth.uid)
      update, delete: auth != null && resource.data.dairyId == auth.uid

    // Farmers, milkEntries, payments, advances, rateCharts:
    // → isMember(dairyId) check for create/update/delete
    // → any authenticated user can read (for sync)
    {collection}/{docId}:
      read: auth != null
      create: auth != null && isMember(request.resource.data.dairyId)
      update, delete: auth != null && isMember(resource.data.dairyId)

    // Dairy Settings: Owner-only read/write
    dairy_settings/{dairyId}:
      read, write: auth.uid == dairyId

    // Default: deny all
    match /{document=**} { allow read, write: if false; }
  }
}
```

**Key Security Changes from Previous Version:**
1. **`isMember()` function** replaces simple `dairyId == auth.uid` — now supports staff access
2. **Owner fallback** (`uid == dairyId`) means admin always has access even without `_members` doc
3. **`_members` collection** added — managed by admin, lists all UIDs with access
4. **Staff self-read** via `firebaseAuthUid` field — staff can read their own staff doc
5. **No passwords in `public_lookups`** — staff auth moved to Firebase Auth
6. **No email in admin `public_lookups`** — only `userId` and `name` stored

---

## 6. SharedPreferences (Local Settings)

### Session / Auth
| Key | Type | Description |
|-----|------|-------------|
| `isLoggedIn` | bool | Login state |
| `userRole` | String | "admin" / "staff" |
| `userName` | String | Current user name |
| `userMobile` | String | Current user mobile |
| `userEmail` | String | Current user email |
| `firebaseDairyId` | String | Firebase UID (string) |
| `dairyId` | int | SQLite dairy ID (hashCode of firebase UID) |
| `userId` | int | Staff: hashCode, Admin: 0 |
| `firebaseUserId` | String | Staff doc ID (only for staff) |
| `dairyName` | String | Dairy name |
| `authProvider` | String | "email" / "google" / "phone" |
| `previousFirebaseDairyId` | String | For data isolation check |
| `isDemo` | bool | Demo mode flag |

### Dairy Info
| Key | Type |
|-----|------|
| `dairy_address` | String |
| `dairy_village` | String |
| `dairy_city` | String |
| `dairy_state` | String |
| `dairy_pincode` | String |
| `dairy_contact` | String |
| `managerMobile` | String |
| `tagline` | String |
| `signatureLabel` | String |

### Settings
| Key | Type | Default |
|-----|------|---------|
| `language_code` | String | "hi" |
| `language_selected` | bool | false |
| `theme_mode` | String | "light" |
| `quickEntryMode` | bool | false |
| `autoCalculateRate` | bool | true |
| `showFatSnfWarning` | bool | true |
| `showEntryConfirmation` | bool | true |
| `defaultShift` | String | "auto" |
| `soundOnEntry` | bool | true |
| `printAfterBilling` | bool | false |
| `minFatWarningBuffalo` | double | 5.0 |
| `maxFatWarningBuffalo` | double | 10.0 |
| `minFatWarningCow` | double | 3.0 |
| `maxFatWarningCow` | double | 5.5 |

### Rate Settings
| Key | Type | Default |
|-----|------|---------|
| `buffaloPerKgFatRate` | double | 820.0 |
| `cowEfuRate` | double | 382.69 |
| `cowDefaultSnf` | double | 8.5 |
| `buffaloSnf88to89Deduction` | double | 2.0 |
| `buffaloSnf85to87Deduction` | double | 4.0 |
| `buffaloSnf84Penalty` | double | 75.0 |
| `buffaloLowQualityPenalty` | double | 75.0 |
| `cowSnf83to84Deduction` | double | 2.0 |
| `cowSnf81to82Deduction` | double | 4.0 |
| `cowHighFatDeduction` | double | 15.0 |
| `cowSnf80Penalty` | double | 75.0 |
| `cowLowFatPenalty` | double | 50.0 |

### Sync / Backup
| Key | Type |
|-----|------|
| `lastFirestoreSync` | String |
| `lastBackupDate` | String |
| `lastDriveBackupDate` | String |
| `lastAutoBackupDate` | String |

---

## 7. Core Features - Screen by Screen

### 7.1 Home Screen

- **Bottom Navigation:** 5 tabs for Admin, 2 tabs for Staff
- **Admin Tabs:** Entry History, Farmers, Milk Entry (default), Payment Manager, More
- **Staff Tabs:** Milk Entry (default), Entry History
- **Header:** Dairy name + logo + settings icon
- **Realtime sync** starts on this screen: `startRealtimeSync(dairyId)`
- Logo tap → Dashboard

### 7.2 Dashboard

- **Admin-only** analytics page
- **KPI Cards:** Total Farmers, Today's Milk, Today's Amount, Active Farmers
- **7-Day Bar Chart:** Daily milk collection (using fl_chart)
- **Trend:** Today vs Yesterday % change
- **Quick Actions:** Add Farmer, New Entry, Billing, Reports
- **Navigation Drawer:** Full menu access + Logout
- Calls `fullSync()` before loading data

### 7.3 Milk Entry (Main Feature)

**The core business operation — recording milk collection from farmers.**

**UI Elements:**
- Date/Shift card (auto-detect morning < 2PM, evening ≥ 2PM)
- Farmer code input + dropdown popup (search by code/name/mobile)
- Cattle type toggle (Buffalo 🐃 / Cow 🐄)
- Quantity (liters), FAT (%), SNF (%) fields
- Calculated Rate & Amount display
- Today's collection summary
- Last 5 entries list

**Business Logic:**
```
1. User enters Farmer Code → app looks up farmer
2. Auto-fills cattleType from farmer's default
3. User enters Quantity, FAT, SNF
4. Rate auto-calculated:
   - If farmer.useFixedRate → rate = farmer.fixedRate
   - Else → RateCalculator.calculateRate(cattleType, fat, snf)
5. Amount = Quantity × Rate
6. Save: SQLite + Firestore (via addMilkEntryWithSync)
```

**Validations:**
- Quantity: 0.1 - 200 liters
- FAT: 0.1 - 15.0%
- Duplicate check: same farmer + date + shift → warning
- FAT warnings: buffalo fat < 5.1 or cow fat > 5.0 → cattle type mismatch
- Backdating: up to 30 days allowed

**Quick Entry Mode:**
- FAT/SNF are optional (saved as 0)
- Entry marked `isPending = true`, rate = 0
- Later completed via Entry History screen

**Data Written:**
```dart
MilkEntry(
  farmerId: farmer.id,
  farmerCode: "001",
  farmerName: "Ramesh Kumar",
  dateTime: DateTime.now(),  // or selected date
  shift: "morning",          // or "evening"
  quantity: 10.5,            // liters
  fat: 6.5,                  // percentage
  snf: 8.8,                  // percentage
  rate: 53.30,               // calculated rate per liter
  amount: 559.65,            // quantity × rate (ROUNDED to 2 decimals)
  cattleType: "buffalo",
  isPending: false,
  createdByUserId: userId,   // staff ID or 0
  createdByUserName: "Staff Name",
  dairyId: sqliteDairyId,
  syncId: "a1b2c3d4-...",   // UUID v4 auto-generated
)
```

> **Amount Rounding:** `_totalAmount = double.parse((quantity * rate).toStringAsFixed(2))` prevents floating-point artifacts like `31.500000000004`.
>
> **syncId:** Auto-generated UUID v4 in the `MilkEntry` constructor. Used as primary dedup key during cloud sync.

### 7.4 Farmers Management

**CRUD for farmers (milk suppliers).**

| Operation | Local | Cloud |
|-----------|-------|-------|
| Add | `db.insertFarmer()` | `addFarmerWithSync()` → `farmers` collection |
| Edit | `db.updateFarmer()` | `updateFarmerWithSync()` → update/create in `farmers` |
| Delete | Delete farmer + milk_entries + payments + advances | Delete from all 3 Firestore collections |

**Farmer Fields:**
- Code (auto-generated, unique per dairy)
- Name, Father's Name
- Mobile (10 digits)
- Cattle Type: "cow" / "buffalo"
- Use Fixed Rate: toggle
- Fixed Rate: ₹ per liter (if enabled)

**Search:** By name, code, or mobile number.

### 7.5 Payment Manager

**4-Tab Payment System:**

#### Tab 1: Bill (Generate Payment)
```
Select Farmer → Select Billing Period → Calculate Bill
    │
    ├─ Billing Periods:
    │   ├─ 10_DAYS: 1-10, 11-20, 21-end of month
    │   ├─ 15_DAYS: 1-15, 16-end of month
    │   ├─ MONTH: Full previous month
    │   └─ CUSTOM: Date range picker
    │
    ▼
Bill Calculation (all values ROUNDED to 2 decimals):
    totalMilk   = Sum of all milk entry quantities in period
    totalAmount  = Sum of all milk entry amounts in period
    totalAdvance = Sum of unpaid advances (type='ADVANCE', isPaid=0 in payments table)
    totalPaid    = Sum of payments already made in period
    lbtAmount    = ₹10 (fixed deduction)
    netPayable   = totalAmount - totalAdvance - totalPaid - lbtAmount
    │
    ▼
Show BillPreviewScreen → Print/Share PDF
    │
    ▼
On Confirm: addPaymentWithSync() + markAdvancesPaidWithSync()
```

> **Rounding Fix:** All bill values use `double.parse(value.toStringAsFixed(2))` to prevent floating-point precision issues (e.g., `31.500000000004`).

#### Tab 2: Advance (Give Advance to Farmer)
```
Select Farmer → Enter Amount → Optional Remarks
    │
    ▼
Creates Payment object with type='ADVANCE' (NOT an Advance object!)
    │
    ▼
addPaymentWithSync() → SQLite payments table + Firestore payments collection
```

> ⚠️ **IMPORTANT:** Advances are stored as `Payment(type: 'ADVANCE')` in the `payments` table. The UI reads advances from this table with `WHERE type = 'ADVANCE'`. The separate `advances` table exists but is NOT the primary source.

#### Advance Reversal on Bill Delete
```
deletePaymentWithSync(paymentId)
    │
    ├─ If advanceDeduction > 0:
    │   ├─ Find farmer's advances in both 'payments' + 'advances' tables
    │   ├─ Set isPaid = 0 (reverse the deduction)
    │   └─ Update Firestore docs (find by farmerCode + type='ADVANCE' + isPaid=true)
    │
    └─ Delete payment from SQLite + Firestore
```

> This prevents farmers from losing money when a bill with advance deduction is deleted.

#### `markAdvancesPaidWithSync()`
When a bill is confirmed, unpaid advances are marked as paid:
```
1. Update advances table: SET isPaid = 1 for matching farmer
2. Update payments table: SET isPaid = 1 WHERE type='ADVANCE' (← the table UI reads from!)
3. Update Firestore payments collection: isPaid = true
```

> **Critical:** Must update BOTH tables (advances + payments) because the UI reads advances from the `payments` table.

#### Tab 3: Bulk Pay
- Select multiple farmers at once
- Generate bill for all selected farmers in the same billing period
- Process each bill sequentially

#### Tab 4: History
- View all past payments and advances
- Filter by type: ALL / PAYMENT / ADVANCE
- Search by farmer name/code
- Edit and Delete with sync (delete triggers advance reversal if applicable)

### 7.6 Billing & Bill Preview

**BillingScreen:** Simple date-range filtered entry listing with summary stats.

**BillPreviewScreen (Professional Invoice):**
- **Two Templates:** Summary (daily totals) and Detailed (every entry)
- **Invoice sections:** Header (dairy info), farmer info, billing period, daily collection table, quality analysis, payment summary, signatures
- **Quality Score (0-100):** fatScore + snfScore + consistencyScore + regularityScore → Grade A+/A/B+/B/C
- **Quality Checks:** Water adulteration (SNF < 7.5), Fat adulteration (fat < 3.0)
- **Amount in words:** Indian numbering system (Crore/Lakh/Thousand)
- **PDF Generation:** A4 format with NotoSans + NotoSansDevanagari fonts
- **Actions:** Print (via Printing library), Share (via Share Plus)

### 7.7 Entry History

**View, filter, edit, delete milk entries + complete pending entries.**

- **Two tabs:** Completed / Pending
- **Filters:** Today / 7 Days / All + calendar picker + staff dropdown + farmer dropdown
- **Staff edit rule:** Can only edit/delete within 2 minutes of creation
- **Admin:** Can always edit/delete

**Edit Entry Dialog:**
- Modify quantity, FAT, SNF
- Rate auto-recalculated
- Synced via `updateMilkEntryWithSync()`

**Complete Pending Entry:**
- Add FAT/SNF to a quick-entry
- Calculate rate, mark `isPending = false`
- Synced via `updateMilkEntryWithSync()`

### 7.8 Reports & Export

**Comprehensive reporting system with 2 views:**

#### Farmer List View
- Date range picker (default: all data)
- Summary row: total farmers, total milk, total amount
- Sortable table: Code, Name, Milk (L), Amount (₹), Pending (₹)
- **Pending calculation:** Sum of entry amounts AFTER farmer's last payment date

#### Farmer Detail View
- Filter chips: All / 7 Days / 30 Days / 3 Months / Custom
- Stats: Entries, Milk, Amount, Paid, Balance
- Two tabs: Entries + Payments

**Export Options:**
- **Excel (xlsx):** 3 sheets — Farmer Summary, Milk Entries, Payments
- **PDF:** A4 pages with summary table, stat boxes, headers/footers
- **Per-farmer Excel:** Individual farmer's entries + payments
- **Per-farmer PDF:** Individual farmer ledger
- **Print:** Via Printing library

### 7.9 Rate Chart

**Configure milk pricing formulas.**

- **Two tabs:** Buffalo / Cow
- **Rate chart grid:** Shows calculated rate for each FAT value
- **Edit settings modal:** Change base rates
- **SNF deduction settings:** Configure deduction percentages

**Data saved to:** SharedPreferences + Firestore `dairy_settings/{dairyId}`

(See Rate Calculation Logic section below for formulas)

### 7.10 Staff Management

**Full CRUD for staff users with Firebase Auth.**

**Staff Fields:**
| Field | Required | Notes |
|-------|----------|-------|
| Name | Yes | |
| Mobile | Yes | Immutable after creation, used as login ID |
| Password | Yes | Min 4 chars |
| Father's Name | No | |
| Email | No | |
| Address | No | |
| Aadhaar | No | Identity document |
| PAN | No | Tax ID |
| Bank Account | No | |
| IFSC | No | Bank code |

**Operations:**
| Action | What Happens |
|--------|-------------|
| **Add Staff** | 1. Create Firebase Auth account via **secondary app** (`staff_{mobile}@dudhpassbook.com`) → get `staffAuthUid` |
| | 2. Create `staff/{auto_id}` doc with `firebaseAuthUid: staffAuthUid` |
| | 3. Create `public_lookups/staff_mobile_{phone}` (NO password) |
| | 4. Optional: Create `public_lookups/staff_email_{email}` |
| | 5. Add `staffAuthUid` to `_members/{dairyId}.uids` array |
| | 6. Insert into SQLite `users` table |
| **Edit Staff** | `updateStaff()` → update `staff` doc + update Firebase Auth password via secondary app + update lookups + SQLite |
| **Delete Staff** | 1. Sign in as staff via secondary app → delete Firebase Auth account |
| | 2. Remove `staffAuthUid` from `_members/{dairyId}.uids` |
| | 3. Delete `staff` doc + delete lookups + delete from SQLite |

**Secondary Firebase App:** Admin can create/edit/delete staff Firebase Auth accounts WITHOUT signing out. This uses `Firebase.initializeApp(name: 'staffAuth')` — a separate `FirebaseAuth` instance.

```dart
Future<FirebaseAuth> _getSecondaryAuth() async {
  try {
    final app = Firebase.app('staffAuth');
    return FirebaseAuth.instanceFor(app: app);
  } catch (_) {
    final app = await Firebase.initializeApp(name: 'staffAuth', options: Firebase.app().options);
    return FirebaseAuth.instanceFor(app: app);
  }
}
```

**Password Storage:** The password is kept in the `staff/{id}` Firestore doc (readable only by admin via `dairyId == auth.uid` rule) so the admin can manage staff accounts and delete Firebase Auth when needed.

### 7.11 Profile

- **View:** Name, Mobile (locked), Email (locked), Dairy Name, Address, City, etc.
- **Edit:** All fields except mobile and email
- **Saved to:** SharedPreferences + Firestore (`users/{uid}` + `dairies/{uid}`)

### 7.12 Settings

| Category | Settings |
|----------|----------|
| Appearance | Theme: Light / Dark / System |
| Language | Hindi / English |
| Milk Entry | Quick Entry, Auto Calculate Rate, Entry Confirmation, FAT/SNF Warning, Sound, Default Shift |
| Billing | Print After Billing |
| FAT Warning | Min/Max ranges for Buffalo and Cow |
| Cloud Sync | Sync Now button + status display |
| Logout | Clear prefs + Firebase signout |

### 7.13 Backup & Restore

**Google Drive Backup:**
- Backup file: `dudhpassbook_backup.json` in Google Drive `appDataFolder`
- Also creates daily timestamped copies: `backup_YYYY-MM-DD.json`
- **Auto-backup:** Every night at midnight via WorkManager
- Requires Google Drive `appdata` scope

**Local File Backup:**
- Creates JSON file → shares via native share sheet
- Restore from `.json` file via FilePicker

**Backup Data Structure (JSON):**
```json
{
  "version": 2,
  "createdAt": "2026-02-17T12:00:00.000",
  "dairyId": 12345678,
  "data": {
    "farmers": [{ ... }],
    "milkEntries": [{ ... }],
    "payments": [{ ... }],
    "advances": [{ ... }],
    "rateCharts": [{ ... }],
    "users": [{ /* staff only */ }]
  },
  "counts": {
    "farmers": 50,
    "milkEntries": 3000,
    "payments": 200,
    "advances": 100
  }
}
```

---

## 8. Rate Calculation Logic

### Buffalo Rate Formula

```
baseRate = FAT × buffaloPerKgFatRate / 100

Example: FAT = 6.5, bufRate = 820
baseRate = 6.5 × 820 / 100 = ₹53.30/liter
```

**SNF Deductions (applied to baseRate):**

| SNF Range | Deduction | Result |
|-----------|-----------|--------|
| ≥ 9.0 AND FAT 5.1-10.0 | None | Full rate |
| 8.8 - 9.0 | -2% | rate × 0.98 |
| 8.5 - 8.8 | -4% | rate × 0.96 |
| 8.4 - 8.5 | -75% | rate × 0.25 |
| ≤ 5.0 FAT AND ≤ 9.0 SNF | -75% | rate × 0.25 |
| < 8.4 | -75% | rate × 0.25 |

### Cow Rate Formula

```
snfEfu = SNF × 2/3
totalEfu = FAT + snfEfu
baseRate = totalEfu × cowEfuRate / 100

Example: FAT = 4.0, SNF = 8.5, cowEfuRate = 382.69
snfEfu = 8.5 × 0.667 = 5.67
totalEfu = 4.0 + 5.67 = 9.67
baseRate = 9.67 × 382.69 / 100 = ₹37.00/liter
```

**Cow SNF Deductions:**

| Condition | Deduction | Result |
|-----------|-----------|--------|
| FAT < 3.0 | REJECTED | ₹0.00 |
| FAT ≥ 5.1 AND SNF ≥ 8.5 | -15% | rate × 0.85 |
| SNF ≥ 8.5 AND FAT 3.0-5.0 | None | Full rate |
| SNF 8.3 - 8.5 | -2% | rate × 0.98 |
| SNF 8.1 - 8.3 | -4% | rate × 0.96 |
| SNF < 8.1 | -75% | rate × 0.25 |

### Rate Calculation in the App

```
Amount = Quantity (liters) × Rate (₹/liter)

// If farmer has fixed rate enabled:
rate = farmer.fixedRate

// Otherwise:
rate = RateCalculator.calculateRate(cattleType, fat, snf)
```

---

## 9. Sync System (App ↔ Cloud)

> **File:** `lib/services/firestore_sync_service.dart` (~3740 lines)

### 9.1 Full Sync

Called on: Login, Dashboard load, Settings "Sync Now" button.

```
fullSync(localDairyId, isNewUser)
    │
    ├── 0. _ensureMembersDoc()  → Creates _members doc if missing (auto-migration)
    ├── 1. _syncFarmers()       → Firestore 'farmers' ↔ SQLite 'farmers'
    ├── 2. _syncMilkEntries()   → Firestore 'milkEntries' ↔ SQLite 'milk_entries' (last 30 days)
    ├── 3. _syncPayments()      → Firestore 'payments' ↔ SQLite 'payments' + 'advances'
    ├── 4. _syncStaff()         → Firestore 'staff' ↔ SQLite 'users'
    └── 5. _syncRateSettingsToLocal() → Firestore 'dairy_settings' → SharedPreferences

isNewUser = true → DOWNLOAD ONLY (no upload of stale local data)
isNewUser = false → BIDIRECTIONAL (upload + download)
```

### 9.2 Realtime Sync (Listeners)

Started when HomeScreen initializes: `startRealtimeSync(dairyId)`

```
3 Firestore snapshot listeners running simultaneously:

1. farmers collection (where dairyId == myDairyId)
   → On added/modified: insert/update local farmer
   → On removed: delete local farmer

2. milkEntries collection (where dairyId == myDairyId)
   → On added: if not exists locally → insert
   → On modified: find local entry → update all fields
   → On removed: find local entry → delete
   → Cross-platform compatible: handles both APK format (farmerCode+dateTime) 
     and website format (farmerId+date+timestamp)

3. payments collection (where dairyId == myDairyId)
   → On added/modified/removed: same pattern
   → Handles date in both Timestamp and String formats
   → ALL types (PAYMENT and ADVANCE) go into SQLite 'payments' table
```

**Important for Website:** The realtime listeners handle both APK and website data formats. When the website writes a milk entry, it can use either `farmerCode + dateTime` or `farmerId + date + timestamp` format — the app will correctly process both.

### 9.3 Individual Sync Methods

#### Farmer Sync
```
Local farmers indexed by CODE
Remote farmers indexed by CODE
Upload: local not in remote → create in Firestore
Download: remote not in local → insert in SQLite
Update: if both exist, compare updatedAt timestamps → newer wins
```

#### Milk Entry Sync (UUID-based dedup)
```
PRIMARY dedup key: syncId (UUID v4)
FALLBACK dedup key: "{farmerCode}_{dateTime_ISO}_{shift}" (for legacy entries without syncId)

Process:
1. Build map of remote entries: { syncId → data, legacyKey → data }
2. Build map of local entries:  { syncId → data, legacyKey → data }
3. For each local entry:
   - Has syncId AND remote has same syncId → SKIP (already synced)
   - Has syncId but NOT in remote → UPLOAD to Firestore
   - No syncId → check legacyKey match → SKIP or UPLOAD
4. For each remote entry:
   - Has syncId AND local has same syncId → SKIP
   - Has syncId but NOT in local → DOWNLOAD to SQLite
   - No syncId → check legacyKey → SKIP or DOWNLOAD

Only last 30 days synced.

Upload includes: updatedAt: FieldValue.serverTimestamp()
```

#### Payment/Advance Download (`_downloadPayment`)
```
ALL types (PAYMENT and ADVANCE) are stored in the 'payments' table as Payment objects.
There is NO branch for "if type == ADVANCE → store in advances table".

Key fields set on download:
- dairyId: sqliteDairyId  ← CRITICAL (was missing before, caused NULL dairyId bug)
- netAmount: parsed with (data['netAmount'] as num?)?.toDouble() 
  NOT: data['netAmount'] ?? data['amount'] as num?  ← operator precedence bug
- type: data['type'] ?? 'PAYMENT'

The Firestore date fields (date, paymentDate, fromDate, toDate) can be:
- Timestamp → .toDate()
- String → DateTime.parse()
- DateTime → use directly
All handled by a local parseFirestoreDate() helper.
```

#### Payment Dedup Key
```
Dedup key: "{farmerCode}_{YYYY-MM-DD}_{type}_{netAmount.toFixed(2)}"
Includes amount in key to differentiate multiple payments same day

On each sync:
1. Firestore dedup cleanup (delete duplicate docs)
2. Local dedup cleanup (delete duplicate rows in payments + advances tables)
3. Re-read clean data
4. Compare keys → upload missing / download missing
```

#### Staff Sync
```
Dedup key: mobile number
Upload: local staff mobiles not in remote → create in Firestore
Download: remote staff mobiles not in local → insert in SQLite
```

#### Advance Reversal on Bill Delete (`deletePaymentWithSync`)
```
When a payment/bill with advanceDeduction > 0 is deleted:
1. Find farmer's advances in both 'payments' table (type='ADVANCE') and 'advances' table
2. Set isPaid = 0 locally (both tables)
3. Find Firestore docs: payments where farmerCode matches + type='ADVANCE' + isPaid=true
4. Update each: isPaid = false in Firestore
5. Then delete the payment doc from both SQLite and Firestore
```

#### `updatedAt` Timestamps
All upload methods now include `updatedAt: FieldValue.serverTimestamp()`:
- `_uploadMilkEntry()` — milkEntries collection
- `_uploadPayment()` — payments collection
- Advance uploads — payments collection (type='ADVANCE')

This enables **future incremental sync** — only fetch docs where `updatedAt > lastSyncTime`.

### 9.4 Dedup Keys

| Data Type | Primary Key | Fallback Key | Example |
|-----------|------------|--------------|---------|
| Farmer | `code` | — | `"001"` |
| Milk Entry | **`syncId` (UUID)** | `{farmerCode}_{dateTime}_{shift}` | `"a1b2c3d4-..."` / `"001_2026-02-17T08:30:00.000_morning"` |
| Payment | `{farmerCode}_{date}_{type}_{amount}` | — | `"001_2026-02-17_PAYMENT_5596.50"` |
| Advance | `{farmerCode}_{date}_ADVANCE_{amount}` | — | `"001_2026-02-17_ADVANCE_1000.00"` |
| Staff | `mobile` | — | `"9876543210"` |

---

## 10. Auto Backup System

```
WorkManager periodic task: 'dailyAutoBackup'
Frequency: Every 24 hours
Start: Next midnight
Constraints: Network connected + Battery not low

Task Flow:
1. Firebase.initializeApp()
2. Read dairyId + isLoggedIn from SharedPreferences
3. If logged in → GoogleDriveBackupService.backupToDrive(dairyId)
4. Save lastAutoBackupDate
```

---

## 11. Website Integration Guide

### Key Points for Website Development

#### 1. Authentication
- **Admin auth:** Use Firebase Auth — try ghost email `{mobile}@dudhpassbook.com` first, fallback to legacy email
- **Staff auth (Option A — Recommended):** Use Firebase Auth with ghost email `staff_{mobile}@dudhpassbook.com`
- **Staff auth (Option B — Legacy):** Read `public_lookups/staff_mobile_{phone}`, if it has `password` field, compare plaintext
- **dairyId** = Firebase Auth UID (this is the master key for ALL data isolation)

#### 2. Data Isolation
- ALL queries MUST filter by `dairyId`
- Each admin's data is completely isolated
- Staff belongs to one admin (via `dairyId`)

#### 3. Writing Milk Entries from Website
When creating a milk entry from the website, write to Firestore `milkEntries` collection:

```javascript
// REQUIRED fields for APK compatibility:
{
  farmerId: farmerCode,        // or farmer's local ID
  farmerCode: "001",           // MUST match farmer's code
  farmerName: "Ramesh Kumar",
  date: "2026-02-17",          // YYYY-MM-DD
  dateTime: "2026-02-17T08:30:00.000",  // Full ISO 8601
  shift: "morning",            // "morning" or "evening"
  cattleType: "buffalo",       // "cow" or "buffalo"
  quantity: 10.5,
  fat: 6.5,
  snf: 8.8,
  rate: 53.30,
  amount: 559.65,              // ROUND to 2 decimals
  totalAmount: 559.65,         // Same as amount
  isPending: false,
  status: "COMPLETED",         // "PENDING" or "COMPLETED"
  isLabTested: true,
  syncId: crypto.randomUUID(), // UUID v4 for dedup (NEW — IMPORTANT!)
  dairyId: "firebase_uid",    // Admin's Firebase UID
  timestamp: Date.now(),       // Milliseconds since epoch
  createdAt: serverTimestamp(), // Firestore server timestamp
  updatedAt: serverTimestamp(), // NEW — for incremental sync
}
```

The APK's realtime listener will automatically pick up this entry and insert it into local SQLite.

#### 4. Writing Payments from Website
```javascript
{
  farmerId: "001",             // Farmer code
  farmerCode: "001",
  farmerName: "Ramesh Kumar",
  date: "2026-02-17T00:00:00.000",  // ISO 8601 string (NOT Timestamp!)
  paymentDate: "2026-02-17T00:00:00.000",
  type: "PAYMENT",             // "PAYMENT" or "ADVANCE"
  amount: 5596.50,             // Net amount
  totalAmount: 6000.00,        // Gross amount
  advanceDeduction: 403.50,
  netAmount: 5596.50,
  totalLiters: 105.0,
  paymentMode: "cash",         // "cash", "upi", "bank"
  dairyId: "firebase_uid",
  timestamp: Date.now(),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(), // NEW — for incremental sync
}
```

**⚠️ IMPORTANT:** Store `date` as ISO 8601 **string**, NOT as Firestore Timestamp. The APK's sync uses string-based date comparison.

#### 5. Writing Advances from Website
```javascript
{
  farmerId: "001",
  farmerCode: "001",
  farmerName: "Ramesh Kumar",
  date: "2026-02-17T00:00:00.000",  // ISO 8601 string
  type: "ADVANCE",             // MUST be "ADVANCE"
  amount: 1000.00,
  netAmount: 1000.00,          // Same as amount for advances
  isPaid: false,               // true = already deducted from payment
  dairyId: "firebase_uid",
  timestamp: Date.now(),
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(), // NEW — for incremental sync
}
```

#### 6. Writing Farmers from Website
```javascript
{
  code: "051",                 // Unique per dairy
  name: "Ramesh Kumar",
  fatherName: "Suresh Kumar",
  mobile: "9876543210",
  cattleType: "buffalo",       // "cow" or "buffalo"
  defaultCattleType: "buffalo",
  useFixedRate: false,
  fixedRate: null,
  currentBalance: 0.0,
  dairyId: "firebase_uid",
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
  isActive: true,
}
```

#### 7. Rate Calculation (JavaScript)
```javascript
// Buffalo
function calcBuffaloRate(fat, snf, perKgFatRate = 820) {
  let baseRate = fat * perKgFatRate / 100;
  if (snf >= 9.0 && fat > 5.0 && fat <= 10.0) return baseRate;
  if (snf >= 8.8) return baseRate * 0.98;  // -2%
  if (snf >= 8.5) return baseRate * 0.96;  // -4%
  if (snf >= 8.4) return baseRate * 0.25;  // -75%
  if (fat <= 5.0 && snf <= 9.0) return baseRate * 0.25;
  return baseRate * 0.25;  // SNF < 8.4
}

// Cow
function calcCowRate(fat, snf, efuRate = 382.69) {
  if (fat < 3.0) return 0;  // Rejected
  let snfEfu = snf * (2/3);
  let totalEfu = fat + snfEfu;
  let baseRate = totalEfu * efuRate / 100;
  if (fat >= 5.1 && snf >= 8.5) return baseRate * 0.85;  // -15%
  if (snf >= 8.5) return baseRate;
  if (snf >= 8.3) return baseRate * 0.98;  // -2%
  if (snf >= 8.1) return baseRate * 0.96;  // -4%
  return baseRate * 0.25;  // -75%
}
```

#### 8. Billing Calculation (JavaScript)
```javascript
function calculateBill(entries, unpaidAdvances, paidInPeriod) {
  const totalAmount = entries.reduce((sum, e) => sum + e.amount, 0);
  const totalLiters = entries.reduce((sum, e) => sum + e.quantity, 0);
  const totalAdvance = unpaidAdvances.reduce((sum, a) => sum + a.amount, 0);
  const totalPaid = paidInPeriod.reduce((sum, p) => sum + p.netAmount, 0);
  const lbtAmount = 10;  // Fixed ₹10 deduction
  const netPayable = totalAmount - totalAdvance - totalPaid - lbtAmount;
  
  return { totalAmount, totalLiters, totalAdvance, totalPaid, lbtAmount, netPayable };
}
```

#### 9. Billing Periods
```javascript
// 10-day cycle
function get10DayPeriods(date) {
  const year = date.getFullYear(), month = date.getMonth();
  const lastDay = new Date(year, month + 1, 0).getDate();
  return [
    { from: new Date(year, month, 1),  to: new Date(year, month, 10) },
    { from: new Date(year, month, 11), to: new Date(year, month, 20) },
    { from: new Date(year, month, 21), to: new Date(year, month, lastDay) },
  ];
}

// 15-day cycle
function get15DayPeriods(date) {
  const year = date.getFullYear(), month = date.getMonth();
  const lastDay = new Date(year, month + 1, 0).getDate();
  return [
    { from: new Date(year, month, 1),  to: new Date(year, month, 15) },
    { from: new Date(year, month, 16), to: new Date(year, month, lastDay) },
  ];
}

// Monthly: 1st to last day of previous month
```

#### 10. Staff Login from Website
```javascript
// OPTION A: Firebase Auth (recommended — new staff accounts)
async function loginStaff(mobile, password) {
  const ghostEmail = `staff_${mobile}@dudhpassbook.com`;
  try {
    const cred = await firebase.auth().signInWithEmailAndPassword(ghostEmail, password);
    // Find staff doc by firebaseAuthUid
    const staffQuery = await db.collection('staff')
      .where('firebaseAuthUid', '==', cred.user.uid)
      .where('isActive', '==', true)
      .limit(1).get();
    if (!staffQuery.empty) {
      return { success: true, ...staffQuery.docs[0].data() };
    }
    return { success: false, error: "Staff data not found" };
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      // Fall through to legacy lookup
    } else {
      return { success: false, error: e.message };
    }
  }

  // OPTION B: Legacy fallback (old staff without Firebase Auth)
  const doc = await db.doc(`public_lookups/staff_mobile_${mobile}`).get();
  if (doc.exists) {
    const data = doc.data();
    if (data.password === password && data.isActive) {
      return { success: true, ...data };
    }
    return { success: false, error: "Wrong password" };
  }
  return { success: false, error: "Staff not found" };
}
```

> **Note:** New staff created by the APK use Firebase Auth (ghost email). Old staff may still have plaintext passwords in `public_lookups`. The website should try Firebase Auth first, then fall back to legacy lookup.

#### 11. Data Format Compatibility Notes

| Field | APK Format | Website Should Use |
|-------|-----------|-------------------|
| Dates | ISO 8601 string | ISO 8601 string (NOT Firestore Timestamp) |
| `dairyId` (in Firestore docs) | Admin's Firebase UID (string) | Same Firebase UID (string) |
| `dairyId` (in SQLite/SharedPreferences) | `firebase_uid.hashCode.abs()` (int) | N/A (website uses Firebase UID directly) |
| `farmerId` (in milk entries) | SQLite auto-increment int | Use `farmerCode` instead |
| `syncId` (in milk entries) | UUID v4 string | Generate `crypto.randomUUID()` |
| Admin auth email | Ghost: `{mobile}@dudhpassbook.com` | Same ghost email pattern |
| Staff auth email | Ghost: `staff_{mobile}@dudhpassbook.com` | Same ghost email OR legacy lookup |
| Shift | "morning" / "evening" | Same values |
| Cattle type | "cow" / "buffalo" | Same values |
| Payment type | "PAYMENT" / "ADVANCE" | Same values (uppercase) |
| Payment mode | "cash" / "upi" / "bank" | Same values |
| Amounts | Rounded to 2 decimal places | Same — use `toFixed(2)` |
| `updatedAt` | `FieldValue.serverTimestamp()` | `serverTimestamp()` |

#### 12. Reading Data for Website Dashboard
```javascript
// Get all farmers for a dairy
const farmers = await db.collection('farmers')
  .where('dairyId', '==', firebaseUid).get();

// Get milk entries for a date range
const entries = await db.collection('milkEntries')
  .where('dairyId', '==', firebaseUid)
  .where('timestamp', '>=', startTimestamp)
  .where('timestamp', '<=', endTimestamp)
  .get();

// Get all payments
const payments = await db.collection('payments')
  .where('dairyId', '==', firebaseUid).get();

// Get rate settings
const settings = await db.doc(`dairy_settings/${firebaseUid}`).get();

// Get dairy info
const dairy = await db.doc(`dairies/${firebaseUid}`).get();
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER APK                             │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Screens  │  │ Services │  │  Models  │  │  Utils   │  │
│  │          │  │          │  │          │  │          │  │
│  │Home      │  │Firestore │  │Farmer    │  │Rate      │  │
│  │Dashboard │  │SyncSvc   │  │MilkEntry │  │Calculator│  │
│  │MilkEntry │  │(3740 ln) │  │ +syncId  │  │Localize  │  │
│  │Farmers   │  │          │  │Payment   │  │Theme     │  │
│  │Payment   │  │GDrive    │  │Advance   │  │          │  │
│  │Billing   │  │          │  │          │  │          │  │
│  │Reports   │  │Backup    │  │          │  │          │  │
│  │RateChart │  │Svc       │  │          │  │          │  │
│  │Staff     │  │          │  │          │  │          │  │
│  │Profile   │  │MobileOtp │  │          │  │          │  │
│  │Settings  │  │Svc       │  │          │  │          │  │
│  │Backup    │  │          │  │          │  │          │  │
│  └────┬─────┘  └────┬─────┘  └──────────┘  └──────────┘  │
│       │              │                                      │
│  ┌────▼──────────────▼─────────────────────┐               │
│  │           DATABASE LAYER                 │               │
│  │                                         │               │
│  │  SQLite v10 (DatabaseHelper)            │               │
│  │  ├── farmers                            │               │
│  │  ├── milk_entries (+syncId column)      │               │
│  │  ├── payments (+ type='ADVANCE' rows)   │               │
│  │  ├── advances (secondary)               │               │
│  │  ├── rate_chart                         │               │
│  │  └── users (staff)                      │               │
│  │                                         │               │
│  │  SharedPreferences                      │               │
│  │  ├── Session/Auth keys                  │               │
│  │  ├── Settings keys                      │               │
│  │  ├── Dairy info keys                    │               │
│  │  └── Rate settings keys                 │               │
│  └─────────────────────────────────────────┘               │
│                                                             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Firebase SDK (Primary + Secondary App)
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                    FIREBASE CLOUD                            │
│                                                             │
│  ┌─────────────────┐  ┌──────────────────────────────────┐ │
│  │  Firebase Auth   │  │     Cloud Firestore              │ │
│  │                 │  │                                  │ │
│  │  Admin:         │  │  📁 users/{uid}                  │ │
│  │  {mob}@dudhpass │  │  📁 dairies/{uid}                │ │
│  │  book.com       │  │  📁 _members/{uid}    ← ACL     │ │
│  │                 │  │  📁 public_lookups/...           │ │
│  │  Staff:         │  │  📁 farmers/{auto}                │ │
│  │  staff_{mob}@   │  │  📁 milkEntries/{auto} +syncId   │ │
│  │  dudhpassbook   │  │  📁 payments/{auto}  +updatedAt  │ │
│  │  .com           │  │  📁 staff/{auto} +firebaseAuthUid│ │
│  │                 │  │  📁 dairy_settings/{uid}          │ │
│  │  Google:        │  │                                  │ │
│  │  real@gmail.com │  │  Security: isMember() function   │ │
│  │                 │  │  with owner fallback              │ │
│  │  Phone: +91xxx  │  │                                  │ │
│  └─────────────────┘  └──────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────┐                                       │
│  │  Google Drive    │                                       │
│  │                 │                                       │
│  │  appDataFolder: │                                       │
│  │  • dudhpassbook_ │                                       │
│  │    backup.json   │                                       │
│  │  • backup_YYYY-  │                                       │
│  │    MM-DD.json    │                                       │
│  └─────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Complete Entry Lifecycle

```
1. FARMER CREATION
   App → SQLite farmers table
   App → Firestore farmers/{auto_id}
   Website listener → detects new farmer → auto-downloads to connected APKs

2. MILK ENTRY
   App/Website → Firestore milkEntries/{auto_id}
   App also → SQLite milk_entries table
   Connected devices → realtime listener picks up → inserts locally

3. PAYMENT
   App calculates bill from entries + advances
   App → SQLite payments table + marks advances as paid
   App → Firestore payments/{auto_id}
   Connected devices → realtime listener picks up

4. BACKUP (Daily midnight)
   WorkManager → reads SQLite → creates JSON → uploads to Google Drive
   
5. LOGIN ON NEW DEVICE
   Firebase Auth → get UID → fullSync(isNewUser: true) → downloads ALL data
   Farmers → Milk entries (30 days) → Payments → Staff → Rate settings
```

---

*Document generated: February 18, 2026*
*App Version: 1.0.0*
*Firebase Project: my-diray-83de8*
*SQLite DB Version: 10*
*Dependencies: uuid ^4.5.1*

---

## 12. Critical Bugs Fixed (Change Log)

### Bug 1: Payment/Advance Download — Missing `dairyId`
- **Root Cause:** `_downloadPayment()` created `Payment` objects without setting `dairyId: sqliteDairyId`
- **Effect:** Downloaded payments had `dairyId = NULL`. UI queries use `WHERE dairyId = ?` → returned empty results → payments/advances invisible
- **Fix:** Added `dairyId: sqliteDairyId` to Payment constructor in `_downloadPayment()`
- **File:** `lib/services/firestore_sync_service.dart`

### Bug 2: Advance Download Stored in Wrong Table
- **Root Cause:** `_downloadPayment()` had `if (type == 'ADVANCE') { store in advances table }` branch
- **Effect:** App creates advances as `Payment(type:'ADVANCE')` in `payments` table. UI reads from `payments` table. But download put them in `advances` table → UI never sees them
- **Fix:** Removed the `if (type == 'ADVANCE')` branch entirely. ALL types stored as Payment in `payments` table
- **File:** `lib/services/firestore_sync_service.dart`

### Bug 3: Operator Precedence in Amount Parsing
- **Root Cause:** `data['netAmount'] ?? data['amount'] as num?` — `as` operator binds tighter than `??`, so it evaluated as `data['netAmount'] ?? (data['amount'] as num?)` instead of `(data['netAmount'] ?? data['amount']) as num?`
- **Effect:** Amount could be parsed as wrong type, causing crashes or incorrect values
- **Fix:** Changed to `(data['netAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble()`
- **Files:** `_downloadPayment()`, `_downloadMilkEntry()`, `_downloadMilkEntryFlexible()`

### Bug 4: `Advance.fromMap()` Crash
- **Root Cause:** `amount: map['amount']` without `.toDouble()` — SQLite can return `int` for `REAL` columns if value has no decimal
- **Effect:** `type 'int' is not a subtype of type 'double'` crash when reading advances
- **Fix:** Added `.toDouble()` and null-safe defaults: `farmerCode: map['farmerCode'] ?? ''`, etc.
- **File:** `lib/models/advance.dart`

### Bug 5: Advance Reversal Missing on Bill Delete
- **Root Cause:** `deletePaymentWithSync()` only deleted the payment, but didn't reverse `isPaid` on advances that were deducted
- **Effect:** If admin deletes a bill that had ₹1000 advance deduction, the advance stays `isPaid = 1` → farmer loses ₹1000
- **Fix:** Added logic to find farmer's advances in both `payments` + `advances` tables, set `isPaid = 0`, and update Firestore
- **File:** `lib/services/firestore_sync_service.dart`

### Bug 6: `markAdvancesPaidWithSync()` — Wrong Table Updated
- **Root Cause:** Method only updated `advances` table and Firestore, but UI reads advances from `payments` table
- **Effect:** After billing, advances still showed as unpaid in the UI
- **Fix:** Added update to `payments` table (`WHERE type = 'ADVANCE'`) in addition to `advances` table
- **File:** `lib/services/firestore_sync_service.dart`

### Bug 7: Floating Point Rounding Errors
- **Root Cause:** `quantity * rate` could produce `31.500000000004` due to IEEE 754 float precision
- **Effect:** Bill amounts showed extra decimal digits, minor payment discrepancies
- **Fix:** `double.parse((value).toStringAsFixed(2))` on all amount calculations
- **Files:** `lib/screens/milk_entry_screen.dart`, `lib/screens/payment_manager_screen.dart`

### Bug 8: PERMISSION_DENIED on Firestore Writes (Existing Admins)
- **Root Cause:** New Firestore rules used `isMember()` which called `get()` on `_members/{dairyId}` doc — but existing admins didn't have this doc
- **Effect:** All farmer/payment/milkEntry writes failed with PERMISSION_DENIED
- **Fix:** Added owner fallback (`uid == dairyId` bypasses `_members` check) + `_ensureMembersDoc()` auto-creates on login/sync
- **Files:** `firestore.rules`, `lib/services/firestore_sync_service.dart`

### Bug 9: Staff Plaintext Passwords in Public Lookups
- **Security Issue:** `public_lookups/staff_mobile_{phone}` contained plaintext password readable by anyone
- **Fix:** Staff now uses Firebase Auth (ghost email `staff_{mobile}@dudhpassbook.com`). Public lookups no longer store passwords for new staff
- **Files:** `lib/services/firestore_sync_service.dart`

### Bug 10: Admin Email Exposed in Public Lookups
- **Security Issue:** `public_lookups/mobile_{phone}` and `public_lookups/user_{uid}` contained the admin's real email, publicly readable
- **Fix:** Removed `email` field from all public_lookups writes. Only `userId` and `name` stored
- **Files:** `lib/services/firestore_sync_service.dart`, `lib/screens/login_screen.dart`, `lib/screens/mobile_otp_login_screen.dart`

---

## 13. Design Decisions & Trade-offs

### Why Ghost Emails Instead of Real Emails?
- Rural dairy farmers don't always have email addresses
- Users only need to remember mobile + password
- Ghost email is deterministic from mobile → no lookup needed on login
- Firebase Auth requires email/password provider → ghost email satisfies this requirement

### Why Store Advances in `payments` Table?
- Original design had separate `advances` table
- But the app creates advances via `addPaymentWithSync()` which uses `Payment` model
- UI reads from `payments` table filtered by `type`
- Having two tables caused sync nightmares (data in wrong table after download)
- Decision: `payments` table is the single source of truth; `advances` table is kept for backward compatibility only

### Why Secondary Firebase App for Staff?
- `Firebase.initializeApp(name: 'staffAuth')` creates an isolated auth instance
- Admin can create/edit/delete staff Firebase Auth accounts without signing themselves out
- Each operation: sign in as staff → do action → sign out staff → admin remains signed in on primary app

### Why `_members` Collection Instead of Subcollection?
- Firestore rules can't read subcollections of other documents efficiently
- Top-level `_members/{dairyId}` with `uids` array is fast to check in rules
- Only one `get()` call per rule evaluation vs. multiple subcollection checks

### Why Owner Fallback in `isMember()`?
- Existing admins (pre-`_members`) would lose access to their own data
- `uid == dairyId` always passes → zero-downtime migration
- `_ensureMembersDoc()` gradually creates missing docs on login

### Why `updatedAt` Server Timestamps?
- Prepared for future incremental sync (only fetch docs updated after last sync)
- Currently unused for filtering but the data is being collected
- `FieldValue.serverTimestamp()` ensures consistent time across devices

---

## 14. Files Modified (Complete List)

| File | Changes |
|------|---------|
| `pubspec.yaml` | Added `uuid: ^4.5.1` dependency |
| `lib/models/milk_entry.dart` | Added `syncId` field (UUID v4), updated `toMap()`/`fromMap()` |
| `lib/models/advance.dart` | Fixed `fromMap()` — `.toDouble()`, null-safe defaults |
| `lib/database/database_helper.dart` | DB version 9→10, migration adds `syncId TEXT` column |
| `lib/services/firestore_sync_service.dart` | Major refactoring (~3740 lines): ghost emails, staff Firebase Auth, `_ensureMembersDoc()`, `_downloadPayment()` fix, advance reversal, rounding, `updatedAt` |
| `lib/screens/login_screen.dart` | Ghost email login, `mobile` param for password update, removed email from public_lookups |
| `lib/screens/mobile_otp_login_screen.dart` | Removed email from public_lookups writes |
| `lib/screens/milk_entry_screen.dart` | Amount rounding: `toStringAsFixed(2)` |
| `lib/screens/payment_manager_screen.dart` | Bill calculation rounding: all values to 2 decimals |
| `firestore.rules` | Complete rewrite: `isMember()`, `_members`, owner fallback, staff self-read |

---

## 15. Migration Notes for Existing Users

### What Happens When Existing Users Update the App?
1. **Login:** Ghost email tried first → fails (old account uses real email) → falls back to legacy lookup → succeeds
2. **`_ensureMembersDoc()`:** Auto-creates `_members/{dairyId}` doc with admin UID → future Firestore rule checks work
3. **Public lookups:** On login, `mobile_{phone}` doc is updated (merge) — old `email` field remains but new writes don't add it
4. **SQLite DB v10:** Migration automatically adds `syncId` column to `milk_entries` table. Existing entries get NULL syncId — sync uses legacy dedup key fallback
5. **Staff:** Old staff still work via legacy plaintext lookup fallback. New staff created after update will use Firebase Auth

### No Manual Migration Required
- All migrations are automatic and backward-compatible
- Owner fallback in Firestore rules means old accounts work immediately
- Legacy login paths remain as fallbacks
