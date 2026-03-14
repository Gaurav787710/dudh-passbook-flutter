# Performance Optimization - Safety Patterns & Verification

## ANTI-PATTERNS TO AVOID

### ❌ NEVER DO THIS

```dart
// BAD: Loading full dataset without limit
List<Payment> payments = await _db.getAllPayments(); // No limit!

// BAD: Reloading entire list on every scroll
void _onScroll() {
  _loadPayments(); // This reloads EVERYTHING
}

// BAD: Nested setState rebuilds
Future<void> _addToList(Item item) async {
  setState(() => items.add(item)); // Rebuild 1
  final updated = await compute(item); // Heavy computation
  setState(() => items[i] = updated); // Rebuild 2
}

// BAD: Not tracking loaded items, causing duplicates
void appendBatch(List<Item> batch) {
  items.addAll(batch); // Duplicates if called twice!
}

// BAD: Not disposing resources
@override
void dispose() {
  // scrollController.dispose(); // FORGOT THIS - MEMORY LEAK
  super.dispose();
}

// BAD: Querying without dairyId isolation
Query query = db.collection('entries').where('dateTime', ...); 
// Other dairies see this data!

// BAD: Billing using paginated entries
List<Entry> displayEntries = ...; // Only loaded 30 entries
double total = displayEntries.fold(...); // WRONG TOTAL!

// BAD: Not resetting pagination on filter change
void onFilterChanged() {
  _selectedFilter = newFilter;
  // _lastDoc should be null here!
  _loadNextBatch(); // Will use old pagination key!
}
```

---

## ✅ RECOMMENDED PATTERNS

### Pattern 1: Safe Pagination Setup

```dart
class SafePaginationState extends State {
  // Data
  List<MilkEntry> _displayList = [];
  Set<String> _loadedIds = {}; // Track by ID
  
  // Pagination state
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isPaginating = false;
  int _pageSize = 30;

  // Controllers
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_checkScrollEnd);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose(); // IMPORTANT
    _displayList.clear();
    _loadedIds.clear();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    resetPagination(); // Clear state
    final batch = await _fetchBatch(null);
    _appendBatch(batch);
  }

  void _checkScrollEnd() {
    // Trigger at 500 pixels from end
    if (_scrollController.position.extentAfter < 500 &&
        _hasMore &&
        !_isPaginating) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isPaginating || !_hasMore || _lastDoc == null) return;
    
    setState(() => _isPaginating = true);
    final batch = await _fetchBatch(_lastDoc);
    _appendBatch(batch);
    setState(() => _isPaginating = false);
  }

  void _appendBatch(List<MilkEntry> batch) {
    for (var item in batch) {
      if (!_loadedIds.contains(item.id)) {
        _displayList.add(item);
        _loadedIds.add(item.id ?? '');
      }
    }
    
    if (batch.isNotEmpty) {
      _lastDoc = batch.last as DocumentSnapshot?;
    }
    
    if (batch.length < _pageSize) {
      _hasMore = false;
    }
  }

  void resetPagination() {
    _displayList.clear();
    _loadedIds.clear();
    _lastDoc = null;
    _hasMore = true;
    _isPaginating = false;
  }

  Future<List<MilkEntry>> _fetchBatch(DocumentSnapshot? cursor) async {
    // Firestore query
    var query = db.collection('entries')
        .where('dairyId', isEqualTo: _dairyId)
        .orderBy('dateTime', descending: true)
        .limit(_pageSize);

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }

    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => MilkEntry.fromFirestore(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }
}
```

### Pattern 2: Filter Change Safety

```dart
// When user changes filter, RESET pagination
Future<void> _onFilterChange(String newFilter) async {
  // STEP 1: Clear pagination state
  _displayList.clear();
  _loadedIds.clear();
  _lastDoc = null; // IMPORTANT: Reset cursor
  _hasMore = true;
  _isPaginating = false;

  // STEP 2: Update filter
  _selectedFilter = newFilter;

  // STEP 3: Load new data
  await _loadInitial();
  
  if (mounted) setState(() {});
}
```

### Pattern 3: Billing Data Safety

