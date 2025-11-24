# Stale Cache Count Bug Fix

## Date: November 18, 2025

## The Bug 🐛

**Symptoms:** After opening the app after a while, posts show:
- ❤️ Heart filled red (correct) ✅
- "0 likes 0 comments" (incorrect) ❌
- Actual data should be "1 like 1 comment"

## Root Cause Analysis 🔍

The app has TWO cache layers for like/comment data:

1. **UserDefaults Cache** (LikeManager & CommentManager)
   - Stores like/comment COUNTS: `[postId: count]`
   - Stores like STATUS: `Set<postId>` (heart filled/unfilled)
   - Updated on every like/unlike/comment/delete
   - Most recent, authoritative source

2. **Disk Cache** (FeedManager - `feed_cache.json`)
   - Stores full feed posts from last session
   - Includes STALE like/comment counts embedded in post data
   - Used for instant perceived load (Instagram trick)
   - Can be hours or days old

### The Problem Flow:

1. **App Launch After A While:**
   ```
   T+0ms:   LikeManager.init() loads UserDefaults cache
            → likedPosts: ["userId-stampId"] (heart filled ✅)
            → likeCounts: ["userId-stampId": 1] (correct count ✅)
            → commentCounts: ["userId-stampId": 1] (correct count ✅)
   
   T+50ms:  FeedManager loads disk cache (stale!)
            → feedPosts: [FeedPost(likeCount: 0, commentCount: 0)]
            → Old data from yesterday before the like happened
   
   T+100ms: FeedView syncs counts from feedPosts
            → likeManager.setLikeCounts(["userId-stampId": 0])
            → OVERWRITES fresh UserDefaults cache with stale disk cache! ❌
   
   T+500ms: Fresh Firebase data arrives
            → But UI already showed wrong counts for 400ms
   ```

2. **Result:**
   - Like STATUS (heart filled) comes from UserDefaults → Correct ✅
   - Like COUNT comes from disk cache → Wrong ❌
   - User sees: ❤️ (red heart) + "0 likes" = Confusing!

## The Fix ✅

**Two-Part Solution:**

### Part 1: Track Data Freshness (FeedManager)
- Added `@Published private(set) var isDataFresh = false`
- Set to `false` when loading disk cache (stale)
- Set to `true` when fetching from Firebase (fresh)
- Reset to `false` on cache clear

