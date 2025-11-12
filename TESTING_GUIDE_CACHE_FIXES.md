# Testing Guide: Comment & Like Count Cache Fixes

## Pre-Test Setup

### 1. Build and Run the App
```bash
# Build the app with the new changes
# Open in Xcode and run on simulator or device
```

### 2. Clear Existing Cache (Optional but Recommended)
To start fresh, you can clear UserDefaults:
- Delete the app from simulator/device
- Reinstall fresh
- OR: Will work with existing cache (will just populate over time)

---

## Test Suite 1: Like Count Persistence ✅

### Test 1.1: Like Your Own Post
**Purpose**: Verify like count shows immediately on cold start (no 0→1 flash)

**Steps**:
1. Open app and navigate to Feed
2. Find one of your own posts (or collect a new stamp to create one)
3. Click the heart icon to like your post
4. **Verify**: Heart fills red and count shows 1 ✅
5. **Kill the app** (swipe up from app switcher, don't just background)
6. Wait 2 seconds
7. **Reopen the app**
8. Navigate to Feed

**Expected Result**:
- ✅ Heart should be filled (red) immediately
- ✅ Count should show 1 immediately (NOT 0→1 flash)
- ✅ No jarring update after 1-2 seconds

**Look for in logs**:
```
⏱️ [LikeManager] init() completed with 1 cached likes and 1 cached counts
📊 [LikeManager] Loaded 1 cached like counts
```

---

### Test 1.2: Unlike Your Post
**Purpose**: Verify unlike state persists

**Steps**:
1. With the same post from Test 1.1
2. Click the heart icon to unlike
3. **Verify**: Heart becomes outline (not filled) and count shows 0 ✅
4. **Kill the app**
5. **Reopen the app**
6. Navigate to Feed

**Expected Result**:
- ✅ Heart should be outline (not filled)
- ✅ Count should show 0
- ✅ No flash or change

---

### Test 1.3: Multiple Posts
**Purpose**: Verify multiple likes are cached correctly

**Steps**:
1. Open app, go to Feed
2. Like 3-4 different posts (yours or others')
3. **Note which posts you liked**
4. **Verify**: All show filled hearts with correct counts ✅
5. **Kill the app**
6. **Reopen the app**
7. Navigate to Feed

**Expected Result**:
- ✅ All liked posts show filled hearts immediately
- ✅ All counts correct immediately
- ✅ No 0→1 flashes on any post

**Look for in logs**:
```
⏱️ [LikeManager] init() completed with 4 cached likes and 4 cached counts
```

---

### Test 1.4: Offline Like (Edge Case)
**Purpose**: Verify optimistic update survives restart even if not synced

**Steps**:
1. Open app, go to Feed
2. **Turn on Airplane Mode** (swipe down, enable)
3. Like a post
4. **Verify**: Heart fills, count increases ✅
5. **Don't turn off Airplane Mode**
6. **Kill the app**
7. **Reopen the app** (still offline)
8. Navigate to Feed

**Expected Result**:
- ✅ Heart still filled (from cache)
- ✅ Count still increased (from cache)
- ⚠️ When you go online later, it will sync to Firebase

---

## Test Suite 2: Comment Count Persistence ✅

### Test 2.1: Add Comment
**Purpose**: Verify comment count persists after restart

**Steps**:
1. Open app, navigate to Feed
2. Find a post, click the comment icon
3. Add a comment (e.g., "Test comment 1")
4. **Verify**: Comment appears, close comment sheet
5. **Verify**: Feed shows comment count = 1 ✅
6. **Kill the app**
7. **Reopen the app**
8. Navigate to Feed

**Expected Result**:
- ✅ Comment count shows 1 immediately
- ✅ No flash or change
- ✅ If you open comments, you see your comment

**Look for in logs**:
```
⏱️ [CommentManager] init() completed with 1 cached comment counts
📊 [CommentManager] Loaded 1 cached comment counts
```

---

### Test 2.2: Delete Comment (THE BUG FIX!)
**Purpose**: Verify deleted comment count persists (this was the original bug)

**Steps**:
1. With the post from Test 2.1 (has 1 comment)
2. Click comment icon to open comments
3. Click "..." menu on your comment
4. Delete the comment
5. **Verify**: Comment disappears ✅
6. Close comment sheet
7. **Verify**: Feed shows comment count = 0 ✅
8. **Kill the app** ⚡ (This is where the bug was!)
9. **Reopen the app** ⚡
10. Navigate to Feed

**Expected Result**:
- ✅ Comment count shows 0 (NOT 1!) ⚡ **THIS IS THE FIX**
- ✅ Opens comments → should show "No comments yet"
- ✅ Close comments → count stays 0

**What USED to happen (the bug)**:
- ❌ Would show 1 after restarting
- ❌ Opening comments would show 0 comments
- ❌ Closing comments would update to 0

---

### Test 2.3: Multiple Comments
**Purpose**: Verify multiple comment counts are tracked

**Steps**:
1. Open app, go to Feed
2. Comment on 2-3 different posts
3. **Note the counts** (should be 1 each if no other comments)
4. **Kill the app**
5. **Reopen the app**
6. Navigate to Feed

**Expected Result**:
- ✅ All posts show correct comment counts immediately
- ✅ No flashes or updates

---

### Test 2.4: Add Multiple, Delete Some
**Purpose**: Complex scenario to verify accurate persistence

**Steps**:
1. Open app, find one of your posts
2. Add 3 comments to it (comment, comment, comment)
3. **Verify**: Count shows 3 ✅
4. Delete 2 of the comments
5. **Verify**: Count shows 1 ✅
6. **Kill the app**
7. **Reopen the app**
8. Navigate to Feed

**Expected Result**:
- ✅ Count shows 1 (not 3, not 0)
- ✅ Open comments → see 1 comment
- ✅ Accurate and consistent

---

## Test Suite 3: Cache Sync with Firebase ✅

### Test 3.1: Feed Refresh Updates Cache
**Purpose**: Verify fresh Firebase data updates cache

**Steps**:
1. Have app open with some likes/comments
2. Pull down to refresh feed
3. **Verify**: Counts stay accurate
4. **Kill and reopen**
5. **Verify**: Still accurate (refresh updated cache)

---

### Test 3.2: Another User Likes Your Post
**Purpose**: Verify cache syncs when others interact

**Steps**:
1. On Device A (or simulator): Post something
2. On Device B (or different account): Like that post
3. On Device A: Pull to refresh
4. **Verify**: Like count increases ✅
5. On Device A: **Kill and reopen**
6. **Verify**: Count persists ✅

---

### Test 3.3: Sign Out Clears Cache
**Purpose**: Verify cache is cleared on sign out

**Steps**:
1. Open app with likes/comments cached
2. Go to Profile → Sign Out
3. Sign back in (same user or different)
4. Navigate to Feed

**Expected Result**:
- ✅ Cache is rebuilt from Firebase (not old cache)
- ✅ Counts are accurate
- ✅ No stale data from previous session

---

## Test Suite 4: Performance & UX ✅

### Test 4.1: Cold Start Speed
**Purpose**: Verify no performance degradation

**Steps**:
1. Kill app completely
2. Time how long until feed shows
3. **Compare**: Should feel instant (<1s)

**Expected Result**:
- ✅ Feed loads quickly
- ✅ Counts show immediately
- ✅ No noticeable delay

---

### Test 4.2: Memory Usage
**Purpose**: Verify no memory issues

**Steps**:
1. Open Xcode → Debug Navigator → Memory
2. Run app, interact with likes/comments
3. Note memory usage

**Expected Result**:
- ✅ Memory usage stable
- ✅ No leaks
- ✅ Typical app memory consumption

---

### Test 4.3: Rapid Interactions
**Purpose**: Verify cache handles rapid changes

**Steps**:
1. Rapidly like/unlike same post 5 times
2. **Verify**: UI responds instantly each time
3. **Kill and reopen**
4. **Verify**: Final state is correct

**Expected Result**:
- ✅ No race conditions
- ✅ Final state accurate
- ✅ No crashes

---

## Edge Cases to Test

### Edge Case 1: Empty State
- New user, no likes/comments
- Cache should be empty
- No errors in logs

### Edge Case 2: Large Numbers
- Like 50+ posts
- Add 20+ comments
- Verify cache handles it

### Edge Case 3: App Crash During Like
- Like post
- Force kill app immediately (before 1 second)
- Reopen
- Should either show liked (if cached) or not liked (if not cached)
- Either way, should sync correctly

---

## Success Criteria ✅

### Must Pass:
- ✅ Test 1.1: Like persists on cold start with correct count
- ✅ Test 2.2: Deleted comment count stays 0 (THE BUG FIX!)
- ✅ Test 3.3: Sign out clears cache
- ✅ No crashes during any test

### Should Pass:
- ✅ All tests in Test Suite 1
- ✅ All tests in Test Suite 2
- ✅ Feed refresh updates cache
- ✅ Performance feels instant

### Nice to Have:
- ✅ Multi-device sync
- ✅ Offline scenarios work
- ✅ Edge cases handled gracefully

---

## What to Look For in Logs

### Good Signs ✅
```
⏱️ [LikeManager] init() completed with X cached likes and Y cached counts
📊 [LikeManager] Loaded X cached like counts
⏱️ [CommentManager] init() completed with X cached comment counts
📊 [CommentManager] Loaded X cached comment counts
✅ Fetched X comments for post: [postId]
✅ Like synced to Firebase: [postId] -> true/false
```

### Bad Signs ❌
```
⚠️ Failed to fetch comments: [error]
⚠️ Failed to sync like: [error]
❌ Failed to add comment: [error]
[Any crash logs]
```

---

## Reporting Issues

If you find a bug, note:
1. Which test failed
2. Expected vs actual behavior
3. Device/simulator details
4. Relevant console logs
5. Steps to reproduce

---

## Quick Test Script

**5-Minute Smoke Test** (tests the main fixes):

1. ✅ Like your post → kill app → reopen → shows ❤️ 1 immediately
2. ✅ Unlike → kill app → reopen → shows ♡ 0
3. ✅ Add comment → kill app → reopen → shows count 1
4. ✅ **Delete comment → kill app → reopen → shows count 0** (THE BUG FIX!)
5. ✅ Sign out → cache cleared

If all 5 pass → ✅ FIXES WORKING!

---

## Notes

- Testing on simulator is fine, but device is better
- Clear cache between test runs if you want fresh state
- Logs are in Xcode console (⌘ + Shift + C)
- Watch for both emoji logs (✅, ⚠️, ❌) and standard logs

**Ready to test!** 🚀

Start with the Quick Test Script, then do deeper testing if you have time.

