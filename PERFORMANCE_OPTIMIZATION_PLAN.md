# Performance Optimization Plan - Milk Collection App
## Date: February 24, 2026

---

## ARCHITECTURE OVERVIEW

### Current Issues
- Entry History loads all entries at once when "All" is selected
- Payment History loads entire payment collection without pagination
- This causes UI lag and memory pressure with 1000+ entries
- No lazy loading or scroll-based pagination

### Optimization Goals
1. **Entry History**: Load today initially, then paginate "All" entries  
2. **Payment History**: Pagination for large datasets  
3. **Billing Screen**: Keep full data loading (required for accuracy)  
4. **Performance**: Support 10,000+ entries without lag  
5. **Safety**: Prevent duplicates, memory leaks, and calculation errors

---

## SOLUTION ARCHITECTURE

### 1. Entry History Optimization

**Initial Load Strategy**:
```
User opens Entry History
  ↓
Load TODAY's entries (fast, typically 5-20 entries)
  ↓
Display in UI with pagination controls
  ↓
If user clicks "All" or scrolls:
   → Show pagination (Load 30 at a time)
   → Use scroll listener to detect end
   → Load next batch on demand
```

**Date Filter Behavior**:
- Today → Load only today (no pagination)
- Week → Load only 7 days (typically < 50 entries, no pagination)
- 15 Days → Load only 15 days (may need pagination)
- Custom Date → Load only selected date (typically < 50 entries)
- **All** → PAGINATION ENABLED (load 30/batch)

**Key Firestore Queries**:
```dart
// For "Today"
query = entries
  .where('dairyId', isEqualTo: dairyId)
  .where('dateTime', isGreaterThanOrEqualTo: todayStart)
  .where('dateTime', isLessThan: todayEnd)
  .orderBy('dateTime', descending: true)
  .limit(30)

// For "All" (pagination)
// Batch 1
query = entries
  .where('dairyId', isEqualTo: dairyId)
  .orderBy('dateTime', descending: true)
  .limit(30)

// Batch N (after document #30)
query = entries
  .where('dairyId', isEqualTo: dairyId)
  .orderBy('dateTime', descending: true)
  .startAfterDocument(lastDocument)
  .limit(30)
```

### 2. Payment History Optimization

**Pagination Strategy**:
```
Filter: ALL
  ↓
Load first 50 payments
  ↓
Show with scroll pagination
  ↓
On scroll-to-end:
   → Load next 50
   → Append safely (no duplicates)

Filter: ADVANCE / PAID / DEDUCTION
  ↓
Load all (usually < 100)
  ↓
No pagination needed
```

### 3. Billing Screen Safety

**Billing MUST load full data**:
```dart
// Billing always uses FULL dataset
_entries = await _db.getMilkEntriesForBilling(
  startDate: _startDate,
  endDate: _endDate,
  // NO LIMIT, NO PAGINATION
)
```

**Reason**: Calculation accuracy requires complete picture
- Total milk must be accurate
- Total amount must be accurate
- Rate averaging must use all data
- No partial results allowed

### 4. Data Structure Separation

```
DataSource Layer:
  _allEntries → Raw fetched data (pagination cursor managed)
  _paginationKey → Last document reference (Firestore)
  _hasMore → Boolean (more data available)
  _pageSize → Entries per batch (30)

Display Layer:
  _entries → Filtered, sorted list for UI
  filteredByFarmer() → Apply farmer filter
  filteredByStaff() → Apply staff filter
  
Calculation Layer:
  _billingEntries → FULL, unfiltered data (for billing only)
  calculateTotals() → Uses unfiltered data
```

### 5. Memory Safety

**Rules**:
1. Never keep duplicate entries in lists
2. Use Set<String> to track loaded IDs
3. Clear pagination state when filter changes
4. Dispose scroll controllers properly
5. Avoid nested data structures

**Pattern**:
```dart
Set<String> _loadedIds = {}; // Track loaded entries

void _appendBatch(List<MilkEntry> newBatch) {
  for (var entry in newBatch) {
    if (!_loadedIds.contains(entry.id)) {
      _entries.add(entry);
      _loadedIds.add(entry.id);
    }
  }
}
```

