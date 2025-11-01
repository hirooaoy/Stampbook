# Like and Comment System Implementation

## Overview

This document describes the implementation of the like and comment functionality for the Stampbook iOS app. The implementation follows Instagram-style patterns with optimistic UI updates and real-time synchronization.

## Architecture

### Data Models

#### Like (`Models/Like.swift`)
- **Fields:**
  - `id`: Document ID (auto-generated)
  - `userId`: User who liked the post
  - `postId`: Post being liked (format: `{userId}-{stampId}`)
  - `stampId`: Stamp ID for the post
  - `postOwnerId`: Owner of the post
  - `createdAt`: Timestamp of like

#### Comment (`Models/Comment.swift`)
- **Fields:**
  - `id`: Document ID (auto-generated)
  - `userId`: User who wrote the comment
  - `postId`: Post being commented on
  - `stampId`: Stamp ID for the post
  - `postOwnerId`: Owner of the post
  - `text`: Comment content
  - `createdAt`: Timestamp of comment
  - `userDisplayName`, `userUsername`, `userAvatarUrl`: Denormalized user info for performance

### Manager Classes

#### LikeManager (`Managers/LikeManager.swift`)
- **Responsibilities:**
  - Track liked posts for current user
  - Maintain like counts per post
  - Handle optimistic UI updates
  - Sync likes with Firebase
  - Cache liked posts locally (UserDefaults)

- **Key Methods:**
  - `toggleLike()`: Like/unlike a post with optimistic update
  - `isLiked()`: Check if current user liked a post
  - `getLikeCount()`: Get like count for a post
  - `fetchLikeStatus()`: Batch fetch like status for multiple posts

#### CommentManager (`Managers/CommentManager.swift`)
- **Responsibilities:**
  - Manage comments per post
  - Track comment counts
  - Handle optimistic UI updates
  - Sync comments with Firebase

- **Key Methods:**
  - `fetchComments()`: Load comments for a post
  - `addComment()`: Add new comment with optimistic update
  - `deleteComment()`: Delete a comment
  - `getComments()`: Get comments for a post
  - `getCommentCount()`: Get comment count for a post

### Firebase Service Updates

#### New Methods in `FirebaseService.swift`:

**Likes:**
- `toggleLike()`: Create or delete like (atomic operation)
- `hasLiked()`: Check if user liked a post
- `fetchLikeCount()`: Get total likes for a post
- `fetchPostLikes()`: Get list of users who liked a post

**Comments:**
- `addComment()`: Create new comment
- `fetchComments()`: Load comments for a post (chronological order)
- `deleteComment()`: Remove a comment
- `fetchCommentCount()`: Get total comments for a post

**Updates to CollectedStamp:**
- Added `likeCount` field (backward compatible, defaults to 0)
- Added `commentCount` field (backward compatible, defaults to 0)

### UI Components

#### FeedView Updates (`Views/Feed/FeedView.swift`)
- Added `LikeManager` and `CommentManager` as `@StateObject`
- Pass managers to `AllFeedContent` and `OnlyYouContent`
- Updated `PostView` to use managers for real-time updates

**PostView Changes:**
- Accept `likeManager` and `commentManager` as parameters
- Compute `isLiked` and counts from managers (reactive)
- Like button calls `likeManager.toggleLike()` with optimistic update
- Comment button opens `CommentView` sheet
- Initialize counts on appear from feed data

#### CommentView (`Views/Shared/CommentView.swift`)
- Full-screen modal for viewing and adding comments
- **Features:**
  - Empty state for no comments
  - Loading state while fetching
  - Scrollable list of comments with profile pictures
  - Comment input field at bottom
  - Delete button for own comments or comments on own posts
  - "Time ago" display for comment timestamps
  - Real-time updates via `CommentManager`

### Firestore Structure

```
/likes/{likeId}
  - userId: string (indexed)
  - postId: string (indexed)
  - stampId: string
  - postOwnerId: string
  - createdAt: timestamp

/comments/{commentId}
  - userId: string
  - postId: string (indexed)
  - stampId: string
  - postOwnerId: string
  - text: string
  - createdAt: timestamp (indexed)
  - userDisplayName: string (denormalized)
  - userUsername: string (denormalized)
  - userAvatarUrl: string (denormalized)

/users/{userId}/collected_stamps/{stampId}
  - likeCount: number (updated atomically)
  - commentCount: number (updated atomically)
  - ... (existing fields)
```

### Security Rules (`firestore.rules`)

**Likes:**
- Read: Authenticated users only
- Create: User can only like with their own userId
- Delete: User can only delete their own likes
- Update: Not allowed (immutable)

**Comments:**
- Read: Authenticated users only
- Create: User can only comment with their own userId
- Delete: Comment author OR post owner can delete
- Update: Not allowed (immutable, no editing)

### Firestore Indexes (`firestore.indexes.json`)

