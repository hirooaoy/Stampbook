# Profile Fetch Deduplication Implementation

**Date:** November 12, 2025
**Status:** ✅ Implemented - Ready for Testing

## What Was Changed

Added request deduplication to `FirebaseService.fetchUserProfile()` to prevent duplicate Firebase reads when multiple UI components request the same user profile simultaneously.

### Files Modified

1. **`Stampbook/Services/FirebaseService.swift`**
   - Added `inFlightProfileFetches` dictionary to track ongoing requests
   - Added `profileFetchQueue` DispatchQueue for thread-safe access
   - Wrapped `fetchUserProfile()` with deduplication logic

### Implementation Pattern

Copied the proven deduplication pattern from `ImageManager.downloadAndCacheProfilePicture()`:

1. **Atomic Check/Create**: Use `DispatchQueue.sync` to atomically check for existing tasks
2. **Wait for In-Flight**: If request already in progress, return the existing task
3. **Create New Task**: If no existing request, create and store new task
4. **Cleanup**: Remove from tracking dictionary after completion (success or error)

## Expected Behavior

### Before Fix
```
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
```
**Result:** 5 separate Firebase reads

### After Fix
```
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
📡 [FirebaseService] Calling getDocument()...
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
⏱️ [FirebaseService] Waiting for in-flight profile fetch
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
⏱️ [FirebaseService] Waiting for in-flight profile fetch
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
⏱️ [FirebaseService] Waiting for in-flight profile fetch
🔍 [FirebaseService] fetchUserProfile(LGp7cMqB2tSEVU1O7NEvR0Xib7y2) started
⏱️ [FirebaseService] Waiting for in-flight profile fetch
⏱️ [FirebaseService] User profile fetch: 0.062s
✅ [FirebaseService] Profile parsed successfully: @watagumostudio
```
**Result:** 1 Firebase read, 4 requests wait for the result

## Testing Plan

### Test 1: Feed View with Likes (Primary Test Case)
**Setup:**
1. Account A makes a post with photos
2. Account B likes the post multiple times (5+ likes)
3. Open app on Account A

**Expected:**
- Feed loads normally
- Like list shows 5 profile badges for Account B
- Logs show only 1 Firebase read for Account B's profile (not 5)
- Logs show "Waiting for in-flight profile fetch" messages

**What Could Go Wrong:**
- ❌ Profile badges don't load (deduplication blocking UI)
- ❌ App crashes when opening like list
- ❌ Multiple Firebase reads still happening (deduplication not working)

### Test 2: Notification Tap Flow
**Setup:**
1. Account B comments on Account A's post
2. Account A taps notification to view post detail

**Expected:**
- Post detail loads normally
- Commenter profile info appears correctly
- No errors in logs

**What Could Go Wrong:**
- ❌ Post detail doesn't load
- ❌ Profile info missing
- ❌ Error about profile fetch failing

### Test 3: Follow List View
**Setup:**
1. Navigate to profile tab
2. Tap "Followers" or "Following" list

**Expected:**
- List loads normally
- All profile badges/info appear
- Smooth scrolling

**What Could Go Wrong:**
- ❌ List doesn't load
- ❌ Profile info missing for some users
- ❌ Crashes when scrolling

### Test 4: Pull to Refresh Feed
**Setup:**
1. Open feed
2. Pull down to refresh

**Expected:**
- Feed refreshes normally
- Profile deduplication still works
- No duplicate reads in logs

**What Could Go Wrong:**
- ❌ Refresh hangs/never completes
- ❌ Profiles don't load after refresh

## Risk Assessment

**Low Risk:**
- Pattern already proven in `ImageManager` (used for months without issues)
- Same synchronization approach (DispatchQueue.sync)
- Error handling includes cleanup on failure
- No changes to data structures or API

**Medium Risk Areas:**
- Task cancellation edge cases (if view dismisses mid-fetch)
- Concurrent access patterns not tested at scale

**Testing Time:**
- ~15 minutes for basic functionality
- ~30 minutes for thorough testing

## Rollback Plan

If issues occur:

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
git checkout Stampbook/Services/FirebaseService.swift
```

This reverts to the previous working version.

## Success Metrics

✅ **Must Have:**
1. No crashes during normal app usage
2. All profiles load correctly
3. Feed, notifications, likes, comments all work

✅ **Should See:**
1. "Waiting for in-flight profile fetch" messages in logs
2. Fewer "Calling getDocument()" messages
3. No change in user-visible behavior

✅ **Nice to Have:**
1. Measurable reduction in Firebase reads
2. Slightly faster profile loading on slow networks

## Notes

This fix addresses the duplicate profile fetches identified in your logs where the same user profile (watagumostudio) was being fetched 5 times simultaneously when their likes appeared on a post. The Instagram-style feed pattern still works, but now shares profile data across concurrent requests instead of each making a separate Firebase read.

