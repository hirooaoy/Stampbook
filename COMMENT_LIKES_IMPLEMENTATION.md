# Comment Likes Feature Implementation

## Overview
Added the ability for users to like comments throughout the Stampbook iOS app, similar to the existing post likes feature.

## Implementation Summary

### 1. Data Model Updates

**Comment.swift**
- Added `likeCount: Int` field (defaults to 0)
- Updated decoder to handle backwards compatibility with existing comments

**CommentLike.swift** (NEW)
- Created model to represent comment likes
- Structure mirrors the existing `Like` model for posts
- Fields: `userId`, `commentId`, `postId`, `stampId`, `commentOwnerId`, `createdAt`

**Notification.swift**
- Added `commentLike` case to `NotificationType` enum
- Added optional `commentId` field to support comment like notifications

### 2. Manager Layer

**CommentLikeManager.swift** (NEW)
- Created manager following the same pattern as `LikeManager`
- Implements optimistic UI updates for instant feedback
- Includes caching, debouncing, and error handling
- Supports batch like status fetching

### 3. Backend Services

**FirebaseService.swift**
- `toggleCommentLike()`: Atomic transaction to like/unlike comments
- `hasLikedComment()`: Check if user has liked a specific comment
- `fetchCommentLikes()`: Get list of users who liked a comment
- All operations update `likeCount` on comment documents atomically

### 4. UI Updates

**CommentRow** (in CommentView.swift)
- Redesigned timestamp area to show: "5h ago • 2 likes • Reply"
- If no likes: "5h ago • Reply" (doesn't show "0 likes")
- Replaced Reply button with heart icon on the right
- Heart fills red when liked, gray outline when not liked
- Clicking like count opens sheet showing who liked the comment
- Triple dot menu remains for delete/report options

**CommentRowView** (in PostDetailView.swift)
- Applied same UI changes as CommentRow
- Maintains consistency across comment sheet and post detail view

**CommentLikesView.swift** (NEW)
- Sheet view showing list of users who liked a comment
- Simplified version of LikeListView (no follow buttons)
- Shows avatar, display name, and username
- Tappable to navigate to user profiles

**NotificationView.swift**
- Added display for `commentLike` notifications
- Shows: "[User] liked your comment on [Stamp]"
- Tapping navigates to the post containing the comment

### 5. Infrastructure

**StampbookApp.swift**
- Created `@StateObject` for `CommentLikeManager`
- Added to environment objects
- Added cache clearing on sign out

**FeedView.swift**
- Added `@EnvironmentObject` for `commentLikeManager`
- Passed manager to `CommentView` instances

**PostDetailView.swift**
- Added `@StateObject` for `commentLikeManager`
- Passed manager to `CommentRowView` instances
- Added comment likes sheet presentation

### 6. Security & Rules

**firestore.rules**
- Added `commentLikes` collection rules
- Validation: users can only create/delete their own comment likes
- Added `likeCount` to allowed update fields for comments

### 7. Cloud Functions

**functions/index.js**
- Added `createCommentLikeNotification` trigger
- Fires when commentLike document is created
- Creates notification for comment owner (skips self-likes)
- Sends push notification: "[Name] liked your comment on [Stamp]"

### 8. Migration

**scripts/add_likecount_to_comments.js** (NEW)
- One-time migration script to add `likeCount: 0` to all existing comments
- Processes in batches of 500 (Firestore batch limit)
- Skips comments that already have `likeCount` field
- Run with: `node add_likecount_to_comments.js`

## Key Design Decisions

1. **UI Consistency**: Comments with 0 likes don't show "0 likes" text, while posts do show "❤️ 0". This follows Instagram's pattern where comment likes are less prominent.

2. **Simplified Likes Sheet**: Comment likes sheet doesn't show follow buttons (unlike post likes sheet). This keeps the focus on who liked the comment.

3. **Atomic Transactions**: Like/unlike operations use Firestore transactions to ensure `likeCount` stays in sync.

4. **Optimistic Updates**: Like state updates instantly in the UI before Firebase confirms, providing snappy Instagram-like UX.

5. **Backwards Compatibility**: Comment model decoder defaults `likeCount` to 0 if field doesn't exist, ensuring existing comments work seamlessly.

## Cost Impact

- **Comment likes storage**: ~100 bytes per like (minimal)
- **Notifications**: 1 write per like (existing pattern)
- **Like status checks**: Cached with same optimization as post likes (15% savings)

At 100 users (MVP goal):
- ~1000 comment likes/month
- ~$0.01/month additional cost
- Negligible impact on Firebase budget

## Testing Checklist

Before deploying:

1. ✅ Run migration script: `node scripts/add_likecount_to_comments.js`
2. ✅ Deploy Firestore rules: `firebase deploy --only firestore:rules`
3. ✅ Deploy Cloud Functions: `firebase deploy --only functions`
4. Test comment liking flow:
   - Like/unlike a comment
   - Check heart fills/unfills correctly
   - Verify like count updates
   - Test optimistic updates (airplane mode)
5. Test notifications:
   - Like someone's comment
   - Verify notification appears
   - Tap notification, verify navigation to post
6. Test likes sheet:
   - Tap like count on comment
   - Verify list of likers appears
   - Tap user, verify navigation to profile
7. Test edge cases:
   - Self-like prevention (no notification)
   - Multiple rapid taps (debouncing)
   - Sign out/sign in (cache clearing)

## Files Modified

**Models**
- Stampbook/Models/Comment.swift
- Stampbook/Models/CommentLike.swift (NEW)
- Stampbook/Models/Notification.swift

**Managers**
- Stampbook/Managers/CommentLikeManager.swift (NEW)

**Services**
- Stampbook/Services/FirebaseService.swift

**Views**
- Stampbook/Views/Shared/CommentView.swift
- Stampbook/Views/Shared/CommentLikesView.swift (NEW)
- Stampbook/Views/Feed/PostDetailView.swift
- Stampbook/Views/Feed/FeedView.swift
- Stampbook/Views/NotificationView.swift

**App**
- Stampbook/StampbookApp.swift

**Backend**
- functions/index.js
- firestore.rules

**Scripts**
- scripts/add_likecount_to_comments.js (NEW)

## Next Steps (Optional Enhancements)

1. **Rich Notifications**: Include comment preview in notification text
2. **Comment Like Analytics**: Track most-liked comments per stamp
3. **Badges**: Award for comments that get 10+ likes
4. **Sorting**: Option to sort comments by likes (in addition to chronological)

---

Implementation completed December 3, 2025