### Part 2: Smart Count Syncing (LikeManager & CommentManager)
- Modified `setLikeCounts()` and `setCommentCounts()` to accept `isStaleData` parameter
- **When `isStaleData = true` (disk cache):**
  - Only initializes counts for posts not already in manager
  - Preserves existing UserDefaults cache (won't overwrite 1 → 0)
- **When `isStaleData = false` (Firebase):**
  - Replaces ALL counts with fresh authoritative data
  - Normal behavior, overwrites everything

### Part 3: Updated Call Sites (FeedView)
- Always sync counts (never skip)
- Pass `isStaleData: !feedManager.isDataFresh` flag
- Applied to: `loadFeedIfNeeded()`, `refreshFeedData()`, `loadMorePostsIfNeeded()`

## Implementation Details

### Files Modified:

1. **`Stampbook/Managers/FeedManager.swift`**
   - Added `isDataFresh` property (line 26)
   - Set to `false` in `loadDiskCache()` (line 848)
   - Set to `true` in `fetchFeedAndPrefetch()` (line 653)
   - Set to `true` in `loadMyPosts()` (line 273)
   - Reset to `false` in `clearCache()` (line 819)

2. **`Stampbook/Managers/LikeManager.swift`**
   - Added `isStaleData` parameter to `setLikeCounts()` (line 227)
   - When stale: only fills missing posts (line 228-239)
   - When fresh: replaces all counts (line 240-246)
   - Added debug logging for both modes

3. **`Stampbook/Managers/CommentManager.swift`**
   - Added `isStaleData` parameter to `setCommentCounts()` (line 242)
   - When stale: only fills missing posts (line 243-254)
   - When fresh: replaces all counts (line 255-261)
   - Added debug logging for both modes

4. **`Stampbook/Views/Feed/FeedView.swift`**
   - Updated `loadFeedIfNeeded()` to always sync with flag (lines 890-899)
   - Updated `refreshFeedData()` to sync with fresh flag (lines 147-154)
   - Updated `loadMorePostsIfNeeded()` to sync with fresh flag (lines 934-942)

### Key Code Snippets:

**LikeManager.swift:**
```swift
func setLikeCounts(_ counts: [String: Int], isStaleData: Bool = false) {
    if isStaleData {
        // Only fill in posts we don't have data for yet
        for (postId, count) in counts {
            if likeCounts[postId] == nil {
                likeCounts[postId] = count
            }
        }
    } else {
        // Replace all counts with fresh Firebase data
        likeCounts = counts
    }
    saveCachedLikes()
}
```

**FeedView.swift:**
```swift
// Load feed (might be disk cache or Firebase)
await feedManager.loadFeed(userId: userId, stampsManager: stampsManager, forceRefresh: false)

// Always sync, but with appropriate mode
let likeCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.likeCount) })
likeManager.setLikeCounts(likeCounts, isStaleData: !feedManager.isDataFresh)
//                                    ↑
//                        true = only fill missing (stale disk cache)
//                        false = replace all (fresh Firebase)
```

## Testing Guide 🧪

### Scenario 1: Cold Start With Likes (Bug Reproduction & Verification)

**Setup:**
1. Open app, like a post (heart filled, "1 like")
2. Add a comment ("1 comment")
3. Force quit app completely
4. Wait a few seconds
5. Reopen app

**Expected Behavior (AFTER FIX):**
- ✅ Heart filled red immediately (from UserDefaults)
- ✅ "1 like 1 comment" shows immediately (from UserDefaults cache)
- ✅ Console shows: `📊 [LikeManager] Initialized X new posts from STALE data (preserved existing cache)`
- ✅ When Firebase loads: `📊 [LikeManager] Replaced all counts with FRESH Firebase data (X posts)`
- ✅ Counts stay correct throughout (no flash from 1 → 0 → 1)

**Old Behavior (BEFORE FIX):**
- ❤️ Heart filled red (correct)
- 💔 "0 likes 0 comments" shows first (WRONG!)
- 💔 After 500ms updates to "1 like 1 comment" (flash)

### Scenario 2: Pull To Refresh (Should Always Sync)

**Setup:**
1. Open app
2. Pull to refresh

**Expected Behavior:**
- ✅ Console shows: `✅ [FeedView] Synced counts from FRESH Firebase data`
- ✅ All counts update correctly
- ✅ `isDataFresh` is `true`

### Scenario 3: Load More Posts (Should Always Sync)

**Setup:**
1. Open app
2. Scroll to bottom
3. Load more posts

**Expected Behavior:**
- ✅ Console shows: `✅ [FeedView] Synced counts from FRESH Firebase data`
- ✅ New posts have correct counts
- ✅ `isDataFresh` is `true`

### Scenario 4: First Time App Open (No Disk Cache)

**Setup:**
1. Delete app
2. Reinstall
3. Sign in

**Expected Behavior:**
- ✅ No disk cache exists
- ✅ All data fetched fresh from Firebase
- ✅ Console shows: `✅ [FeedView] Synced counts from FRESH Firebase data`
- ✅ Counts are correct

## Debug Logging

Added debug prints to track behavior:

**FeedManager.swift:**
```
💾 [FeedManager] Loaded X posts from disk cache (STALE - don't sync counts!)
```

**FeedView.swift:**
```
✅ [FeedView] Synced counts from FRESH Firebase data
⏭️ [FeedView] Skipped count sync - data is from STALE disk cache
```

## Why This Works 🎯

1. **Preserves UserDefaults Cache:**
   - UserDefaults cache is always the most recent
   - Updated immediately on every like/comment action
   - NOT overwritten by stale disk cache (`isStaleData: true` only fills gaps)

2. **Initializes Missing Posts:**
   - If managers don't have a post's counts, disk cache provides fallback
   - Shows *something* instead of 0 (better UX)
   - But won't overwrite fresh data (1 like) with stale data (0 likes)

3. **Maintains Instagram-Style Loading:**
   - Disk cache still shows immediately for perceived speed
   - Visual content (images, text) shows instantly
   - Counts come from UserDefaults OR disk cache fallback
   - Fresh data replaces everything within 500ms

4. **No Breaking Changes:**
   - Disk cache still works the same way
   - Count sync always happens (no skipped calls)
   - Only the merge strategy changed (fill vs replace)

## Edge Cases Handled ✨

1. **No Disk Cache:** If `feed_cache.json` doesn't exist, `isDataFresh` stays `false` until Firebase loads → Counts come from UserDefaults cache → Correct ✅

2. **Force Refresh:** Always fetches fresh data, `isDataFresh = true` → Counts sync → Correct ✅

3. **Load More Posts:** Pagination loads fresh data, `isDataFresh = true` → Counts sync → Correct ✅

4. **Cache Clear:** On sign out or profile update, `isDataFresh` reset to `false` → Prevents stale counts → Correct ✅

## Performance Impact 📊

**No negative impact:**
- Disk cache still loads instantly
- UserDefaults cache loads instantly
- Skip one dictionary creation if data is stale (negligible)
- Fresh data arrives same speed as before

**Benefits:**
- No visual flash from 0 → 1 like
- Correct counts immediately on cold start
- Better user experience

## Related Code References

**Like Status Caching:** See `LIKE_STATUS_CACHING_SUMMARY.md`
**Comment Count Fix:** See `FIXES_APPLIED.md`
**Feed Optimization:** See `OPTIMIZATION_SUMMARY.md`

## Status: ✅ FIXED

All code changes committed. Ready for testing.

