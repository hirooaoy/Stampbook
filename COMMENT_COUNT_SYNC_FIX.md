# Comment Count Synchronization Fix

**Date:** November 2, 2025

## Issue

Comment count was showing as "2" on feed view even after deleting the comments. The UI was not reflecting the actual number of comments in Firebase.

## Root Cause

The comment count desync occurred due to the following flow:

1. User opens comment sheet → `CommentManager.fetchComments()` loads actual comments
2. User deletes a comment → `CommentManager.deleteComment()` optimistically decrements local count
3. Firebase properly decrements the `commentCount` field in the `CollectedStamp` document
4. User closes comment sheet and returns to feed
5. **Problem:** Feed continues showing stale count from its cached `FeedPost` data

The issue was that `CommentManager.updateCommentCount()` was designed to NOT overwrite existing counts (to preserve optimistic updates), which meant:
- When feed loaded with stale data (count = 2), it called `updateCommentCount(postId, count: 2)`
- Since the count already existed (from deletion = 0), it was preserved
- But then when user returns to feed later, the feed's cached `FeedPost` still shows count = 2

## Solution

Made two key changes to `CommentManager.swift`:

### 1. Always Sync After Deletion
```swift
func deleteComment(commentId: String, postId: String, postOwnerId: String, stampId: String) {
    // ... optimistic update ...
    
    Task {
        do {
            try await firebaseService.deleteComment(...)
            
            // ✅ NEW: Refetch comments after successful deletion
            // This ensures count is accurate and synced with Firebase
            await fetchComments(postId: postId)
        } catch {
            // Also refetch on error to restore accurate state
            await fetchComments(postId: postId)
        }
    }
}
```

### 2. Always Use Fetched Count as Source of Truth
```swift
func fetchComments(postId: String) async {
    // ...
    let fetchedComments = try await firebaseService.fetchComments(postId: postId, limit: 100)
    
    await MainActor.run {
        comments[postId] = fetchedComments
        // ✅ ALWAYS update count to match actual fetched comments
        // This fixes desync between cached feed count and actual Firebase count
        commentCounts[postId] = fetchedComments.count
        // ...
    }
}
```

### 3. Add Force Update Option
```swift
func updateCommentCount(postId: String, count: Int, forceUpdate: Bool = false) {
    // When forceUpdate is true, always updates (used for feed refresh)
    // When false, only updates if count doesn't exist (preserves optimistic updates)
    if forceUpdate || commentCounts[postId] == nil {
        commentCounts[postId] = count
    }
}
```

## How It Works Now

1. User deletes comment
2. Local count decrements immediately (optimistic)
3. Firebase deletion succeeds
4. **NEW:** Comments are refetched, count updates to match actual Firebase data
5. When user closes comment sheet, the count shown in feed is now accurate

## Testing

To verify the fix:
1. Open any post with 2+ comments
2. Delete all comments
3. Close comment sheet
4. **Expected:** Comment count shows "0" on feed
5. Pull to refresh feed
6. **Expected:** Count remains "0" (synced with Firebase)

## Related Files

- `Stampbook/Managers/CommentManager.swift` - Comment management with optimistic updates
- `Stampbook/Services/FirebaseService.swift` - Firebase comment operations (already working correctly)
- `Stampbook/Views/Feed/FeedView.swift` - Feed display (no changes needed)

## Notes

- The Firebase deletion logic in `FirebaseService.deleteComment()` was already working correctly
- The issue was purely a local cache synchronization problem
- Similar pattern should be considered for other social features (likes, follows, etc.)

