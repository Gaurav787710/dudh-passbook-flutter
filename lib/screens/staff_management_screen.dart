import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/milk_entry.dart';
import '../services/firestore_sync_service.dart';

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key});

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<Map<String, dynamic>> _staffList = [];
  Map<String, dynamic>? _selectedStaff;
  bool _isLoading = true;
  int? _dairyId;
  String _searchQuery = '';
  String _activeTab = 'PROFILE';

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  // Professional Colors
  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color primaryViolet = Color(0xFF7C3AED);
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _loadUserAndStaff();
  }

  Future<void> _loadUserAndStaff() async {
    final prefs = await SharedPreferences.getInstance();
    _dairyId = prefs.getInt('dairyId');
    _languageCode = prefs.getString('language_code') ?? 'hi';
    await _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper.instance;
      final allUsers = await db.getAllUsers(dairyId: _dairyId);
      _staffList = allUsers.where((u) => u['role'] == 'staff').toList();
    } catch (e) {
      _showSnackBar('Error loading staff: $e', isError: true);
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
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

  List<Map<String, dynamic>> get _filteredStaff {
    if (_searchQuery.isEmpty) return _staffList;
    return _staffList.where((s) =>
      (s['name']?.toString() ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
      (s['mobile']?.toString() ?? '').contains(_searchQuery)
    ).toList();
  }

  void _showAddStaffModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddStaffModal(
        dairyId: _dairyId,
        onSaved: () {
          _loadStaff();
          Navigator.pop(context);
          _showSnackBar('Staff added successfully!');
        },
      ),
    );
  }

  void _showStaffDetails(Map<String, dynamic> staff) {
    setState(() {
      _selectedStaff = staff;
      _activeTab = 'PROFILE';
    });
  }

  void _showDeleteConfirmDialog(Map<String, dynamic> staff) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.delete_rounded, color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Delete Staff?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isHindi ? 'क्या आप वाकई "${staff['name']}" को delete करना चाहते हैं?' : 'Are you sure you want to delete "${staff['name']}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, color: Colors.red.shade600, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This action cannot be undone!',
                      style: TextStyle(fontSize: 12, color: Colors.red),
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
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final db = DatabaseHelper.instance;
                final syncService = FirestoreSyncService.instance;
                
                // Delete from Firestore first
                final staffMobile = staff['mobile'] as String?;
                if (staffMobile != null) {
                  await syncService.deleteStaff(mobile: staffMobile);
                }
                
                // Delete from local database
                await db.deleteUser(staff['id'] as int);
                Navigator.pop(context);
                setState(() => _selectedStaff = null);
                _loadStaff();
                _showSnackBar('Staff deleted successfully!');
              } catch (e) {
                _showSnackBar('Error: $e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEditStaff(Map<String, dynamic> staff) async {
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
                _isHindi ? 'स्टाफ एडिट करें?' : 'Edit Staff?',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          _isHindi
              ? 'क्या आप वाकई "${staff['name'] ?? ''}" की जानकारी एडिट करना चाहते हैं?'
              : 'Are you sure you want to edit "${staff['name'] ?? ''}" details?',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isHindi ? 'रद्द करें' : 'Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(_isHindi ? 'हाँ, एडिट करें' : 'Yes, Edit'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _showEditStaffModal(staff);
    }
  }

  void _showEditStaffModal(Map<String, dynamic> staff) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditStaffModal(
        staff: staff,
        dairyId: _dairyId,
        onSaved: () {
          _loadStaff();
          Navigator.pop(context);
          // Refresh the selected staff
          setState(() => _selectedStaff = null);
          _showSnackBar('Staff updated successfully!');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
            ),
            child: const Icon(Icons.arrow_back_rounded, color: textDark, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Staff Management',
          style: TextStyle(color: textDark, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : isLargeScreen
              ? _buildLargeScreenLayout()
              : _buildMobileLayout(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _showAddStaffModal();
        },
        backgroundColor: primaryBlue,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Add Staff', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildMobileLayout() {
    if (_selectedStaff != null) {
      return _buildStaffDetailsView(_selectedStaff!);
    }
    return _buildStaffListView();
  }

  Widget _buildLargeScreenLayout() {
    return Row(
      children: [
        SizedBox(width: 350, child: _buildStaffListView()),
        Expanded(
          child: _selectedStaff != null
              ? _buildStaffDetailsView(_selectedStaff!)
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline_rounded, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Select a staff member', style: TextStyle(color: Colors.grey.shade500)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStaffListView() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.people_rounded, color: primaryBlue, size: 22),
                        const SizedBox(width: 8),
                        Text('Staff (${_staffList.length})', 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textDark)),
                      ],
                    ),
                    IconButton(
                      onPressed: _showAddStaffModal,
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: primaryBlue, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search staff...',
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                    filled: true,
                    fillColor: bgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _filteredStaff.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No staff found', style: TextStyle(color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _filteredStaff.length,
                    itemBuilder: (context, index) {
                      final staff = _filteredStaff[index];
                      final isSelected = _selectedStaff?['id'] == staff['id'];
                      
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showStaffDetails(staff);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryBlue.withOpacity(0.1) : bgColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isSelected ? primaryBlue : Colors.transparent, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isSelected ? primaryBlue : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    (staff['name']?.toString() ?? '').isNotEmpty
                                        ? staff['name'].toString()[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey.shade600),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(staff['name'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textDark)),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(Icons.phone_outlined, size: 12, color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Text(staff['mobile'] as String, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffDetailsView(Map<String, dynamic> staff) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                if (MediaQuery.of(context).size.width <= 600)
                  IconButton(
                    onPressed: () => setState(() => _selectedStaff = null),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: primaryBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: primaryBlue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: Text(
                      (staff['name']?.toString() ?? '').isNotEmpty
                          ? staff['name'].toString()[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff['name'] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(staff['mobile'] as String, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('ID: ${staff['username'] ?? staff['mobile']}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _confirmEditStaff(staff),
                  icon: Icon(Icons.edit_outlined, color: primaryBlue),
                  tooltip: 'Edit Staff',
                ),
                IconButton(
                  onPressed: () => _showDeleteConfirmDialog(staff),
                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                  tooltip: 'Delete Staff',
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
            child: Row(
              children: [
                _buildTab('PENDING', 'Pending Lab Tests', Icons.science_outlined, primaryViolet),
                _buildTab('PROFILE', 'Profile Details', Icons.person_outline_rounded, primaryBlue),
              ],
            ),
          ),
          Expanded(
            child: _activeTab == 'PENDING' ? _buildPendingEntriesTab() : _buildProfileTab(staff),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String tabId, String label, IconData icon, Color color) {
    final isActive = _activeTab == tabId;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.1) : Colors.transparent,
            border: Border(bottom: BorderSide(color: isActive ? color : Colors.transparent, width: 2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isActive ? color : Colors.grey.shade500),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? color : Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingEntriesTab() {
    return FutureBuilder<List<MilkEntry>>(
      future: DatabaseHelper.instance.getPendingEntries(dairyId: _dairyId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: primaryViolet));
        }

        final pendingEntries = snapshot.data ?? [];

        if (pendingEntries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16)),
                  child: Icon(Icons.check_circle_outline_rounded, size: 32, color: Colors.green.shade400),
                ),
                const SizedBox(height: 16),
                Text(_isHindi ? 'कोई pending entries नहीं' : 'No pending entries', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(
                  _isHindi ? 'सभी दूध एंट्री की FAT/SNF भरी हुई है ✅' : 'All milk entries have FAT/SNF filled ✅',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isHindi
                          ? '${pendingEntries.length} entries में FAT/SNF भरना बाकी है'
                          : '${pendingEntries.length} entries pending FAT/SNF',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: pendingEntries.length,
                itemBuilder: (context, index) {
                  final entry = pendingEntries[index];
                  final dateStr = DateFormat('dd MMM yyyy').format(entry.dateTime);
                  final shiftIcon = entry.shift == 'morning' ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
                  final shiftColor = entry.shift == 'morning' ? Colors.orange : Colors.indigo;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryViolet.withOpacity(0.15)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: primaryViolet.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.science_outlined, color: primaryViolet, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.farmerName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textDark),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text('${entry.quantity.toStringAsFixed(1)}L', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  const SizedBox(width: 8),
                                  Icon(shiftIcon, size: 12, color: shiftColor),
                                  const SizedBox(width: 3),
                                  Text(entry.shift == 'morning' ? 'सुबह' : 'शाम', style: TextStyle(fontSize: 11, color: shiftColor)),
                                  const SizedBox(width: 8),
                                  Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _isHindi ? 'FAT/SNF बाकी' : 'Pending',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProfileTab(Map<String, dynamic> staff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildInfoCard('Personal Information', Icons.person_outline_rounded, [
            _buildInfoRow('Father Name', staff['fatherName'] ?? '-'),
            _buildInfoRow('Email', staff['email'] ?? '-'),
            _buildInfoRow('Address', staff['address'] ?? '-'),
          ]),
          const SizedBox(height: 16),
          _buildInfoCard('Identity & Bank', Icons.credit_card_rounded, [
            _buildInfoRow('Aadhar', staff['aadhar'] ?? '-'),
            _buildInfoRow('PAN', staff['pan'] ?? '-'),
            _buildInfoRow('Bank Account', staff['bankAccount'] ?? '-'),
            _buildInfoRow('IFSC Code', staff['ifsc'] ?? '-'),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: primaryBlue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 18, color: primaryBlue),
                    const SizedBox(width: 8),
                    Text('Login Credentials', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryBlue)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('User ID', style: TextStyle(fontSize: 11, color: primaryBlue.withOpacity(0.7))),
                          const SizedBox(height: 4),
                          Text(staff['username'] ?? staff['mobile'], style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryBlue)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Password', style: TextStyle(fontSize: 11, color: primaryBlue.withOpacity(0.7))),
                          const SizedBox(height: 4),
                          Text(staff['password'] ?? '-', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryBlue)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          Flexible(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textDark), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _AddStaffModal extends StatefulWidget {
  final int? dairyId;
  final VoidCallback onSaved;

  const _AddStaffModal({required this.dairyId, required this.onSaved});

  @override
  State<_AddStaffModal> createState() => _AddStaffModalState();
}

class _AddStaffModalState extends State<_AddStaffModal> {
  final _formKey = GlobalKey<FormState>();
  bool _showPassword = false;
  String? _error;

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _aadharController = TextEditingController();
  final _panController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _ifscController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color bgColor = Color(0xFFF5F7FA);

  @override
  void initState() {
    super.initState();
    _loadLanguage();
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
    _nameController.dispose();
    _fatherNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _aadharController.dispose();
    _panController.dispose();
    _bankAccountController.dispose();
    _ifscController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveStaff() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);

    try {
      final db = DatabaseHelper.instance;
      final syncService = FirestoreSyncService.instance;

      // Check if Firebase is authenticated
      if (!syncService.isAuthenticated) {
        setState(() => _error = 'Not connected to cloud. Please login again.');
        return;
      }

      final mobile = _mobileController.text.trim();
      final password = _passwordController.text;
      final name = _nameController.text.trim();

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      bool loadingDialogOpen = true;

      try {
        // Register staff in Firebase Auth and Firestore
        final result = await syncService.registerStaff(
          name: name,
          mobile: mobile,
          password: password,
          fatherName: _fatherNameController.text.trim().isNotEmpty ? _fatherNameController.text.trim() : null,
          email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
          address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
          aadhar: _aadharController.text.trim().isNotEmpty ? _aadharController.text.trim() : null,
          pan: _panController.text.trim().isNotEmpty ? _panController.text.trim() : null,
          bankAccount: _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
          ifsc: _ifscController.text.trim().isNotEmpty ? _ifscController.text.trim() : null,
        );

        // Close loading dialog
        if (mounted && loadingDialogOpen) {
          Navigator.of(context).pop();
          loadingDialogOpen = false;
        }

        if (result['success'] == true) {
          // Also save to local database for offline access
          await db.createUser(
            name: name,
            mobile: mobile,
            password: password,
            role: 'staff',
            dairyId: widget.dairyId,
            username: mobile,
            fatherName: _fatherNameController.text.trim().isNotEmpty ? _fatherNameController.text.trim() : null,
            email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
            address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
            aadhar: _aadharController.text.trim().isNotEmpty ? _aadharController.text.trim() : null,
            pan: _panController.text.trim().isNotEmpty ? _panController.text.trim() : null,
            bankAccount: _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
            ifsc: _ifscController.text.trim().isNotEmpty ? _ifscController.text.trim() : null,
          );

          widget.onSaved();
        } else {
          if (mounted) setState(() => _error = result['error'] ?? 'Failed to create staff');
        }
      } catch (e) {
        // Close loading dialog if still open
        if (mounted && loadingDialogOpen) {
          Navigator.of(context).pop();
          loadingDialogOpen = false;
        }
        if (mounted) setState(() => _error = 'Error: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_isHindi ? 'नया स्टाफ जोड़ें' : 'Add New Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildSectionHeader(_isHindi ? 'व्यक्तिगत जानकारी' : 'Personal Information'),
                  const SizedBox(height: 12),
                  _buildTextField(_nameController, _isHindi ? 'पूरा नाम *' : 'Full Name *', Icons.person_outline_rounded, required: true),
                  const SizedBox(height: 12),
                  _buildTextField(_fatherNameController, _isHindi ? 'पिता का नाम' : "Father's Name", Icons.family_restroom_rounded),
                  const SizedBox(height: 12),
                  _buildTextField(_mobileController, _isHindi ? 'मोबाइल *' : 'Mobile *', Icons.phone_outlined, keyboardType: TextInputType.phone, required: true, maxLength: 10),
                  const SizedBox(height: 12),
                  _buildTextField(_emailController, 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  _buildTextField(_addressController, _isHindi ? 'पता' : 'Address', Icons.location_on_outlined, maxLines: 2),
                  
                  const SizedBox(height: 24),
                  _buildSectionHeader(_isHindi ? 'पहचान और बैंक' : 'Identity & Bank'),
                  const SizedBox(height: 12),
                  _buildTextField(_aadharController, _isHindi ? 'आधार नंबर' : 'Aadhar Number', Icons.credit_card_rounded, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _buildTextField(_panController, _isHindi ? 'पैन कार्ड' : 'PAN Card', Icons.credit_card_rounded),
                  const SizedBox(height: 12),
                  _buildTextField(_bankAccountController, _isHindi ? 'बैंक खाता' : 'Bank Account', Icons.account_balance_rounded, keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  _buildTextField(_ifscController, 'IFSC Code', Icons.account_balance_rounded),
                  
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryBlue.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primaryBlue.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline_rounded, color: primaryBlue, size: 18),
                            const SizedBox(width: 8),
                            Text('App Login Credentials', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryBlue)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.badge_outlined, size: 20, color: primaryBlue),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Staff ID', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _mobileController.text.isNotEmpty ? _mobileController.text : 'Mobile number will be used as ID',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _mobileController.text.isNotEmpty ? Colors.black87 : Colors.grey.shade400),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Staff ID = Mobile Number (auto-set)', style: TextStyle(fontSize: 11, color: primaryBlue, fontStyle: FontStyle.italic)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 20),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                            helperText: _isHindi ? 'कम से कम 8 अक्षर, A-Z, a-z, 0-9, विशेष चिह्न (!@#\$%)' : 'Min 8 chars: A-Z, a-z, 0-9, special (!@#\$%)',
                            helperMaxLines: 2,
                          ),
                          validator: (v) {
                            if (v?.isEmpty ?? true) return 'Password is required';
                            if (v!.length < 8) return 'Minimum 8 characters required';
                            if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must have at least 1 uppercase letter (A-Z)';
                            if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must have at least 1 lowercase letter (a-z)';
                            if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must have at least 1 number (0-9)';
                            if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(v)) return 'Must have at least 1 special character (!@#\$%^&*)';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(_isHindi ? 'Staff को Mobile Number और Password बताएं।' : 'Share Mobile Number and Password with staff for app login.', style: TextStyle(fontSize: 12, color: primaryBlue.withOpacity(0.8))),
                      ],
                    ),
                  ),
                  
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade600, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _saveStaff,
                          style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: Text(_isHindi ? 'सेव करें' : 'Save Staff', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700, letterSpacing: 0.5)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool required = false, TextInputType? keyboardType, int maxLines = 1, int? maxLength, Color? fillColor}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: fillColor ?? bgColor,
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      ),
      validator: required ? (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        return null;
      } : null,
    );
  }
}

// =============================================
// EDIT STAFF MODAL
// =============================================
class _EditStaffModal extends StatefulWidget {
  final Map<String, dynamic> staff;
  final int? dairyId;
  final VoidCallback onSaved;

  const _EditStaffModal({required this.staff, required this.dairyId, required this.onSaved});

  @override
  State<_EditStaffModal> createState() => _EditStaffModalState();
}

class _EditStaffModalState extends State<_EditStaffModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _aadharController;
  late final TextEditingController _panController;
  late final TextEditingController _bankAccountController;
  late final TextEditingController _ifscController;
  late final TextEditingController _passwordController;
  String? _error;
  bool _isLoading = false;

  String _languageCode = 'hi';
  bool get _isHindi => _languageCode == 'hi';

  static const Color primaryBlue = Color(0xFF1976D2);
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color textDark = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _nameController = TextEditingController(text: widget.staff['name'] ?? '');
    _fatherNameController = TextEditingController(text: widget.staff['fatherName'] ?? '');
    _mobileController = TextEditingController(text: widget.staff['mobile'] ?? '');
    _emailController = TextEditingController(text: widget.staff['email'] ?? '');
    _addressController = TextEditingController(text: widget.staff['address'] ?? '');
    _aadharController = TextEditingController(text: widget.staff['aadhar'] ?? '');
    _panController = TextEditingController(text: widget.staff['pan'] ?? '');
    _bankAccountController = TextEditingController(text: widget.staff['bankAccount'] ?? '');
    _ifscController = TextEditingController(text: widget.staff['ifsc'] ?? '');
    _passwordController = TextEditingController();
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
    _nameController.dispose();
    _fatherNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _aadharController.dispose();
    _panController.dispose();
    _bankAccountController.dispose();
    _ifscController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _updateStaff() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = DatabaseHelper.instance;
      final syncService = FirestoreSyncService.instance;

      // BUG FIX #3: Check network/auth before proceeding (prevents infinite loading)
      if (!syncService.isAuthenticated) {
        setState(() {
          _error = _isHindi
              ? 'इंटरनेट या लॉगिन कनेक्शन नहीं है। कृपया दोबारा लॉगिन करें।'
              : 'Not connected to cloud. Please login again.';
          _isLoading = false;
        });
        return;
      }
      final mobile = widget.staff['mobile'] as String;
      final name = _nameController.text.trim();

      // Update in Firestore
      final result = await syncService.updateStaff(
        mobile: mobile,
        name: name,
        fatherName: _fatherNameController.text.trim().isNotEmpty ? _fatherNameController.text.trim() : null,
        email: _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        aadhar: _aadharController.text.trim().isNotEmpty ? _aadharController.text.trim() : null,
        pan: _panController.text.trim().isNotEmpty ? _panController.text.trim() : null,
        bankAccount: _bankAccountController.text.trim().isNotEmpty ? _bankAccountController.text.trim() : null,
        ifsc: _ifscController.text.trim().isNotEmpty ? _ifscController.text.trim() : null,
        newPassword: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      );

      if (result['success'] == true) {
        // Also update local database
        final updateData = <String, dynamic>{
          'name': name,
        };
        if (_fatherNameController.text.trim().isNotEmpty) updateData['fatherName'] = _fatherNameController.text.trim();
        if (_emailController.text.trim().isNotEmpty) updateData['email'] = _emailController.text.trim();
        if (_addressController.text.trim().isNotEmpty) updateData['address'] = _addressController.text.trim();
        if (_aadharController.text.trim().isNotEmpty) updateData['aadhar'] = _aadharController.text.trim();
        if (_panController.text.trim().isNotEmpty) updateData['pan'] = _panController.text.trim();
        if (_bankAccountController.text.trim().isNotEmpty) updateData['bankAccount'] = _bankAccountController.text.trim();
        if (_ifscController.text.trim().isNotEmpty) updateData['ifsc'] = _ifscController.text.trim();
        if (_passwordController.text.isNotEmpty) updateData['password'] = _passwordController.text;
        
        await db.updateUser(widget.staff['id'] as int, updateData);

        widget.onSaved();
      } else {
        if (mounted) setState(() => _error = result['error'] ?? 'Failed to update staff');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: primaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_rounded, color: primaryBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Edit Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textDark)),
                      Text(_isHindi ? 'स्टाफ विवरण अपडेट करें' : 'Update staff details', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                ],
              ),
            ),
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('BASIC INFORMATION'),
                    const SizedBox(height: 12),
                    _buildTextField(_nameController, _isHindi ? 'नाम *' : 'Name *', Icons.person_outline_rounded, required: true),
                    const SizedBox(height: 12),
                    _buildTextField(_fatherNameController, _isHindi ? 'पिता का नाम' : 'Father\'s Name', Icons.people_outline_rounded),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _mobileController,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: _isHindi ? 'मोबाइल नंबर (बदला नहीं जा सकता)' : 'Mobile Number (Cannot change)',
                        prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(_emailController, _isHindi ? 'ईमेल' : 'Email', Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    _buildTextField(_addressController, _isHindi ? 'पता' : 'Address', Icons.location_on_outlined, maxLines: 2),
                    const SizedBox(height: 24),
                    _buildSectionHeader('IDENTITY & BANK DETAILS'),
                    const SizedBox(height: 12),
                    _buildTextField(_aadharController, _isHindi ? 'आधार नंबर' : 'Aadhar Number', Icons.credit_card_rounded, keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    _buildTextField(_panController, _isHindi ? 'पैन कार्ड' : 'PAN Card', Icons.credit_card_rounded),
                    const SizedBox(height: 12),
                    _buildTextField(_bankAccountController, _isHindi ? 'बैंक खाता' : 'Bank Account', Icons.account_balance_outlined, keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    _buildTextField(_ifscController, _isHindi ? 'IFSC कोड' : 'IFSC Code', Icons.numbers_rounded),
                    const SizedBox(height: 24),
                    _buildSectionHeader('PASSWORD (Leave blank to keep current)'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: _isHindi ? 'नया पासवर्ड' : 'New Password',
                        labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                        filled: true,
                        fillColor: bgColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                        helperText: _isHindi ? 'कम से कम 8 अक्षर, A-Z, a-z, 0-9, विशेष चिह्न' : 'Min 8 chars, A-Z, a-z, 0-9, special char',
                        helperMaxLines: 2,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null; // optional on edit
                        if (v.length < 8) return 'Minimum 8 characters required';
                        if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Must have at least 1 uppercase letter (A-Z)';
                        if (!RegExp(r'[a-z]').hasMatch(v)) return 'Must have at least 1 lowercase letter (a-z)';
                        if (!RegExp(r'[0-9]').hasMatch(v)) return 'Must have at least 1 number (0-9)';
                        if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(v)) return 'Must have at least 1 special character';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: Colors.grey.shade300)),
                            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _updateStaff,
                            style: ElevatedButton.styleFrom(backgroundColor: primaryBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: _isLoading 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(_isHindi ? 'अपडेट करें' : 'Update Staff', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700, letterSpacing: 0.5)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool required = false, TextInputType? keyboardType, int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: bgColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      ),
      validator: required ? (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        return null;
      } : null,
    );
  }
}
