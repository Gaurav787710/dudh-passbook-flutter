# Dudh Passbook - डेयरी प्रबंधन प्रणाली

## 📱 About / परिचय

**Dudh Passbook** एक आधुनिक और व्यापक डेयरी प्रबंधन प्रणाली (Comprehensive Dairy Management System) है जो विशेष रूप से भारतीय डेयरी मालिकों की जरूरतों के लिए बनाई गई है।

A modern and comprehensive Dairy Management System specially designed for Indian dairy owners.

## ✨ Key Features / मुख्य विशेषताएं

### 🔐 Authentication & Security
- ✅ Secure login with Admin and Staff roles
- ✅ Demo mode for testing (username: `admin`, password: `admin123`)
- ✅ Role-based access control

### 👨‍🌾 Farmer Management / किसान प्रबंधन
- ✅ Add/Edit/Delete farmers
- ✅ Unique farmer code system
- ✅ Mobile number tracking
- ✅ Cattle type (Cow/Buffalo) support
- ✅ Fixed rate option for specific farmers
- ✅ Search functionality

### 🥛 Milk Collection / दूध संग्रहण
- ✅ Fast entry with farmer code
- ✅ Auto-fetch farmer details
- ✅ Fat & SNF percentage input
- ✅ Automatic rate calculation
- ✅ Morning/Evening shift management
- ✅ Real-time amount calculation
- ✅ Today's collection summary

### 📊 Dashboard / डैशबोर्ड
- ✅ Today's collection overview
- ✅ Total liters and amount
- ✅ Average Fat & SNF
- ✅ Last 7 days graphical chart
- ✅ Quick action buttons

### 💰 Billing & Payments (Coming Soon)
- 📋 Generate bills for custom periods
- 📋 Advance/Loan management
- 📋 Bulk payment processing
- 📋 Payment history

### 📈 Reports & Analytics (Coming Soon)
- 📋 Export to Excel/CSV
- 📋 Filter by date, shift, cattle type
- 📋 Detailed analytics

### ⚙️ Settings / सेटिंग्स
- ✅ Language toggle (Hindi/English)
- ✅ Dairy profile management
- 📋 Rate chart management

### 📱 Mobile Features
- ✅ Offline-first architecture
- ✅ Portrait mode optimized
- 📋 SMS notifications (via native Android)

## 🚀 Getting Started / शुरुआत करें

### Building APK / APK बनाएं

#### Release APK (Production):
```bash
flutter build apk --release
```

The APK will be available at:
`build/app/outputs/flutter-apk/app-release.apk`

#### Split APKs (Smaller size):
```bash
flutter build apk --split-per-abi
```

## 🎯 Default Login Credentials

**Username:** `admin`  
**Password:** `admin123`  
**Role:** Admin

Or click **"Demo Mode"** button to load with sample data.

## 🛠️ Technology Stack

- **Framework:** Flutter 3.10.3
- **Language:** Dart
- **Database:** SQLite (sqflite)
- **Charts:** FL Chart
- **State Management:** Provider pattern

## 📝 Usage Guide / उपयोग गाइड

### First Time Setup:
1. Login with admin credentials or use Demo Mode
2. Go to Settings → Add your dairy details
3. Go to Farmers → Add your farmers with unique codes

### Daily Operations:
1. **Morning Collection:**
   - Open Milk Entry
   - Enter farmer code
   - Input quantity, Fat %, SNF %
   - Submit

2. **Evening Collection:**
   - Repeat the same process
   - Shift automatically changes to "Evening"

3. **View Dashboard:**
   - Check today's total collection
   - View trends for last 7 days

---

**Made in India 🇮🇳 | भारत में निर्मित**
