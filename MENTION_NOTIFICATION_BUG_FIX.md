# @Mention Notification Bug Fix

**Date:** November 22, 2025  
**Status:** ✅ FIXED

---

## Problem

watagumostudio was not receiving mention notifications when hiroo mentioned them using `@watagumostudio` in a comment. The notification bell showed no unread notifications.

---

## Root Cause

The Cloud Function `createCommentNotification` in `functions/index.js` had an **early return** bug:

**Before (Buggy Code):**

```javascript
exports.createCommentNotification = onDocumentCreated('comments/{commentId}', async (event) => {
  const comment = event.data.data();
  
  // Don't create notification if user comments on their own post
  if (comment.userId === comment.postOwnerId) {
    return null;  // ❌ BUG: This exits BEFORE processing mentions!
  }
  
  // ... mention extraction code here (never reached if commenting on own post)
});
```

**The specific case that broke:**

1. hiroo comments on their **own** post: `@watagumostudio`
2. Cloud Function checks: `comment.userId === comment.postOwnerId` → **true**
3. Function returns early on line 391 → **exits completely**
4. Mention extraction code (line 405+) **never runs**
5. watagumostudio never gets notification

This affected ANY case where someone mentions another user in a comment on their own post.

---

## Solution

Restructured the Cloud Function to **process mentions FIRST**, then conditionally create post owner notification:

**After (Fixed Code):**

```javascript
exports.createCommentNotification = onDocumentCreated('comments/{commentId}', async (event) => {
  const comment = event.data.data();
  
  // ✅ Extract mentions FIRST (before any early returns)
  const mentionedUsernames = extractMentions(comment.text);
  
  // Track who gets notified
  const notifiedUserIds = new Set();
  
  // Only create post owner notification if someone ELSE commented
  if (comment.userId !== comment.postOwnerId) {
    // ... create post owner notification
    notifiedUserIds.add(comment.postOwnerId);
  } else {
    console.log('⏭️ Skipping post owner notification (user commented on own post)');
  }
  
  // ✅ Process mentions (works regardless of who commented)
  if (mentionedUsernames.length > 0) {
    for (const username of mentionedUsernames) {
      // ... create mention notifications for other users
    }
  }
});
```

**Key Changes:**

1. Mention extraction moved **before** the post owner check
2. Replaced early `return null` with conditional notification creation
3. `notifiedUserIds` tracking ensures no duplicate notifications
4. Mention processing happens **regardless** of whether commenting on own post

---

## Test Results

**Test Case 1: Self-Comment with Mention**

- **Setup:** hiroo comments `@watagumostudio` on hiroo's own post
- **Expected:** watagumostudio gets mention notification, hiroo gets nothing
- **Result:** ✅ PASS

**Test Case 2: Regular Comment with Mention**

- **Setup:** watagumostudio comments `@hiroo` on hiroo's post
- **Expected:** hiroo gets mention notification (not regular comment notification)
- **Result:** ✅ PASS (existing functionality preserved)

**Test Case 3: Regular Comment without Mention**

- **Setup:** watagumostudio comments "Hi!" on hiroo's post
- **Expected:** hiroo gets regular comment notification
- **Result:** ✅ PASS (existing functionality preserved)

---

## Deployment

**Cloud Function Deployed:**

```bash
firebase deploy --only functions:createCommentNotification
```

**Status:** ✅ Live in production

---

## Data Cleanup

**Missed Notification:**

The original comment `@watagumostudio` (comment ID: `R8RkD3XLp3gDmwrSkipH`) from November 22, 2025 at 00:08:08 was missing its notification.

**Fix:** Manually created the missed notification:

```javascript
await db.collection('notifications').add({
  recipientId: 'Go0nnPbVWeOX8kxWhP2xjW0HDvg1', // watagumostudio
  actorId: 'mpd4k2n13adMFMY52nksmaQTbMQ2',    // hiroo
  type: 'mention',
  postId: 'mpd4k2n13adMFMY52nksmaQTbMQ2-your-first-stamp',
  stampId: 'your-first-stamp',
  commentPreview: '@watagumostudio',
  createdAt: <original timestamp>,
  isRead: false
});
```

**Result:** watagumostudio now sees the notification in the app ✅

---

## Edge Cases Handled

The fixed Cloud Function correctly handles all these scenarios:

1. ✅ **Self-comment with mention:** User comments on own post mentioning others → mentioned users get notified, post owner does not
2. ✅ **Self-comment without mention:** User comments on own post → no notifications (correct)
3. ✅ **Regular comment with mention:** User comments on someone else's post with mentions → post owner gets mention notification, other mentioned users get mention notifications
4. ✅ **Regular comment without mention:** User comments on someone else's post → post owner gets regular comment notification
5. ✅ **Multiple mentions:** All mentioned users get notified (max 3 per comment)
6. ✅ **Self-mention:** User mentions themselves → no notification (spam prevention)
7. ✅ **Duplicate mentions:** User mentioned multiple times → only one notification
8. ✅ **Invalid username:** @nonexistent → silently skipped

---

## Files Modified

1. **`functions/index.js`** - Fixed `createCommentNotification` Cloud Function

---

## Verification

After the fix, watagumostudio now has:

- **1 total notification**
- **1 unread notification**
- **Type:** mention
- **From:** hiroo
- **Preview:** "@watagumostudio"
- **Created:** November 22, 2025 at 00:08:08

The notification will appear in the app when watagumostudio opens the notifications sheet.

---

## Future Work

Consider adding:

1. **Firestore index** for `recipientId + type + createdAt` queries (for faster filtered notification queries)
2. **Push notifications** for mentions (high engagement feature)
3. **Mention autocomplete** in comment editor (Phase 2 of mention feature)

---

## Related Documentation

- **Mention Feature Implementation:** `MENTION_FEATURE_IMPLEMENTATION.md`
- **Cloud Function Code:** `functions/index.js` (lines 386-509)
- **Notification Model:** `Stampbook/Models/Notification.swift`

