# Region-Based Stamp Loading (Archived Feature)

## Status: NOT IMPLEMENTED IN MVP ⚠️
**Current:** Using `fetchAllStamps()` - loads all stamps globally  
**When to activate:** When stamp count exceeds ~1500 stamps

---

## Why This Exists

For MVP with <1000 stamps, loading all stamps at once is:
- ✅ Faster (Firebase persistent cache makes subsequent loads instant)
- ✅ Simpler (no region tracking complexity)
- ✅ Cheaper (~12K reads/month = FREE under 1.5M tier)

But at **1500+ stamps**, region-based loading becomes necessary:
- Only load visible stamps (~150-300 vs all 1500+)
- Faster initial load, less bandwidth
- Reduces Firebase read costs

---

## How It Works

### 1. Geohash Encoding
Each stamp has a `geohash` field (e.g., "9q8yyk8y") that encodes its location.
Nearby locations share prefixes: "9q8y" covers most of SF downtown.

### 2. Firestore Range Query
```swift
// Instead of fetching ALL stamps:
let allStamps = try await db.collection("stamps").getDocuments()

// Fetch only stamps in visible map region:
let (minHash, maxHash) = Geohash.bounds(for: mapRegion, precision: 5)
let visibleStamps = try await db.collection("stamps")
    .whereField("geohash", isGreaterThanOrEqualTo: minHash)
    .whereField("geohash", isLessThan: maxHash)
    .limit(to: 500)
    .getDocuments()
```

### 3. Update on Pan/Zoom
Re-query when user moves map to load new stamps.

---

## Implementation Code (Ready to Use)

### StampsManager.swift
```swift
/// Fetch stamps in a geographic region (for map view)
/// 
/// **WHEN TO USE:**
/// - Stamp count exceeds ~1500 stamps
/// - "Fetch all" approach becomes too slow (>1 second)
/// 
/// Uses geohash for efficient spatial queries
/// - Parameter region: The visible map region
/// - Parameter precision: Geohash precision (default 5 = ~5km)
/// - Returns: Array of stamps in the region
func fetchStampsInRegion(region: MKCoordinateRegion, precision: Int = 5) async -> [Stamp] {
    let (minGeohash, maxGeohash) = Geohash.bounds(for: region, precision: precision)
    
    do {
        let fetched = try await firebaseService.fetchStampsInRegion(
            minGeohash: minGeohash,
            maxGeohash: maxGeohash,
            limit: 500  // Generous limit for complete metro area coverage
        )
        
        // Add to cache for future use
        for stamp in fetched {
            stampCache.set(stamp.id, stamp)
        }
        
        return fetched
    } catch {
        print("❌ [StampsManager] Failed to fetch stamps in region: \(error.localizedDescription)")
        return []
    }
}
```

### FirebaseService.swift
```swift
/// Fetch stamps in a geographic region (for map view)
/// Uses geohash for efficient spatial queries
func fetchStampsInRegion(minGeohash: String, maxGeohash: String, limit: Int = 200) async throws -> [Stamp] {
    let snapshot = try await db
        .collection("stamps")
        .whereField("geohash", isGreaterThanOrEqualTo: minGeohash)
        .whereField("geohash", isLessThan: maxGeohash)
        .limit(to: limit)
        .getDocuments()
    
    let stamps = snapshot.documents.compactMap { doc -> Stamp? in
        try? doc.data(as: Stamp.self)
    }
    
    return stamps
}
```

### MapView.swift Changes
```swift
// CURRENT (loads all stamps once):
let stamps = await stampsManager.fetchAllStamps()

// FUTURE (loads only visible region):
let stamps = await stampsManager.fetchStampsInRegion(region: mapRegion)

// Add region change tracking:
.onChange(of: mapRegion) { oldRegion, newRegion in
    // Refresh when user pans/zooms significantly
    if hasMovedSignificantly(from: oldRegion, to: newRegion) {
        Task {
            allStamps = await stampsManager.fetchStampsInRegion(region: newRegion)
        }
    }
}
```

---

## Migration Checklist

When you're ready to switch (at ~1500 stamps):

### Step 1: Verify Geohash Data
```bash
# Check all stamps have geohash field
node check_stamps_in_firebase.js

# If any missing, run:
node add_geohash_to_stamps.js
```

