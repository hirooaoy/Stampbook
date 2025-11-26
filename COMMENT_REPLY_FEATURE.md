# Comment Reply Feature Implementation

## ✅ Complete

The comment reply feature has been successfully implemented. Users can now reply directly to specific comments, creating threaded conversations with visual indentation.

---

## What Was Built

### 1. **Data Model Updates**

**Comment Model** (`Stampbook/Models/Comment.swift`)
- Added optional `parentCommentId: String?` field
- When `nil`, comment is top-level
- When set, comment is a reply to the parent comment ID
- Backwards compatible with existing comments

### 2. **Backend Changes**

**CommentManager** (`Stampbook/Managers/CommentManager.swift`)
- Updated `addComment()` to accept `parentCommentId` parameter
- Added smart sorting logic in `getComments()`:
  - Top-level comments sorted chronologically
  - Replies grouped under their parents
  - Replies within each group sorted chronologically
- Updated `deleteComment()` to orphan child replies:
  - When a parent comment is deleted, its replies are promoted to top-level
  - This prevents orphaned invisible comments

**FirebaseService** (`Stampbook/Services/FirebaseService.swift`)
- Updated `addComment()` to accept and save `parentCommentId`
- Updated `deleteComment()` with `orphanReplies` parameter:
  - Queries for child comments with matching `parentCommentId`
  - Sets their `parentCommentId` to `nil` (promotes to top-level)
  - Uses `FieldValue.delete()` to remove the field

**Firestore Rules** (`firestore.rules`)
- Added validation for optional `parentCommentId` field in comment creation
- Added update rule to allow orphaning (setting `parentCommentId` to nil)
- Deployed to production ✅

### 3. **UI Updates**

**CommentView** (`Stampbook/Views/Shared/CommentView.swift`)
- Added `@State private var replyingTo: Comment?` to track reply target
- Updated `CommentRow` signature to include `onReply` callback
- Added Reply button (text only, gray, 14pt font) to the left of triple dot menu
- Clicking Reply:
  1. Sets `replyingTo` to the comment being replied to
  2. Pre-fills text field with "@username " (e.g., "@rosemary ")
  3. Focuses keyboard (opens if closed)
- Updated `sendComment()` to pass `parentCommentId` from `replyingTo`
- Added visual indentation: `.padding(.leading, comment.parentCommentId != nil ? 40 : 0)`
- After sending, clears both `newCommentText` and `replyingTo`

**PostDetailView** (`Stampbook/Views/Feed/PostDetailView.swift`)
- Added `@State private var replyingTo: Comment?` state
- Updated `CommentInputView` to accept `@Binding var replyingTo: Comment?`
- Added `onChange(of: replyingTo)` to pre-fill text when reply target changes
- Wired up Reply button callback in `CommentRowView`
- Added visual indentation for replies (same 40pt padding)

### 4. **Visual Design**

**Reply Button:**
- Plain text "Reply" (no background, no border)
- Gray color (`.gray`)
- 14pt font size
- Positioned left of the triple dot menu
- Only visible for saved comments (not optimistic ones)

**Indentation:**
- Top-level comments: No indentation (0pt padding)
- Replies: 40pt left padding
- Replies to replies: Same 40pt padding (max 1 level of indentation)

**Pre-fill Behavior:**
- When Reply is tapped, input field shows: "@username " (with trailing space)
- Cursor positioned after the space, ready for typing
- User can delete the @mention if desired (still counts as a reply)
- `parentCommentId` determines reply status, not the @mention

---

## How It Works

### Reply Flow:

1. User taps "Reply" on a comment
2. `replyingTo` state is set to that comment
3. Text field pre-fills with "@username "
4. Keyboard opens/focuses
5. User types their message
6. User taps send
7. Comment is created with `parentCommentId` set
8. Comment appears indented under the parent
9. `replyingTo` is cleared for next comment

### Delete Flow (Parent Comment):