### 6. Real-time Sync Safety

**Current Entry Added**:
```
New entry added via Firestore
  ↓
_syncService webhook fires
  ↓
If entry matches current filter:
   → Insert at TOP of list (newest first)
   → Don't reload full list
   → Maintain pagination state
```

**Change After Pagination**:
```
User on page 3 (entries 60-90)
New entry added in page 1 (top):
  ↓
Don't disrupt user's view
Add to top silently
Mark offset as "+1"
```

---

## IMPLEMENTATION CHECKLIST

### Phase 1: Entry History Pagination
- [ ] Add `ScrollController` to entry list
- [ ] Add `_paginationKey`, `_hasMore`, `_pageSize` variables
- [ ] Create `_loadNextBatch()` method
- [ ] Attach scroll listener
- [ ] Test with "All" filter
- [ ] Test with mixed filters (farmer + all)

### Phase 2: Payment History Pagination
- [ ] Add pagination to history tab
- [ ] Load first 50 on open
- [ ] Scroll-to-load-more
- [ ] Test with no filter
- [ ] Test with type filter

### Phase 3: Billing Screen Safety
- [ ] Verify billing loads full data
- [ ] Test calculation accuracy with paginated entry history
- [ ] Ensure summary shows correct totals

### Phase 4: Real-time Sync
- [ ] Test new entries added while viewing history
- [ ] Verify pagination state preserved
- [ ] No duplicate entries
- [ ] No memory leak

### Phase 5: Performance Testing
- [ ] 1000+ entries: Check memory
- [ ] 1000+ entries: Check UI responsiveness
- [ ] Pagination load time < 1s per batch
- [ ] No frame drops during scroll

---

## QUERY PATTERNS

### Firestore Query Safety

**Good Pattern**:
```dart
// Load with limit
Query query = db.collection('entries')
  .where('dairyId', isEqualTo: _dairyId)
  .orderBy('dateTime', descending: true)
  .limit(30);

// Fetch
QuerySnapshot snapshot = await query.get();
List<QueryDocumentSnapshot> docs = snapshot.docs;

// Store last doc for next pagination
if (docs.isNotEmpty) {
  _paginationKey = docs.last; // Save last document
}

// Get more
if (_paginationKey != null) {
  Query nextQuery = db.collection('entries')
    .where('dairyId', isEqualTo: _dairyId)
    .orderBy('dateTime', descending: true)
    .startAfterDocument(_paginationKey)
    .limit(30);
}
```

**Bad Pattern**:
```dart
// AVOID: No limit, loads everything
Query query = db.collection('entries')
  .where('dairyId', isEqualTo: _dairyId);

// With 10,000+ entries, this is slow and memory-heavy
QuerySnapshot snapshot = await query.get(); // BAD
```

---

## PERFORMANCE TARGETS

| Metric | Target | Current |
|--------|--------|---------|
| Initial Load | < 500ms | ? |
| Pagination Batch | < 1s | ? |
| Scroll FPS | 60 FPS | ? |
| Memory (1000 entries) | < 50MB | ? |
| Billing Load | < 2s | ? |
| No UI freezes | Always | ? |

---

## SAFETY GUARANTEES

1. **Accurate Billing**: Full data always loaded for calculations
2. **No Duplicates**: Track loaded IDs with Set<String>
3. **No Memory Leak**: Dispose controllers, clear caches on unload
4. **No Lost Data**: Pagination state preserved across filter changes
5. **Smooth UX**: Append batchesmanually, no full reloads

---

## FILES TO MODIFY

1. `lib/screens/entry_history_screen.dart` — Add pagination, scroll listener
2. `lib/screens/payment_manager_screen.dart` — Add pagination to history tab
3. `lib/database/database_helper.dart` — Add pagination query methods (optional, if using local DB)
4. `lib/services/firestore_sync_service.dart` — Verify pagination-safe sync

---

## NEXT STEPS

1. Review this plan with team
2. Implement Phase 1 (Entry History pagination)
3. Run performance tests
4. Iterate based on results
5. Document lessons learned