Added composite indexes for:
1. **Likes:** `postId` (ASC) + `createdAt` (DESC)
   - Used for fetching likes on a post sorted by time
2. **Comments:** `postId` (ASC) + `createdAt` (ASC)
   - Used for fetching comments on a post in chronological order

## Key Features

### Optimistic UI Updates
- **Likes:** Instantly toggle heart icon and update count, sync to Firebase in background
- **Comments:** Immediately add comment to list, sync to Firebase in background
- **Error Handling:** Revert optimistic updates if Firebase sync fails

### Performance Optimizations
- **Like Caching:** Store liked posts in UserDefaults for instant UI state on app launch
- **Batch Operations:** Fetch like status for multiple posts in parallel
- **Denormalized Data:** Comment includes user profile info to avoid extra fetches

### User Experience
- **Real-time Updates:** Counts update automatically as managers change
- **Instagram-style UX:** Familiar interaction patterns (heart to like, tap count to see who liked)
- **Smooth Animations:** Native SwiftUI transitions for adding/removing items

## Usage

### For Developers

**To add likes to a new view:**
```swift
@StateObject private var likeManager = LikeManager()

// In your post/item view
Button(action: {
    likeManager.toggleLike(
        postId: postId,
        stampId: stampId,
        userId: currentUserId,
        postOwnerId: postOwnerId
    )
}) {
    Image(systemName: likeManager.isLiked(postId: postId) ? "heart.fill" : "heart")
    Text("\(likeManager.getLikeCount(postId: postId))")
}
```

**To add comments to a new view:**
```swift
@StateObject private var commentManager = CommentManager()

// Show comment view
.sheet(isPresented: $showComments) {
    CommentView(
        postId: postId,
        postOwnerId: postOwnerId,
        stampId: stampId,
        commentManager: commentManager
    )
    .environmentObject(authManager)
}
```

## Deployment Checklist

1. **Deploy Firestore Rules:**
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Deploy Firestore Indexes:**
   ```bash
   firebase deploy --only firestore:indexes
   ```

3. **Verify Indexes:**
   - Go to Firebase Console → Firestore → Indexes
   - Wait for indexes to build (usually < 5 minutes)

4. **Test in Production:**
   - Like a post → verify count updates
   - Unlike a post → verify count decrements
   - Add a comment → verify it appears immediately
   - Delete a comment → verify it removes
   - Close app and reopen → verify liked posts persist

## Cost Considerations

**Firestore Reads:**
- Like toggle: 1 read (check if liked) + 1 write (create/delete)
- Load comments: N reads (N = number of comments, capped at 50)
- Load likes: N reads (N = number of likes, capped at 50)

**Optimizations:**
- Like status cached locally (reduces reads on cold start)
- Comments only fetched when user opens CommentView
- Denormalized user data in comments (avoids N additional profile reads)

## Future Enhancements

1. **Notifications:**
   - Notify user when someone likes their post
   - Notify user when someone comments on their post

2. **Like List View:**
   - Show list of users who liked a post
   - Tap like count to navigate to list

3. **Comment Editing:**
   - Allow users to edit their own comments within 5 minutes
   - Add "Edited" indicator

4. **Rich Comments:**
   - @mentions of other users
   - Emoji reactions to comments
   - Reply threading

5. **Performance:**
   - Implement pagination for comments (currently loads all)
   - Add real-time listeners for live updates
   - Cache comment counts in feed posts

## Testing

### Manual Test Cases

**Likes:**
- [ ] Like a post → heart turns red, count increments
- [ ] Unlike a post → heart turns gray, count decrements
- [ ] Close app and reopen → liked state persists
- [ ] Like while offline → syncs when online
- [ ] Multiple users like same post → count accurate

**Comments:**
- [ ] Add comment → appears immediately at bottom
- [ ] Delete own comment → removes from list
- [ ] Delete comment on own post → removes from list
- [ ] View empty comments → shows "No comments yet"
- [ ] Add comment while offline → syncs when online

### Edge Cases
- [ ] Like/unlike rapidly (optimistic updates don't conflict)
- [ ] Add comment with empty text → button disabled
- [ ] Network error during like → reverts optimistic update
- [ ] Network error during comment → removes optimistic comment

## Summary

The like and comment system has been successfully implemented with:
- ✅ Data models (Like, Comment)
- ✅ Manager classes (LikeManager, CommentManager)
- ✅ Firebase service methods
- ✅ UI components (CommentView, updated FeedView)
- ✅ Firestore rules and indexes
- ✅ Optimistic UI updates
- ✅ Offline support with caching

The implementation follows best practices:
- **Separation of concerns:** Managers handle business logic, views handle presentation
- **Optimistic updates:** Instant UI feedback for better UX
- **Error handling:** Graceful fallbacks for network issues
- **Performance:** Caching, batch operations, denormalized data
- **Security:** Proper Firestore rules to prevent abuse

Users can now like and comment on posts in the feed with a smooth, Instagram-style experience!

