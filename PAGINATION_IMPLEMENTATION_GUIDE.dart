// PAGINATION MIXIN - Ready to add to Entry History Screen
// File: lib/mixins/pagination_mixin.dart

import 'package:flutter/material.dart';
import '../models/milk_entry.dart';
import '../models/payment.dart';

/// Pagination state manager for memory-efficient loading of large datasets
mixin PaginationMixin<T> on State {
  // Pagination state
  late ScrollController scrollController;
  List<T> displayList = [];
  Set<String> loadedIds = {};
  bool hasMore = true;
  int pageSize = 30;
  dynamic paginationKey; // Last Firestore document snapshot
  bool isPaginating = false;
  int totalLoaded = 0;

  @override
  void initState() {
    super.initState();
    scrollController = ScrollController();
    scrollController.addListener(_onScrollEnd);
  }

  @override
  void dispose() {
    scrollController.dispose();
    clearPagination();
    super.dispose();
  }

  /// Reset pagination when filter changes
  void resetPagination() {
    displayList.clear();
    loadedIds.clear();
    paginationKey = null;
    hasMore = true;
    totalLoaded = 0;
  }

  /// Check if reached end of scroll and load more
  void _onScrollEnd() {
    if (scrollController.position.extentAfter < 500 && hasMore && !isPaginating) {
      loadNextBatch();
    }
  }

  /// Override in subclass to implement actual data loading
  Future<void> loadNextBatch() async {
    // Implemented in entry_history_screen.dart
  }

  /// Safely append batch, preventing duplicates
  void appendBatch(List<T> newBatch, Function(T) getId) {
    if (isPaginating) return;

    try {
      isPaginating = true;
      for (var item in newBatch) {
        String id = getId(item);
        if (!loadedIds.contains(id)) {
          displayList.add(item);
          loadedIds.add(id);
          totalLoaded++;
        }
      }
      // Update last document key for next query
      if (newBatch.isNotEmpty) {
        paginationKey = newBatch.last; // Store for cursor continuation
      }
      if (newBatch.length < pageSize) {
        hasMore = false; // Less than a full page means we're at the end
      }
    } finally {
      isPaginating = false;
    }
  }

  /// Clear all pagination state
  void clearPagination() {
    displayList.clear();
    loadedIds.clear();
    paginationKey = null;
    hasMore = true;
    totalLoaded = 0;
  }

  /// Debug info
  String getPaginationState() => 
    'Loaded: $totalLoaded | HasMore: $hasMore | IsPaginating: $isPaginating';
}

---

// USAGE PATTERN: Entry History Screen
// File: lib/screens/entry_history_screen.dart (modifications)