1. User deletes a parent comment
2. `deleteComment()` queries for child comments
3. Each child's `parentCommentId` is set to `nil` in Firestore
4. Comments are re-fetched
5. Former child comments now appear as top-level comments, sorted chronologically

### Display Flow:

1. `getComments()` fetches all comments for a post
2. Comments are separated into top-level and replies
3. Top-level comments are sorted by `createdAt` (oldest first)
4. For each top-level comment:
   - Comment is added to display list
   - Its replies are found and sorted (oldest first)
   - Replies are added immediately after parent
5. View applies 40pt indentation to any comment with `parentCommentId != nil`

---

## User Experience

**Threading:**
- Replies appear visually nested under their parent
- Only one level of indentation (flat hierarchy, easy to read)
- Replying to a reply still uses the same indentation level

**Deletion:**
- When a parent is deleted, replies are promoted to top-level
- No "deleted" placeholders or broken threads
- Replies remain visible, just lose their parent context

**Mentions:**
- @mentions still work in replies (automatically pre-filled)
- User can delete the @mention before posting (still a reply)
- Reply status is determined by `parentCommentId`, not @mention text

**Notifications:**
- No special "reply" notification type
- If someone is @mentioned in a reply, they get a mention notification
- Post owner always gets comment notification (existing behavior)

---

## Technical Decisions

### Why orphan replies instead of deleting them?

When a parent comment is deleted, we promote replies to top-level rather than deleting them. This:
- Preserves user-generated content
- Prevents confusion ("where did my comment go?")
- Matches your explicit design choice
- Simpler than showing "deleted" placeholders

### Why only one level of indentation?

Limiting to one visual level of indentation:
- Keeps UI clean and readable (no deep nesting)
- Prevents runaway thread depth
- Works well on mobile (limited screen width)
- Common pattern in Instagram, Twitter, Reddit

### Why pre-fill @mention when replying?

Pre-filling "@username " when tapping Reply:
- Makes it clear who you're replying to
- Notifies the person you're responding to them
- User can still delete it if unwanted
- Familiar pattern from Twitter/Instagram

### Why use `parentCommentId` instead of nesting collections?

Using a flat collection with `parentCommentId` field:
- Single query fetches all comments (efficient)
- Client-side grouping is fast and flexible
- Easy to orphan/promote replies
- Firestore subcollections would require multiple queries (expensive)

---

## Files Changed

1. `Stampbook/Models/Comment.swift` - Added `parentCommentId` field
2. `Stampbook/Managers/CommentManager.swift` - Threading logic & orphaning
3. `Stampbook/Services/FirebaseService.swift` - Backend support
4. `Stampbook/Views/Shared/CommentView.swift` - Reply UI & interaction
5. `Stampbook/Views/Feed/PostDetailView.swift` - Reply UI & interaction
6. `firestore.rules` - Security rules for new field

---

## Testing Checklist

- [ ] Reply to a top-level comment (should appear indented)
- [ ] Reply to a reply (should appear at same indentation level)
- [ ] Delete parent comment with replies (replies should become top-level)
- [ ] Tap Reply button (keyboard should open, text should pre-fill)
- [ ] Delete @mention before posting (should still be a reply)
- [ ] Old comments without `parentCommentId` (should display as top-level)
- [ ] Optimistic UI for replies (should show loading spinner while saving)
- [ ] Mention someone in a reply (they should get mention notification)

---

## Future Enhancements (Post-MVP)

1. **Show reply count** - "View 3 replies" to collapse/expand threads
2. **Collapse threads** - Tap to hide/show replies under a parent
3. **Reply indicator** - Small icon or "Replying to @username" label
4. **Vertical line connector** - Visual line connecting reply to parent
5. **Navigate to parent** - Tap reply to scroll to/highlight parent comment

---

## Cost Impact

**Reads:** No change (same single query fetches all comments)
**Writes:** No change (one document per comment)
**Storage:** Minimal (+20 bytes per comment for `parentCommentId`)
**Functions:** No additional function calls

**Estimated increase:** < 1% (essentially free)

