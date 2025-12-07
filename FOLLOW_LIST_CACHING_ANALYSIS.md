# Follow List Caching Analysis

**Date:** December 5, 2025  
**Component:** FollowManager & FirebaseService  
**Severity:** Medium - Scalability & UX Issues

---

## Current Caching Architecture

### 1. **Follow Counts** (Efficient ✅)
**Location:** `FollowManager.followCounts`  
**Storage:** UserDefaults (persistent)  
**Structure:** `[userId: (followers: Int, following: Int)]`

```swift
// Cached in memory + disk
var followCounts: [String: (followers: Int, following: Int)] = [:]
```

**How it works:**
- Loads from UserDefaults on app launch
- Updates when viewing profiles
- Persists across app sessions

**Scalability:** ✅ **GOOD**
- Only stores counts (2 integers per user)
- Memory footprint: ~24 bytes per cached user
- For 1000 users: ~24 KB
- Disk storage is minimal

**Cache invalidation:** ✅ **GOOD**
- Updates on follow/unfollow via Cloud Functions
- Force refresh when viewing profiles
- Old data auto-expires when user opens profile

---

### 2. **Following Lists** (Medium Efficiency ⚠️)
**Location:** `FirebaseService.followingCache`  
**Storage:** In-memory only (doesn't persist)  
**TTL:** 2 hours  
**Structure:** `[userId: (profiles: [UserProfile], timestamp: Date)]`

```swift
private var followingCache: [String: (profiles: [UserProfile], timestamp: Date)] = [:]
private let followingCacheExpiration: TimeInterval = 7200 // 2 hours
```

**How it works:**
- First fetch from Firebase → Cache for 2 hours
- Subsequent requests within 2 hours → Serve from cache
- Invalidated on follow/unfollow

**Scalability:** ⚠️ **CONCERNS**

Memory usage per cached user's following list:
- UserProfile object: ~300 bytes (username, displayName, avatarUrl, etc.)
- Average following: 50 users
- **Per user cached: 15 KB**
- **For 100 users cached: 1.5 MB**
- **For 1000 users cached: 15 MB** ⚠️

**Issues:**
1. **Memory leak potential** - Cache never clears old entries (no LRU eviction)
2. **Unbounded growth** - Cache grows indefinitely until app restart
3. **Stale data risk** - 2 hour TTL might show outdated data if someone follows/unfollows

**Cache invalidation:** ⚠️ **PARTIAL**
- ✅ Invalidates YOUR cache when YOU follow/unfollow
- ❌ Doesn't invalidate when OTHERS follow/unfollow
- ❌ No LRU eviction for least-recently-used entries

---

### 3. **Followers/Following Display Lists** (Broken ❌)
**Location:** `FollowManager.followers` / `FollowManager.following`  
**Storage:** In-memory only  
**Structure:** Single global array per type

```swift
@Published var followers: [UserProfile] = []
@Published var following: [UserProfile] = []
```

**How it works:**
- `FollowListView` fetches for current user → Stores in global array
- When viewing different user → **BUG: Shows previous user's data**

**Scalability:** ❌ **BROKEN**

**Issues:**
1. **No per-user storage** - Single global array for all users
2. **Stale data bug** - Shows wrong user's followers/following
3. **No cache invalidation** - Data persists across navigation
4. **Memory inefficient** - Stores full UserProfile objects globally

**Just fixed:** Added `loadedUserId` tracking and `clearFollowLists()` to detect user changes

---

## Scalability Assessment

### Current State (11 users, ~15 follows)
- ✅ Follow counts: Minimal memory (~264 bytes)
- ✅ Following cache: ~225 bytes (only 2-3 users cached)
- ❌ Display lists: 2 KB (stale data bug)

**Total: ~2.5 KB** - Fine for now

---

### At 100 Users Scale (Target MVP)
Assuming average 50 follows per user:

| Cache Type | Memory | Issues |
|------------|--------|--------|
| Follow Counts | 2.4 KB | ✅ No issues |
| Following Cache | 1.5 MB | ⚠️ If all 100 cached |
| Display Lists | 30 KB | ✅ Fixed with clearFollowLists() |
| **TOTAL** | **1.5 MB** | ⚠️ Manageable but growing |

**Concerns:**
1. Following cache has no LRU eviction
2. Cache grows unbounded until app restart
3. Memory pressure on older devices

---

### At 1000 Users Scale (Post-MVP)
Assuming average 100 follows per user:

| Cache Type | Memory | Issues |
|------------|--------|--------|
| Follow Counts | 24 KB | ✅ No issues |
| Following Cache | **30 MB** | ❌ CRITICAL |
| Display Lists | 60 KB | ✅ Fine |
| **TOTAL** | **30 MB** | ❌ UNACCEPTABLE |

**Critical Issues:**
1. 30 MB for following lists is excessive
2. Will cause memory warnings on older iPhones
3. App will be killed by iOS on memory pressure
4. Performance degradation (slower SwiftUI updates)

---

## Is It Caching at the Right Time?

### What's Good ✅

1. **Follow counts cached on profile view**
   - ✅ Right timing - needed immediately for UI
   - ✅ Persisted to disk - instant display on next launch
   - ✅ Lightweight data structure

2. **Following list cached for feed refresh**
   - ✅ Good use case - feed queries following list frequently
   - ✅ 2 hour TTL is reasonable for mostly-static data

3. **Cache invalidation on follow/unfollow**
   - ✅ Immediate updates when user takes action
   - ✅ Prevents showing stale data after follow changes

### What's Bad ❌

1. **No LRU eviction for following cache**
   - ❌ Cache grows unbounded
   - ❌ No memory limit enforcement
   - ❌ Older entries never cleaned up

2. **Following cache stored in-memory only**
   - ⚠️ Lost on app restart (forces refetch)
   - ⚠️ Could persist to disk for better UX
   - ⚠️ Trade-off: Disk space vs memory

3. **Full UserProfile objects cached**
   - ❌ Stores avatarUrl, bio, etc. (not needed for feed)
   - ❌ Could cache just userIds and fetch profiles on-demand
   - ❌ Over-caching unnecessary data

4. **2 hour TTL too long**
   - ⚠️ Shows stale data if someone follows/unfollows others
   - ⚠️ Only invalidates YOUR cache, not others viewing you
   - ⚠️ Could reduce to 30 minutes

---

## Recommendations

### Immediate Fixes (Do Now)

1. **Add LRU eviction to following cache**
   ```swift
   private let maxCacheSize = 50 // Limit to 50 users
   private var cacheAccessOrder: [String] = [] // Track LRU order
   
   func evictOldestCacheEntry() {
       if followingCache.count > maxCacheSize {
           let oldestUserId = cacheAccessOrder.removeFirst()
           followingCache.removeValue(forKey: oldestUserId)
       }
   }
   ```

2. **Reduce TTL to 30 minutes**
   ```swift
   private let followingCacheExpiration: TimeInterval = 1800 // 30 min
   ```

3. **Add memory warning handler**
   ```swift
   NotificationCenter.default.addObserver(
       forName: UIApplication.didReceiveMemoryWarningNotification,
       object: nil,
       queue: .main
   ) { _ in
       self.followingCache.removeAll()
       print("🧹 Cleared following cache due to memory warning")
   }
   ```

### Medium-term Improvements (Post-MVP)

1. **Cache only user IDs, not full profiles**
   ```swift
   // Instead of: [userId: [UserProfile]]
   // Use: [userId: [String]] // Just store user IDs
   // Fetch profiles on-demand from ProfileManager cache
   ```
   **Benefit:** 98% memory reduction (300 bytes → 8 bytes per user)

2. **Move following cache to disk (Core Data or file)**
   - Persist across app restarts
   - Use NSCache with automatic eviction
   - Better memory management

3. **Implement smart prefetching**
   - Only cache following lists for active users
   - Don't cache for users you're just browsing
   - Prioritize current user's following list

### Long-term Architecture (1000+ users)

1. **Paginated following lists**
   - Don't fetch all 1000 following at once
   - Fetch 50 at a time with cursor
   - Only cache first page

2. **Server-side caching with CDN**
   - Cache following lists on Firebase servers
   - Use Cloud CDN for faster global access
   - Client just fetches from CDN

3. **GraphQL-style selective field fetching**
   - Only fetch fields needed for current view
   - Feed refresh only needs user IDs
   - Profile view needs full UserProfile

---

## Summary

### Current State
- ✅ Follow counts: Well-designed, scalable
- ⚠️ Following cache: Works but unbounded growth
- ✅ Display lists: Fixed stale data bug

### Scalability Verdict
- **100 users:** ⚠️ Manageable with fixes
- **1000 users:** ❌ Needs architectural changes
- **10000+ users:** ❌ Requires complete redesign

### Priority Actions
1. **HIGH:** Add LRU eviction (30 min to implement)
2. **HIGH:** Add memory warning handler (15 min)
3. **MEDIUM:** Reduce TTL to 30 min (2 min)
4. **LOW:** Consider disk persistence for following cache

### Cost-Benefit
Current caching saves **~4000 Firebase reads/day** for 100 users at the cost of **1.5 MB memory**. This is a good trade-off for MVP, but needs optimization for scale.