class _EntryHistoryScreenState extends State<EntryHistoryScreen>
    with SingleTickerProviderStateMixin, PaginationMixin<MilkEntry> {
  
  // ... existing code ...

  // PAGINATION SPECIFIC
  late ScrollController _scrollController;
  QueryDocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMoreEntries = true;
  bool _isPaginating = false;
  int _paginationPageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _scrollController = ScrollController();
    _scrollController.addListener(_onListScroll);
    
    if (widget.initialFarmerId != null) {
      _selectedFilter = 'all';
      _selectedFarmerId = widget.initialFarmerId;
    }
    _loadUserAndEntries();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Called when filter changes - reset pagination
  Future<void> _onFilterChanged(String newFilter) async {
    _selectedFilter = newFilter;
    _entries.clear();
    _lastDoc = null;
    _hasMoreEntries = true;
    _isPaginating = false;
    await _loadEntries();
    if (mounted) setState(() {});
  }

  /// Load initial entries based on filter
  Future<void> _loadEntries() async {
    if (_isPaginating) return;
    
    setState(() => _isLoading = true);
    try {
      DateTime? startDate;
      DateTime? endDate = DateTime.now();

      // Define date range based on filter
      if (_selectedFilter == 'today') {
        startDate = DateTime(endDate.year, endDate.month, endDate.day);
      } else if (_selectedFilter == 'week') {
        startDate = endDate.subtract(const Duration(days: 7));
      } else if (_selectedFilter == 'date') {
        startDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );
        endDate = startDate.add(const Duration(days: 1));
      } else {
        // 'all' - use pagination, start from epoch
        startDate = DateTime(2020);
      }

      int? filterUserId;
      if (_userRole == 'staff') {
        filterUserId = _userId;
      } else if (_selectedStaffId != null) {
        filterUserId = _selectedStaffId;
      }

      // If 'all' filter, use pagination query; otherwise use standard query
      if (_selectedFilter == 'all') {
        await _loadEntriesPaginated(startDate, endDate, filterUserId);
      } else {
        // For limited date ranges, load all at once (no pagination)
        _entries = await _db.getMilkEntriesForBilling(
          startDate: startDate,
          endDate: endDate,
          createdByUserId: filterUserId,
          dairyId: _dairyId,
        );
        _hasMoreEntries = false; // No more pagination for limited ranges
      }

      _entries = _entries.where((e) => !e.isPending).toList();

      // Filter by farmer if selected
      if (_selectedFarmerId != null) {
        _entries = _entries
            .where((e) => e.farmerId == _selectedFarmerId)
            .toList();
      }

      // Cache totals
      _cachedTotalLiters = _entries.fold<double>(0, (sum, e) => sum + e.quantity);
      _cachedTotalAmount = _entries.fold<double>(0, (sum, e) => sum + e.amount);

    } catch (e) {
      debugPrint('Error loading entries: $e');
      _entries = [];
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  /// Load entries with pagination for 'all' filter
  Future<void> _loadEntriesPaginated(
    DateTime startDate,
    DateTime endDate,
    int? filterUserId,
  ) async {
    try {
      _isPaginating = true;
      
      // Build Firestore query with limit
      var query = _syncService.db
          .collection('entries')
          .where('dairyId', isEqualTo: _dairyId)
          .orderBy('dateTime', descending: true)
          .limit(_paginationPageSize);

      // Apply farmer filter if needed
      if (_selectedFarmerId != null) {
        query = query.where('farmerId', isEqualTo: _selectedFarmerId);
      }

      // Apply user filter if needed
      if (filterUserId != null) {
        query = query.where('createdByUserId', isEqualTo: filterUserId);
      }

      QuerySnapshot querySnapshot = await query.get();
      
      List<MilkEntry> batch = querySnapshot.docs
          .map((doc) => MilkEntry.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // Store first batch
      _entries = batch;
      
      // Save last doc for pagination
      if (querySnapshot.docs.isNotEmpty) {
        _lastDoc = querySnapshot.docs.last;
      }

      // Check if more entries available
      _hasMoreEntries = batch.length == _paginationPageSize;

      debugPrint('Pagination: Loaded ${batch.length} entries, hasMore: $_hasMoreEntries');

    } catch (e) {
      debugPrint('Error in pagination: $e');
      _entries = [];
      _hasMoreEntries = false;
    } finally {
      _isPaginating = false;
    }
  }

  /// Load next batch when user scrolls to bottom
  Future<void> _loadNextBatchPaginated(int? filterUserId) async {
    if (_isPaginating || !_hasMoreEntries || _lastDoc == null) return;

    try {
      _isPaginating = true;

      var query = _syncService.db
          .collection('entries')
          .where('dairyId', isEqualTo: _dairyId)
          .orderBy('dateTime', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_paginationPageSize);

      if (_selectedFarmerId != null) {
        query = query.where('farmerId', isEqualTo: _selectedFarmerId);
      }

      if (filterUserId != null) {
        query = query.where('createdByUserId', isEqualTo: filterUserId);
      }

      QuerySnapshot querySnapshot = await query.get();
      
      List<MilkEntry> batch = querySnapshot.docs
          .map((doc) => MilkEntry.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      if (batch.isNotEmpty) {
        // Append safely without duplicates
        Set<int> existingIds = _entries.map((e) => e.id ?? 0).toSet();
        for (var entry in batch) {
          if (entry.id != null && !existingIds.contains(entry.id)) {
            _entries.add(entry);
            existingIds.add(entry.id!);
          }
        }

        // Update totals
        _cachedTotalLiters = _entries.fold<double>(0, (sum, e) => sum + e.quantity);
        _cachedTotalAmount = _entries.fold<double>(0, (sum, e) => sum + e.amount);

        _lastDoc = querySnapshot.docs.last;
        _hasMoreEntries = batch.length == _paginationPageSize;

        debugPrint('Pagination: Loaded ${batch.length} more entries, total: ${_entries.length}');

        if (mounted) setState(() {});
      } else {
        _hasMoreEntries = false;
      }

    } catch (e) {
      debugPrint('Error loading next batch: $e');
    } finally {
      _isPaginating = false;
    }
  }

  /// Scroll listener - detect when user reaches bottom
  void _onListScroll() {
    if (_scrollController.position.extentAfter < 500 &&
        _hasMoreEntries &&
        !_isPaginating &&
        _selectedFilter == 'all') {
      int? filterUserId;
      if (_userRole == 'staff') {
        filterUserId = _userId;
      } else if (_selectedStaffId != null) {
        filterUserId = _selectedStaffId;
      }
      _loadNextBatchPaginated(filterUserId);
    }
  }

  // Then in your ListView.builder:
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        controller: _scrollController,
        itemCount: _entries.length + (_hasMoreEntries ? 1 : 0),
        itemBuilder: (context, index) {
          // Loading indicator at bottom
          if (index == _entries.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  color: primaryGreen,
                ),
              ),
            );
          }

          final entry = _entries[index];
          return _buildEntryCard(entry);
        },
      ),
    );
  }
}

