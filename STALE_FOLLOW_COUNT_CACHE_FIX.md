# Stale Follow Count Cache Bug Fix

**Date:** December 5, 2025  
**Severity:** HIGH  
**Status:** ✅ FIXED

---

## The Bug

User reported: "watagumostudio shows 1 follower on the profile card, but when I tap in it shows 0, then when I go back it still shows 1"

### Root Cause

The `FollowManager` caches follow counts in a dictionary (`followCounts: [String: (followers: Int, following: Int)]`) and persists them to UserDefaults. This cache had NO expiration mechanism.

The `UserProfileView` had problematic "optimistic merge" logic that would:
1. Check if cached counts exist for a user
2. If yes, ALWAYS keep the cached follower count (ignoring fresh Firestore data)
3. Only update the following count from fresh data

This was intended for optimistic UI updates during follow/unfollow actions, but it caused stale data to persist indefinitely.

### The Flow (Before Fix)

1. At some point, watagumostudio had 1 follower
2. That count was cached to `FollowManager.followCounts` and persisted to UserDefaults
3. The follower relationship was removed in Firestore (follower count became 0)
4. The iOS app cache was never updated
5. User views watagumostudio profile:
   - `UserProfileView` loads fresh profile from Firestore (followerCount: 0)
   - But the "merge" logic sees cached count exists (1 follower)
   - It KEEPS the stale cached value of 1 instead of using fresh data
6. User taps into FollowListView:
   - Fetches actual followers from Firestore
   - Shows the truth: 0 followers