```dart
// Billing MUST use full dataset, never paginated
Future<void> openBill(Farmer farmer) async {
  try {
    // Load COMPLETE data for calculation
    final fullEntries = await _db.getMilkEntriesForBilling(
      startDate: _billStartDate,
      endDate: _billEndDate,
      farmerCode: farmer.code,
      dairyId: _dairyId,
      // NO LIMIT - get all
    );

    // Calculate from full data
    final totals = _calculateTotals(fullEntries);

    // Pass full data to billing screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BillPreviewScreen(
          entries: fullEntries, // FULL DATA
          totalMilk: totals['milk'],
          totalAmount: totals['amount'],
          // ... other fields
        ),
      ),
    );
  } catch (e) {
    showError('Error generating bill: $e');
  }
}
```

### Pattern 4: Real-time Sync Safety

```dart
// When new entry added via stream, don't break pagination
void _onNewEntryFromStream(MilkEntry newEntry) {
  // Check if matches current filter
  if (_matchesCurrentFilter(newEntry)) {
    // Insert at top (newest first)
    if (!_loadedIds.contains(newEntry.id)) {
      _displayList.insert(0, newEntry);
      _loadedIds.add(newEntry.id ?? '');
      
      // Update totals silently
      _cachedTotals['milk'] += newEntry.quantity;
      _cachedTotals['amount'] += newEntry.amount;
      
      if (mounted) setState(() {});
    }
  }
}

bool _matchesCurrentFilter(MilkEntry entry) {
  if (_selectedFilter == 'today') {
    return _isToday(entry.dateTime);
  } else if (_selectedFilter == 'week') {
    return _isThisWeek(entry.dateTime);
  }
  return true; // Matches 'all'
}
```

### Pattern 5: Memory Safety

```dart
// Audit before submitting
class MemorySafeEntry extends State {
  @override
  void initState() {
    super.initState();
    // Dispose will be called on pop
  }

  @override
  void dispose() {
    // CHECKLIST:
    _scrollController.dispose(); // ✓ Free scroll listener
    _textControllers.forEach((c) => c.dispose()); // ✓ Free text
    _displayList.clear(); // ✓ Clear data
    _loadedIds.clear(); // ✓ Clear tracking
    _lastDoc = null; // ✓ Clear reference
    super.dispose();
  }
}
```

---

## VERIFICATION CHECKLIST

### Before Deployment

- [ ] **Entry History**: 
  - [ ] Today filter loads < 1s
  - [ ] Week filter shows all 7 days
  - [ ] "All" filter shows first 30 entries
  - [ ] Scroll to bottom loads next batch
  - [ ] No duplicate entries in list

- [ ] **Payment History**:
  - [ ] Type filter works correctly
  - [ ] Pagination loads next 50 on scroll
  - [ ] No duplicate payments
  - [ ] Filter change resets pagination

- [ ] **Billing Screen**:
  - [ ] Bill uses FULL entry data
  - [ ] Totals are accurate (not partial)
  - [ ] Billing works even with 1000+ entries
  - [ ] No lag when opening bill

- [ ] **Memory**:
  - [ ] App memory < 100MB with 1000 entries
  - [ ] No memory leak after closing screens
  - [ ] Scroll remains 60 FPS with pagination
  - [ ] No frame drops during load

- [ ] **Real-time Sync**:
  - [ ] New entries appear at top
  - [ ] Pagination state preserved
  - [ ] No duplicates on sync
  - [ ] Totals update correctly

- [ ] **Multi-device Safety**:
  - [ ] Pagination works on low-end phones
  - [ ] Works with slow internet
  - [ ] Works with Firestore offline
  - [ ] No crashes with malformed data

- [ ] **Code Quality**:
  - [ ] All controllers disposed
  - [ ] No nested setState calls
  - [ ] No infinite loops
  - [ ] No console errors

---

## PERFORMANCE TEST PROCEDURE

### Test 1: Initial Load Speed

```
1. Open Entry History
2. Check app startup time (target: < 1s for today)
3. Verify first 30 entries display
4. Check memory usage
```

### Test 2: Pagination Load

```
1. Open "All" filter
2. Scroll to bottom
3. Measure load time for next batch (target: < 1s)
4. Verify no duplicate entries
5. Total count increases correctly
```

### Test 3: Filter Change

