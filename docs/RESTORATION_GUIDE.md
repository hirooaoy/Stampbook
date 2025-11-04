# Code Restoration Guide

## Region-Based Stamp Loading (Removed Nov 4, 2025)

**Commit:** `924ea6b2cccab589e73357fe48f91727a819f9d2`  
**Removed:** 176 lines of unused code  
**Why:** Premature optimization for MVP (only 1000 stamps)

### When to Restore

Restore this optimization when:
- Stamp count exceeds **2000 stamps**
- Initial map load time exceeds **1 second**
- Approaching Firebase free tier limits (1.5M reads/month)
- Users complain about slow map loading

### How to Restore

```bash
# 1. View the deleted code
git show 924ea6b -- Stampbook/Utilities/Geohash.swift

# 2. Restore the file
git checkout 924ea6b -- Stampbook/Utilities/Geohash.swift

# 3. Re-add the Firebase functions
# (Check commit 924ea6b for the removed fetchStampsInRegion functions)

# 4. Update MapView.swift to use region-based loading
# Replace: allStamps = await stampsManager.fetchAllStamps()
# With: allStamps = await stampsManager.fetchStampsInRegion(region: mapRegion)

# 5. Test with 2000+ stamps to verify performance improvement
```

### What Was Removed

1. **Geohash.swift** (124 lines)
   - Geohash encoding utility
   - Region bounds calculation
   - Used for spatial queries in Firestore

2. **StampsManager.fetchStampsInRegion()** (28 lines)
   - Fetches stamps only in visible map region
   - Uses geohash for efficient queries
   - Reduces bandwidth and initial load time

3. **FirebaseService.fetchStampsInRegion()** (24 lines)
   - Firestore query with geohash range
   - Batch fetching with limit
   - Returns only visible stamps

### What Was Kept

- **Firebase geohash index** (firestore.indexes.json)
  - Already deployed to production
  - No cost to maintain
  - Ready to use when needed

### Performance Benefits (at 2000+ stamps)

| Approach | Initial Load | Bandwidth | Firebase Reads |
|----------|--------------|-----------|----------------|
| Fetch All (current) | ~2-3s | 2MB | 2000 reads |
| Region-based | ~500ms | 300KB | 200-300 reads |

**When to enable:** Stamp count > 2000 OR load time > 1s

---

## Other Removed Features

### User Rank System (Removed Oct 2025)

**Commit:** Check git history for "rank"  
**Why:** Expensive Firestore queries for MVP  
**When to restore:** 1000+ active users, implement with Cloud Functions