7. User goes back:
   - Card still shows cached 1 follower (because it wasn't updated)

### Code Location

**UserProfileView.swift** (lines 417-428 and 441-447):
```swift
// BEFORE FIX (BROKEN)
if let optimisticCounts = followManager.followCounts[userId] {
    // Merge: keep optimistic followers, but update following from profile
    followManager.updateFollowCounts(userId: userId, 
                                   followerCount: optimisticCounts.followers,  // ❌ Keeps stale count!
                                   followingCount: profile.followingCount)
} else {
    // No optimistic counts, use profile data
    followManager.updateFollowCounts(userId: userId, 
                                   followerCount: profile.followerCount, 
                                   followingCount: profile.followingCount)
}
```

---

## The Fix

Added **timestamp-based cache expiration** with a 5-second validity window. Optimistic updates are only valid immediately after follow/unfollow actions, not indefinitely.

### Changes Made

#### 1. FollowManager.swift

Added cache timestamp tracking:
```swift
// Track when counts were cached to prevent stale data
private var followCountTimestamps: [String: Date] = [:]
private let cacheValidityDuration: TimeInterval = 5.0 // 5 seconds

/// Check if cached counts are still valid (cached within last 5 seconds)
func isCachedCountValid(userId: String) -> Bool {
    guard let timestamp = followCountTimestamps[userId] else {
        return false
    }
    let age = Date().timeIntervalSince(timestamp)
    return age < cacheValidityDuration
}
```

Updated cache write methods to track timestamps:
```swift
func updateFollowCounts(userId: String, followerCount: Int, followingCount: Int) {
    followCounts[userId] = (followerCount, followingCount)
    followCountTimestamps[userId] = Date() // ✅ Track when cached
    saveCachedFollowCounts()
}

func refreshFollowCounts(userId: String) async {
    let profile = try await firebaseService.fetchUserProfile(userId: userId, forceRefresh: true)
    self.followCounts[userId] = (profile.followerCount, profile.followingCount)
    self.followCountTimestamps[userId] = Date() // ✅ Track when cached
    self.saveCachedFollowCounts()
}
```

#### 2. UserProfileView.swift

Updated "merge" logic to check cache validity:
```swift
// AFTER FIX (CORRECT)
if let profile = userProfile {
    // ✅ Only use cached optimistic counts if they're very recent (< 5 seconds)
    if let optimisticCounts = followManager.followCounts[userId],
       followManager.isCachedCountValid(userId: userId) {
        // Recent optimistic update exists - use it
        print("📊 Using RECENT optimistic followers=\(optimisticCounts.followers)")
        followManager.updateFollowCounts(userId: userId, 
                                       followerCount: optimisticCounts.followers, 
                                       followingCount: profile.followingCount)
    } else {
        // No optimistic counts OR cache is stale - use fresh profile data
        print("📊 Using FRESH profile data: followers=\(profile.followerCount)")
        followManager.updateFollowCounts(userId: userId, 
                                       followerCount: profile.followerCount, 
                                       followingCount: profile.followingCount)
    }
}
```

---

## How It Works Now

### Scenario 1: Recent Follow/Unfollow (Optimistic Update)

1. User follows someone at 10:00:00
2. FollowManager optimistically updates count from 5 → 6
3. Cache timestamp set to 10:00:00
4. User views profile at 10:00:02 (2 seconds later)
5. Fresh profile loads from Firestore (still shows 5 because Cloud Function hasn't run yet)
6. Cache validity check: age = 2s < 5s → **cache is valid**
7. Result: Shows optimistic count of 6 ✅ (smooth UX, no flicker)

### Scenario 2: Stale Cache (Bug Case)

1. Old cache exists: watagumostudio = 1 follower (cached 2 days ago)
2. User views profile now
3. Fresh profile loads from Firestore (followerCount: 0)
4. Cache validity check: age = 172,800s > 5s → **cache is expired**
5. Result: Shows fresh count of 0 ✅ (truth from Firestore)

### Scenario 3: First View (No Cache)

1. User views profile for first time
2. No cached counts exist
3. Fresh profile loads from Firestore
4. Result: Shows fresh count from Firestore ✅

---

## Testing

### Before Fix
```
👤 View watagumostudio profile
   Card shows: 1 follower ❌ (stale cache)
   
→ Tap into followers list
   List shows: 0 followers ✅ (fresh from Firestore)
   
← Go back
   Card shows: 1 follower ❌ (still stale)
```

### After Fix
```
👤 View watagumostudio profile
   Card shows: 0 followers ✅ (cache expired, uses fresh data)
   
→ Tap into followers list
   List shows: 0 followers ✅ (fresh from Firestore)
   
← Go back
   Card shows: 0 followers ✅ (consistent)
```

### Test Sequence

1. ✅ View a profile with stale cached counts
   - Should show fresh Firestore data
   
2. ✅ Follow someone and immediately view their profile
   - Should show optimistic updated count (smooth UX)
   
3. ✅ Wait 6 seconds after following, then view profile
   - Cache should be expired, shows fresh Firestore data
   
4. ✅ View profile → tap followers → go back
   - All counts should be consistent

---

## Impact

### User Experience

**Before:** Confusing inconsistent counts, stale data could persist for days/weeks

**After:** 
- Accurate counts from Firestore (truth source)
- Smooth optimistic updates for recent follow actions (no flicker)
- Consistent counts across all views

### Cost

No additional Firebase reads. The profile was already being fetched, we're just using the correct data.

### Performance

Same performance. No new network calls, just better logic for which data to display.

---

## Files Changed

- `Stampbook/Managers/FollowManager.swift`
  - Added `followCountTimestamps` dictionary
  - Added `cacheValidityDuration` constant (5 seconds)
  - Added `isCachedCountValid()` method
  - Updated `updateFollowCounts()` to track timestamps
  - Updated `refreshFollowCounts()` to track timestamps
  - Updated `clearFollowData()` to clear timestamps

- `Stampbook/Views/Profile/UserProfileView.swift`
  - Updated "merge" logic in `onAppear` to check cache validity
  - Updated "merge" logic in `onChange(of: profileManager.currentUserProfile)` to check cache validity

---

## Prevention

This won't happen again because:

1. ✅ Cache now has 5-second expiration for non-optimistic views
2. ✅ Fresh Firestore data always preferred over stale cache
3. ✅ Optimistic updates only applied immediately after user actions
4. ✅ Clear separation between "recent optimistic" vs "stale historical" cache

---

## Related Bugs

This fix complements the earlier cache fixes documented in `FOLLOW_RELATIONSHIPS_BUG_FIX.md`:
- Profile cache expiration (24-hour limit)
- Cache invalidation on follow/unfollow actions

Together, these ensure follow counts are always accurate and up-to-date.

---

## Lessons Learned

1. **Timestamp everything you cache** - Without expiration, caches become stale data graves
2. **Different cache types need different TTLs** - Optimistic updates (5s) vs profile cache (24h)
3. **Always prefer fresh data over cache for viewing** - Cache should optimize, not replace truth
4. **Test cache invalidation paths** - Stale cache is worse than no cache

---

✅ **Status: RESOLVED**