```
1. Load "All" filter (paginated)
2. Switch to "Today" filter
3. Verify old pagination state cleared
4. Verify today's entries loaded
5. No leftover UI elements
```

### Test 4: Memory Endurance

```
1. Open entry history
2. Scroll through 100 batches (3000+ entries)
3. Monitor memory increase (should be linear, < 150MB)
4. Close and reopen screen
5. Memory should return to baseline
```

### Test 5: Real-time Sync

```
1. Open entry history on Device A
2. Add new entry on Device B
3. Verify new entry appears at top of list on A
4. Verify no duplicates
5. Verify pagination state unchanged
```

---

## COMMON ISSUES & FIXES

### Issue: Duplicates in List

**Symptom**: Same entry appears twice after pagination

**Root Cause**: Not tracking loaded IDs

**Fix**:
```dart
Set<String> _loadedIds = {};

void _appendBatch(List<MilkEntry> batch) {
  for (var entry in batch) {
    if (!_loadedIds.contains(entry.id)) {
      _displayList.add(entry);
      _loadedIds.add(entry.id ?? '');
    }
  }
}
```

### Issue: Pagination Doesn't Work

**Symptom**: Scrolling doesn't load more entries

**Root Cause**: Scroll listener not attached or `_hasMore` always false

**Fix**:
```dart
@override
void initState() {
  super.initState();
  _scrollController = ScrollController(); // Create
  _scrollController.addListener(_onScroll); // Attach
}

void _onScroll() {
  if (_scrollController.position.extentAfter < 500 &&
      _hasMore && // Check this!
      !_isPaginating) {
    _loadMore();
  }
}
```

### Issue: Wrong Billing Totals

**Symptom**: Bill shows incorrect amounts

**Root Cause**: Using paginated list instead of full data

**Fix**:
```dart
// WRONG:
var entries = _displayList; // Only 30 entries!
var total = entries.fold(...);

// RIGHT:
var entries = await _db.getMilkEntriesForBilling(
  startDate: _startDate,
  endDate: _endDate,
  // NO LIMIT
);
var total = entries.fold(...);
```

### Issue: Memory Leak on Close

**Symptom**: App slows down after opening/closing screens multiple times

**Root Cause**: Controllers not disposed

**Fix**:
```dart
@override
void dispose() {
  _scrollController.dispose(); // ADD THIS
  _displayList.clear();
  _loadedIds.clear();
  super.dispose();
}
```

---

## MONITORING & METRICS

### Add Logging

```dart
void _trackPaginationMetrics() {
  debugPrint('''
    === PAGINATION METRICS ===
    Total Loaded: ${_displayList.length}
    Has More: $_hasMore
    Page Size: $_pageSize
    Loaded IDs: ${_loadedIds.length}
    Memory Estimate: ${_displayList.length * 2}KB
    Last Fetch Time: ${DateTime.now()}
  ''');
}
```

### Expected Performance

| Metric | Target | Success |
|--------|--------|---------|
| First Load | < 500ms | ✓ |
| Pagination Batch | < 1s | ✓ |
| Scroll FPS | 60 | ✓ |
| Memory/1000e | < 50MB | ✓ |
| No Duplicates | Always | ✓ |
| Bill Accuracy | 100% | ✓ |

---

## ROLLOUT PLAN

### Phase 1: Entry History (Week 1)
- Implement pagination for "All" filter
- Test with 100, 500, 1000 entries
- Performance test
- Deploy to staging

### Phase 2: Payment History (Week 2)
- Implement pagination for history tab
- Test with payment volumes
- Deploy to staging

### Phase 3: Integration (Week 3)
- Verify billing still accurate
- Real-time sync testing
- Multi-device testing
- Deploy to production

### Phase 4: Monitor (Week 4+)
- Track error logs
- Monitor performance metrics
- Gather user feedback
- Iterate if needed

---

## SUCCESS CRITERIA

✅ App never feels laggy with 1000+ entries
✅ No duplicate entries after pagination
✅ Billing totals always accurate
✅ Memory usage < 100MB
✅ Smooth scroll at 60 FPS
✅ Real-time sync preserves pagination
✅ All controllers properly disposed
✅ No crashes or errors
