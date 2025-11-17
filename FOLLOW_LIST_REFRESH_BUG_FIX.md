# Follow List Refresh Bug Fix

**Date**: November 17, 2025  
**Issue**: After unfollowing someone, they still appear in the Following list with the wrong count

## Problem

**User Report**: "i still see watagumo on follow list (it says 3) even though i unfollowed (should say 2)"

### What Was Happening:

1. User unfollows watagumo from search/profile
2. ✅ Optimistic update removes watagumo from `FollowManager.following` array  
3. ✅ Button correctly shows "Follow" instead of "Following"
4. ❌ User navigates to Following list → **watagumo reappears**
5. ❌ Count still shows "3 Following" instead of "2"

### Root Cause:

**FollowListView.onAppear** (line 80-84) ALWAYS refetches the following list from Firebase:

```swift
.onAppear {
    followManager.fetchFollowers(userId: userId, currentUserId: authManager.userId)
    followManager.fetchFollowing(userId: userId, currentUserId: authManager.userId) // ← Always fetches!
}
```

**FollowManager.fetchFollowing** (line 364-366) overwrites the entire array:

```swift
let profiles = try await firebaseService.fetchFollowing(userId: userId)
await MainActor.run {
    self.following = profiles  // ← Overwrites optimistic update!
}
```

**The Race Condition**:
- Client optimistically removes watagumo from following list
- Firebase still has watagumo (Cloud Function hasn't updated yet - eventual consistency)
- `onAppear` refetches → overwrites with stale data → watagumo reappears

## Solution

Only fetch if the list is empty (first load). Don't refetch if already populated (preserves optimistic updates):

### Fix: FollowListView.swift (line 80-90)

```swift
.onAppear {
    // Load both followers and following data to show accurate counts
    // Pass current user ID to batch check follow statuses
    // ✅ FIX: Only fetch if lists are empty (preserves optimistic updates from unfollow)
    if followManager.followers.isEmpty {
        followManager.fetchFollowers(userId: userId, currentUserId: authManager.userId)
    }
    if followManager.following.isEmpty {
        followManager.fetchFollowing(userId: userId, currentUserId: authManager.userId)
    }
}
```

## Why This Works

1. **First visit**: List is empty → fetches from Firebase ✅
2. **After unfollow**: List already populated with optimistic update → skips fetch ✅
3. **Eventual consistency**: Cloud Function updates Firebase, next fetch will be correct ✅
4. **Pull-to-refresh**: Can add explicit refresh that clears list first if needed

## Alternative Solutions Considered

### ❌ Merge Strategy in FollowManager
```swift
// Don't overwrite, merge new profiles
if self.following.isEmpty {
    self.following = profiles
} else {
    // Add new profiles only
}
```
**Rejected**: Doesn't handle removals properly. Complexity not worth it.

### ❌ Debounce/Cooldown Period
```swift
// Skip fetches for X seconds after unfollow
if Date().timeIntervalSince(lastUnfollowTime) < 5 {
    return
}
```
**Rejected**: Arbitrary timing, adds complexity. The "fetch if empty" check is simpler and more reliable.

### ✅ Fetch If Empty (Chosen)
- Simple, clear logic
- Preserves optimistic updates
- Works with existing eventual consistency model

## Testing

**Before fix**:
1. Unfollow someone → they disappear ✅
2. Navigate to Following list → **they reappear** ❌
3. Count shows old value ❌

**After fix**:
1. Unfollow someone → they disappear ✅
2. Navigate to Following list → **they stay gone** ✅
3. Count decrements immediately ✅
4. Next app launch → fetches fresh data from Firebase ✅

## Impact

- **UX**: Following list now respects optimistic updates
- **Performance**: Saves 1 Firebase query per Following list view (only fetches once)
- **Cost**: Reduces unnecessary refetches

## Files Changed

- `Stampbook/Views/Profile/FollowListView.swift` - Added empty check before fetching

## Notes

- This is a general pattern: **Don't blindly refetch on onAppear if data already exists**
- Optimistic updates are valuable for UX but must be preserved until Firebase syncs
- Consider adding pull-to-refresh for users who want to force refresh