---

// PAYMENT MANAGER SCREEN - History Tab Pagination
// File: lib/screens/payment_manager_screen.dart (modifications)

class _PaymentManagerScreenState extends State<PaymentManagerScreen> 
    with SingleTickerProviderStateMixin {
  
  // ... existing code ...

  // PAGINATION
  late ScrollController _historyScrollController;
  List<Payment> _historyPayments = [];
  List<Payment> _filteredHistoryPayments = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _historyLastDoc;
  bool _historyHasMore = true;
  bool _historyIsPaginating = false;
  static const int _historyPageSize = 50;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _historyScrollController = ScrollController();
    _historyScrollController.addListener(_onHistoryScroll);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  /// Load initial history
  Future<void> _loadHistoryPayments() async {
    if (_historyIsPaginating) return;

    try {
      _historyIsPaginating = true;

      var query = _syncService.db
          .collection('payments')
          .where('dairyId', isEqualTo: _dairyId)
          .orderBy('dateTime', descending: true)
          .limit(_historyPageSize);

      QuerySnapshot querySnapshot = await query.get();

      List<Payment> batch = querySnapshot.docs
          .map((doc) => Payment.fromFirestore(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      _historyPayments = batch;
      _applyHistoryFilter();

      if (querySnapshot.docs.isNotEmpty) {
        _historyLastDoc = querySnapshot.docs.last;
      }

      _historyHasMore = batch.length == _historyPageSize;

      if (mounted) setState(() {});

      debugPrint('History: Loaded ${batch.length} payments');

    } catch (e) {
      debugPrint('Error loading history: $e');
      _historyPayments = [];
    } finally {
      _historyIsPaginating = false;
    }
  }

  /// Load next batch of history
  Future<void> _loadMoreHistoryPayments() async {
    if (_historyIsPaginating || !_historyHasMore || _historyLastDoc == null) return;

    try {
      _historyIsPaginating = true;

      var query = _syncService.db
          .collection('payments')
          .where('dairyId', isEqualTo: _dairyId)
          .orderBy('dateTime', descending: true)
          .startAfterDocument(_historyLastDoc!)
          .limit(_historyPageSize);

      QuerySnapshot querySnapshot = await query.get();

      List<Payment> batch = querySnapshot.docs
          .map((doc) => Payment.fromFirestore(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // Append safely
      Set<String> existingIds = _historyPayments.map((p) => p.id).toSet();
      for (var payment in batch) {
        if (!existingIds.contains(payment.id)) {
          _historyPayments.add(payment);
        }
      }

      _applyHistoryFilter();

      _historyLastDoc = querySnapshot.docs.last;
      _historyHasMore = batch.length == _historyPageSize;

      if (mounted) setState(() {});

      debugPrint('History: Loaded ${batch.length} more payments');

    } catch (e) {
      debugPrint('Error loading more history: $e');
    } finally {
      _historyIsPaginating = false;
    }
  }

  /// Scroll listener
  void _onHistoryScroll() {
    if (_historyScrollController.position.extentAfter < 500 &&
        _historyHasMore &&
        !_historyIsPaginating) {
      _loadMoreHistoryPayments();
    }
  }

  /// Apply filter to history
  void _applyHistoryFilter() {
    if (_historyFilter == 'ALL') {
      _filteredHistoryPayments = _historyPayments;
    } else {
      _filteredHistoryPayments = _historyPayments
          .where((p) => p.type == _historyFilter)
          .toList();
    }
  }

  // Build history list view
  Widget _buildHistoryList() {
    return _filteredHistoryPayments.isEmpty
        ? Center(
            child: Text(_isHindi ? 'कोई payment नहीं' : 'No payments'),
          )
        : ListView.builder(
            controller: _historyScrollController,
            itemCount: _filteredHistoryPayments.length + 
                (_historyHasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _filteredHistoryPayments.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                      child: CircularProgressIndicator(color: primaryGreen)),
                );
              }
              final payment = _filteredHistoryPayments[index];
              return _buildPaymentHistoryCard(payment);
            },
          );
  }
}

---

// FIRESTORE EXTENSION - Add to MilkEntry model
// File: lib/models/milk_entry.dart (add method)

extension FirestoreConversion on MilkEntry {
  static MilkEntry fromFirestore(Map<String, dynamic> data, String docId) {
    return MilkEntry(
      id: int.tryParse(docId) ?? 0,
      farmerId: data['farmerId'] as int? ?? 0,
      farmerCode: data['farmerCode'] as String? ?? '',
      farmerName: data['farmerName'] as String? ?? '',
      shift: data['shift'] as String? ?? 'morning',
      dateTime: DateTime.parse(data['dateTime'] as String? ?? ''),
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      fat: (data['fat'] as num?)?.toDouble() ?? 0,
      snf: (data['snf'] as num?)?.toDouble() ?? 0,
      rate: (data['rate'] as num?)?.toDouble() ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      cattleType: data['cattleType'] as String? ?? 'cow',
      createdByUserId: data['createdByUserId'] as int? ?? 0,
      dairyId: data['dairyId'] as int? ?? 0,
      isPending: data['isPending'] as bool? ?? false,
      notes: data['notes'] as String? ?? '',
    );
  }
}

---

// BILLING SCREEN - NO CHANGES NEEDED
// File: lib/screens/payment_manager_screen.dart - Bill tab

// SAFETY: Billing ALWAYS loads full data
Future<void> _computeBillingForFarmer(Farmer farmer) async {
  try {
    // Load FULL entries for selected date range - NO LIMIT
    final entries = await _db.getMilkEntriesForBilling(
      startDate: _startDate,
      endDate: _endDate,
      farmerCode: farmer.code,
      dairyId: _dairyId,
    );

    // Calculate totals from FULL data
    final totalMilk = entries.fold<double>(0, (sum, e) => sum + e.quantity);
    final totalAmount = entries.fold<double>(0, (sum, e) => sum + e.amount);
    final totalAdvance = ... // from payments for this farmer

    // Create bill with complete data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          farmer: farmer,
          entries: entries, // FULL DATASET
          startDate: _startDate,
          endDate: _endDate,
          totalMilk: totalMilk,
          totalAmount: totalAmount,
          totalAdvance: totalAdvance,
          // ... more fields
        ),
      ),
    );
  } catch (e) {
    debugPrint('Error computing bill: $e');
  }
}
