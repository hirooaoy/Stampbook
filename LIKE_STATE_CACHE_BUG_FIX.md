# Like State Cache Bug Fix

## Problem
User reported seeing "0 likes" but the heart icon was filled (red), even though they hadn't liked the post yet. This was caused by stale cached like state from a previous session.

## Root Cause
The app had three issues with like state management:

1. **No Like Status Fetch**: When the feed loaded, it displayed posts with like counts from Firebase, but never fetched the actual like status (whether the current user has liked each post). The app relied entirely on cached like state from UserDefaults.

2. **Stale Cache Not Cleared**: The cached like state persisted across app launches via `UserDefaults`. If a user liked a post, then unliked it elsewhere (e.g., web, or after cache corruption), the local cache would still show the old "liked" state.

3. **Like Count Update Logic**: The `updateLikeCount()` method only updated if the count was `nil`, meaning fresh data from Firebase feed couldn't overwrite stale cached counts.

## Solution

### 1. Fetch Like Status After Feed Load
Added a call to `fetchLikeStatus()` after the feed loads to sync cached state with Firebase:

```swift
// In FeedView.swift - AllFeedContent
private func loadFeedIfNeeded() {
    // ... existing feed load code ...
    
    // Fetch like status for all posts to sync with cached state
    let postIds = feedManager.feedPosts.map { $0.id }
    if !postIds.isEmpty {
        await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
    }
}
```

Applied to:
- `AllFeedContent.loadFeedIfNeeded()`
- `OnlyYouContent.loadFeedIfNeeded()`
- `FeedView.refreshFeedData()` (pull-to-refresh)

### 2. Fixed Like Count Update Logic
Changed `updateLikeCount()` to always update with fresh data unless there's a pending optimistic operation:

```swift
// In LikeManager.swift
func updateLikeCount(postId: String, count: Int) {
    // Only skip update if there's an active pending operation (preserves optimistic UI)
    if pendingLikes.contains(postId) || pendingUnlikes.contains(postId) {
        return
    }
    
    // Otherwise, always update with fresh data from feed
    likeCounts[postId] = count
}
```

**Before**: Only updated if count was `nil` (stale counts persisted)
**After**: Always updates with fresh data unless there's an active optimistic update

## How It Works Now

### Feed Load Flow
1. User opens feed
2. Feed loads posts from Firebase (includes like counts)
3. Posts display with cached like state (instant)
4. `fetchLikeStatus()` queries Firebase for actual like status
5. Like state updates if cache was wrong (heart fills/unfills accordingly)
6. Like counts update from fresh feed data

### Optimistic Updates Preserved
- When user taps like/unlike, UI updates instantly (optimistic)
- Pending operations tracked via `pendingLikes` and `pendingUnlikes`
- Fresh data from feed won't overwrite active optimistic updates
- After sync completes, state is verified and corrected if needed

## Testing
1. Like a post
2. Force quit app
3. Unlike the post from another device/session
4. Reopen app
5. ✅ Heart should be unfilled (previously would be filled)
6. ✅ Like count should be correct (previously might show stale count)

## Files Changed
- `Stampbook/Views/Feed/FeedView.swift`
  - Added `fetchLikeStatus()` calls in `AllFeedContent.loadFeedIfNeeded()`
  - Added `fetchLikeStatus()` calls in `OnlyYouContent.loadFeedIfNeeded()`
  - Added `fetchLikeStatus()` calls in `FeedView.refreshFeedData()`

- `Stampbook/Managers/LikeManager.swift`
  - Fixed `updateLikeCount()` to always update unless pending operation

## Impact
- ✅ Fixes heart icon showing wrong state
- ✅ Fixes like count showing stale data
- ✅ Preserves optimistic UI updates
- ✅ No impact on like/unlike performance
- ⚠️ Adds one batch query to Firebase on feed load (minimal cost, fetches all like status in parallel)