### Step 2: Verify Firestore Index
Firestore index should already exist (deployed via `firestore.indexes.json`):
```json
{
  "collectionGroup": "stamps",
  "fields": [
    {"fieldPath": "geohash", "order": "ASCENDING"},
    {"fieldPath": "__name__", "order": "ASCENDING"}
  ]
}
```

### Step 3: Update MapView.swift
Replace line 278:
```swift
// OLD:
let stamps = await stampsManager.fetchAllStamps()

// NEW:
@State private var mapRegion: MKCoordinateRegion = ...
let stamps = await stampsManager.fetchStampsInRegion(region: mapRegion)
```

### Step 4: Add Region Change Tracking
```swift
.onChange(of: searchRegion) { oldValue, newValue in
    if let region = newValue {
        Task {
            allStamps = await stampsManager.fetchStampsInRegion(region: region)
        }
    }
}
```

### Step 5: Test Thoroughly
- Pan map around → stamps load dynamically
- Zoom in/out → appropriate density
- Check Firebase reads (should be ~200 per map view vs 400+ with fetchAll)

---

## Performance Comparison

### Current (fetchAllStamps):
- First load: ~500ms for 400 stamps
- Subsequent: <50ms (Firebase cache)
- Reads: 400 per new user

### Future (fetchStampsInRegion):
- First load: ~300ms for 150 stamps (visible region)
- Subsequent: <50ms (Firebase cache)
- Reads: 150 per new user + 50-100 per pan/zoom
- **Net savings: ~250 reads on first load**

---

## Cost Analysis

### At 1000 stamps, 100 users:
- **Current:** 100 users × 1000 stamps = 100K reads/month = FREE ✅
- **Region-based:** Not worth the complexity

### At 2000 stamps, 500 users:
- **Current:** 500 × 2000 = 1M reads/month = $0 (just under 1.5M free tier) ✅
- **Region-based:** 500 × 300 average = 150K reads/month = $0 💰

### At 5000 stamps, 1000 users:
- **Current:** 1000 × 5000 = 5M reads/month = **$2.10/month** 💸
- **Region-based:** 1000 × 300 = 300K reads/month = **$0** ✅

**Break-even point:** ~1500-2000 stamps or 500+ active users

---

## Infrastructure Already Deployed ✅

You don't need to set up anything new! The infrastructure is ready:

1. ✅ **Geohash field** on all stamps (via `upload_stamps_to_firestore.js`)
2. ✅ **Firestore index** deployed (via `firestore.indexes.json`)
3. ✅ **Geohash utility** (`Utilities/Geohash.swift`)
4. ✅ **Migration script** (`add_geohash_to_stamps.js`) for backfill

All you need to do is:
1. Uncomment the functions in `StampsManager.swift` and `FirebaseService.swift`
2. Update `MapView.swift` to use region-based loading
3. Test and deploy

---

## Files Involved

### Core Implementation
- `Stampbook/Managers/StampsManager.swift` (lines 270-297)
- `Stampbook/Services/FirebaseService.swift` (lines 311-324)
- `Stampbook/Utilities/Geohash.swift` (entire file)
- `Stampbook/Views/Map/MapView.swift` (line 278)

### Infrastructure
- `firestore.indexes.json` (lines 14-26)
- `upload_stamps_to_firestore.js` (auto-generates geohashes)
- `add_geohash_to_stamps.js` (backfill script)
- `check_stamps_in_firebase.js` (verification)

### Documentation
- `docs/ADDING_STAMPS.md` (mentions geohash auto-generation)

---

## Decision Time: When to Switch?

### **Keep current approach if:**
- ❌ You have <1500 stamps
- ❌ You have <500 active users  
- ❌ Firebase bills are <$1/month
- ✅ First load is <1 second
- ✅ Users rarely pan far from initial location

### **Switch to region-based if:**
- ✅ You have >1500 stamps
- ✅ Firebase reads exceed 2M/month (costing money)
- ✅ First load takes >1.5 seconds
- ✅ Users frequently explore distant locations
- ✅ You're approaching Firebase free tier limits

**Bottom line:** You'll know when you need it. Firebase Console will show rising costs.

---

*Archived: November 4, 2025*  
*Ready to activate when stamp count reaches ~1500*

