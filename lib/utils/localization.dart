import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // Auth
      'login': 'Login',
      'username': 'Username',
      'password': 'Password',
      'admin': 'Admin',
      'staff': 'Staff',
      'demo_mode': 'Demo Mode',
      'logout': 'Logout',
      
      // Dashboard
      'dashboard': 'Dashboard',
      'todays_collection': "Today's Collection",
      'total_liters': 'Total Liters',
      'total_amount': 'Total Amount',
      'total_entries': 'Total Entries',
      'avg_fat': 'Avg Fat',
      'avg_snf': 'Avg SNF',
      'pending_payments': 'Pending Payments',
      'last_7_days': 'Last 7 Days',
      
      // Farmers
      'farmers': 'Farmers',
      'add_farmer': 'Add Farmer',
      'farmer_code': 'Farmer Code',
      'farmer_name': 'Farmer Name',
      'mobile': 'Mobile Number',
      'cattle_type': 'Cattle Type',
      'cow': 'Cow',
      'buffalo': 'Buffalo',
      'fixed_rate': 'Fixed Rate',
      'use_fixed_rate': 'Use Fixed Rate',
      'current_balance': 'Current Balance',
      'save': 'Save',
      'cancel': 'Cancel',
      'edit': 'Edit',
      'delete': 'Delete',
      
      // Milk Collection
      'milk_collection': 'Milk Collection',
      'add_entry': 'Add Entry',
      'morning': 'Morning',
      'evening': 'Evening',
      'shift': 'Shift',
      'quantity': 'Quantity (Liters)',
      'fat': 'Fat %',
      'snf': 'SNF %',
      'rate': 'Rate',
      'amount': 'Amount',
      'submit': 'Submit',
      'auto_shift': 'Auto Shift',
      
      // Billing
      'billing': 'Billing & Payments',
      'generate_bill': 'Generate Bill',
      'from_date': 'From Date',
      'to_date': 'To Date',
      'advance_deduction': 'Advance Deduction',
      'net_amount': 'Net Amount',
      'pay_now': 'Pay Now',
      'payment_mode': 'Payment Mode',
      'cash': 'Cash',
      'upi': 'UPI',
      'bank': 'Bank Transfer',
      'transaction_id': 'Transaction ID',
      'send_sms': 'Send SMS',
      'bulk_payment': 'Bulk Payment',
      'payment_history': 'Payment History',
      
      // Reports
      'reports': 'Reports',
      'export_excel': 'Export to Excel',
      'filter': 'Filter',
      'date': 'Date',
      'select_date': 'Select Date',
      
      // Settings
      'settings': 'Settings',
      'rate_chart': 'Rate Chart',
      'language': 'Language',
      'english': 'English',
      'hindi': 'Hindi',
      'dairy_profile': 'Dairy Profile',
      'dairy_name': 'Dairy Name',
      'address': 'Address',
      'contact': 'Contact',
      
      // Mobile Collector
      'collector_mode': 'Collector Mode',
      'collection_only': 'Collection Only',
      'lab_testing': 'Lab Testing',
      'weight_entry': 'Weight Entry',
      'update_lab_values': 'Update Lab Values',
      
      // Common
      'yes': 'Yes',
      'no': 'No',
      'ok': 'OK',
      'search': 'Search',
      'total': 'Total',
      'pending': 'Pending',
      'paid': 'Paid',
      'active': 'Active',
      'inactive': 'Inactive',
      'all': 'All',
      
      // Dashboard specific
      'today': 'Today',
      'todays_progress': "Today's Progress",
      'total_milk': 'Total Milk',
      'quick_actions': 'Quick Actions',
      'collection_trend': 'Collection Trend',
      'vs_yesterday': 'vs yesterday',
      'farmer': 'Farmer',
      'entry': 'Entry',
      'paid_status': 'Paid',
      '7_day_progress': '7 Day Progress',
      'no_data': 'No data',
      'close': 'Close',
      'go_to_billing': 'Go to Billing',
      'milk_collection_title': 'Milk Collection',
      'todays_amount': "Today's Amount",
      'payment_status': 'Payment Status',
      'last_10_days': 'Last 10 Days',
      'paid_farmers': 'Paid Farmers',
      'pending_farmers': 'Pending',
      'above_average': 'above average',
      'below_average': 'below average',
      'no_previous_data': 'No previous data',
      'total_payable_today': 'Total payable today',
      'farmers_paid': 'farmers paid',
    },
    'hi': {
      // Auth
      'login': 'लॉगिन',
      'username': 'यूज़रनेम',
      'password': 'पासवर्ड',
      'admin': 'एडमिन',
      'staff': 'स्टाफ',
      'demo_mode': 'डेमो मोड',
      'logout': 'लॉगआउट',
      
      // Dashboard
      'dashboard': 'डैशबोर्ड',
      'todays_collection': 'आज का संग्रहण',
      'total_liters': 'कुल लीटर',
      'total_amount': 'कुल राशि',
      'total_entries': 'कुल एंट्री',
      'avg_fat': 'औसत फैट',
      'avg_snf': 'औसत SNF',
      'pending_payments': 'बकाया भुगतान',
      'last_7_days': 'पिछले 7 दिन',
      
      // Farmers
      'farmers': 'किसान',
      'add_farmer': 'किसान जोड़ें',
      'farmer_code': 'किसान कोड',
      'farmer_name': 'किसान का नाम',
      'mobile': 'मोबाइल नंबर',
      'cattle_type': 'पशु का प्रकार',
      'cow': 'गाय',
      'buffalo': 'भैंस',
      'fixed_rate': 'फिक्स रेट',
      'use_fixed_rate': 'फिक्स रेट उपयोग करें',
      'current_balance': 'वर्तमान बैलेंस',
      'save': 'सेव करें',
      'cancel': 'रद्द करें',
      'edit': 'संपादित करें',
      'delete': 'डिलीट करें',
      
      // Milk Collection
      'milk_collection': 'दूध संग्रहण',
      'add_entry': 'एंट्री जोड़ें',
      'morning': 'सुबह',
      'evening': 'शाम',
      'shift': 'शिफ्ट',
      'quantity': 'मात्रा (लीटर)',
      'fat': 'फैट %',
      'snf': 'SNF %',
      'rate': 'रेट',
      'amount': 'राशि',
      'submit': 'सबमिट करें',
      'auto_shift': 'ऑटो शिफ्ट',
      
      // Billing
      'billing': 'बिलिंग और भुगतान',
      'generate_bill': 'बिल बनाएं',
      'from_date': 'शुरुआत की तारीख',
      'to_date': 'अंतिम तारीख',
      'advance_deduction': 'अग्रिम कटौती',
      'net_amount': 'नेट राशि',
      'pay_now': 'भुगतान करें',
      'payment_mode': 'भुगतान का तरीका',
      'cash': 'कैश',
      'upi': 'UPI',
      'bank': 'बैंक ट्रांसफर',
      'transaction_id': 'ट्रांजैक्शन ID',
      'send_sms': 'SMS भेजें',
      'bulk_payment': 'बल्क भुगतान',
      'payment_history': 'भुगतान इतिहास',
      
      // Reports
      'reports': 'रिपोर्ट्स',
      'export_excel': 'Excel में निर्यात करें',
      'filter': 'फिल्टर',
      'date': 'तारीख',
      'select_date': 'तारीख चुनें',
      
      // Settings
      'settings': 'सेटिंग्स',
      'rate_chart': 'रेट चार्ट',
      'language': 'भाषा',
      'english': 'English',
      'hindi': 'हिंदी',
      'dairy_profile': 'डेयरी प्रोफाइल',
      'dairy_name': 'डेयरी का नाम',
      'address': 'पता',
      'contact': 'संपर्क',
      
      // Mobile Collector
      'collector_mode': 'कलेक्टर मोड',
      'collection_only': 'केवल संग्रहण',
      'lab_testing': 'लैब टेस्टिंग',
      'weight_entry': 'वजन एंट्री',
      'update_lab_values': 'लैब वैल्यू अपडेट करें',
      
      // Common
      'yes': 'हां',
      'no': 'नहीं',
      'ok': 'ठीक है',
      'search': 'खोजें',
      'total': 'कुल',
      'pending': 'बकाया',
      'paid': 'भुगतान किया',
      'active': 'सक्रिय',
      'inactive': 'निष्क्रिय',
      'all': 'सभी',
      
      // Dashboard specific
      'today': 'आज',
      'todays_progress': 'आज की प्रगति',
      'total_milk': 'कुल दूध',
      'quick_actions': 'त्वरित कार्य',
      'collection_trend': 'संग्रहण रुझान',
      'vs_yesterday': 'कल की तुलना में',
      'farmer': 'किसान',
      'entry': 'एंट्री',
      'paid_status': 'भुगतान',
      '7_day_progress': '7 दिन की प्रगति',
      'no_data': 'कोई डेटा नहीं',
      'close': 'बंद करें',
      'go_to_billing': 'बिलिंग पर जाएं',
      'milk_collection_title': 'दूध संग्रहण',
      'todays_amount': 'आज की राशि',
      'payment_status': 'भुगतान स्थिति',
      'last_10_days': 'पिछले 10 दिन',
      'paid_farmers': 'भुगतान किए गए किसान',
      'pending_farmers': 'बकाया किसान',
      'above_average': 'औसत से ऊपर',
      'below_average': 'औसत से नीचे',
      'no_previous_data': 'कोई पिछला डेटा नहीं',
      'total_payable_today': 'आज देय कुल राशि',
      'farmers_paid': 'किसानों को भुगतान',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ?? 
           _localizedValues['en']?[key] ?? 
           key;
  }
  
  // Check if current language is Hindi
  bool get isHindi => locale.languageCode == 'hi';
  
  // Check if current language is English
  bool get isEnglish => locale.languageCode == 'en';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'hi'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

class LanguageProvider extends ChangeNotifier {
  Locale _locale = const Locale('hi');

  Locale get locale => _locale;

  LanguageProvider() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language_code') ?? 'hi';
    _locale = Locale(languageCode);
    notifyListeners();
  }

  Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', languageCode);
    _locale = Locale(languageCode);
    notifyListeners();
  }

  String tr(BuildContext context, String key) {
    return AppLocalizations.of(context).translate(key);
  }
}
