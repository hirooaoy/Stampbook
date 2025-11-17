# Architecture Edge Cases Audit

**Date**: November 17, 2025  
**Context**: After fixing the "feed disappears when viewing profiles" bug

## Recently Fixed ✅

### 1. ProfileManager Posting Global Notifications for Non-Current Users
**Status**: ✅ **FIXED**

**Issue**: UserProfileView created local ProfileManager instances to view OTHER users' profiles. ProfileManager posted `profileDidUpdate` for ANY profile load, causing FeedManager to clear feed cache unnecessarily.

**Fix**: Added `isCurrentUser` parameter to `loadProfile()`. Only posts notification when loading current user's profile.

**Files Changed**:
- `Stampbook/Managers/ProfileManager.swift`
- `Stampbook/Views/Profile/UserProfileView.swift`

---

### 2. Manager Caches Not Cleared on Sign Out (DATA LEAK)
**Status**: ✅ **FIXED - CRITICAL**

**Issue**: When User A signed out and User B signed in, User B would see:
- User A's liked posts (LikeManager cache)
- User A's comment counts (CommentManager cache)
- User A's follow data (FollowManager cache)
- User A's feed (FeedManager - but this was OK, see below)

**Root Cause**: Only ProfileManager's cache was cleared on sign out. Other manager caches persisted in memory AND UserDefaults.

**Fix**: Added cache clearing to `StampbookApp.handleAuthStateChange()`:
```swift
likeManager.clearCache()
commentManager.clearCache()
followManager.clearFollowData()
// FeedManager is @StateObject in FeedView, destroyed on sign out (OK)
```

**Why This Matters**: This is a critical privacy/security issue. Without this fix, users could see each other's private data (likes, follows, cached posts).

**Files Changed**:
- `Stampbook/StampbookApp.swift`

---

### 3. Feed Not Refreshing After NavigationStack Follow
**Status**: ✅ **FIXED**

**Issue**: When users followed someone via NavigationStack navigation (not sheets), the feed wouldn't refresh:
```
Common Flow:
1. Feed → Tap username → UserProfileView
2. Follow @hiroo
3. Back to feed
4. ❌ Feed still stale - doesn't show @hiroo's posts
```

**Root Cause**: NavigationStack navigation doesn't trigger sheet `.onDisappear` handlers. Only sheet dismissals were triggering refresh.

**Why Critical**: This is the organic discovery flow (seeing interesting comments → following users). If broken, users can't discover new people naturally.

**Fix**: Added `.onAppear` handler to `FeedContent` that checks `didFollowingListChange` and refreshes if needed.

**Safety**:
- Boolean flag prevents double-refresh (first handler resets flag to `false`)
- 3-second debounce prevents spam
- Works alongside existing sheet refresh handlers

**Files Changed**:
- `Stampbook/Views/Feed/FeedView.swift`

**Documentation**: See `NAVIGATION_STACK_REFRESH_FIX.md` for detailed analysis and test scenarios.

---

## Reviewed & Safe ✅

### 4. Multiple FeedManager Instances
**Status**: ✅ **SAFE - By Design**

**Pattern**: Two views create local FeedManager instances:
- **FeedView**: Creates `@StateObject private var feedManager = FeedManager()`
- **PostDetailView**: Creates `@StateObject private var feedManager = FeedManager()`

**Why Safe**:
- Each instance listens to `profileDidUpdate` and `stampDidCollect` notifications
- Each clears its own cache when notifications fire
- **FeedView's instance**: Persists across tab switches, holds main feed cache
- **PostDetailView's instance**: Ephemeral, only used to fetch a single post once
- They don't interfere with each other

**Verification**: PostDetailView loads the post into `@State private var post`, so even if FeedManager's cache clears, the UI still shows the post.

---

### 5. stampDidCollect Notification
**Status**: ✅ **SAFE - Correct Usage**

**Who Posts**: `StampsManager` when user collects a stamp
**Who Listens**: `FeedManager` to clear feed cache

**Why Safe**:
- Only fires when the CURRENT user collects a stamp
- Always correct to clear feed cache (need to show newly collected stamp)
- No cross-user contamination possible

**Code References**:
```swift
// StampsManager.swift line 567
NotificationCenter.default.post(name: .stampDidCollect, object: nil)

// FeedManager.swift line 78
@objc private func handleStampCollection(_ notification: Notification) {
    clearCache() // ✅ Correct - always need fresh data after collecting
}
```

---

### 6. followingListDidChange Notification
**Status**: ✅ **DEPRECATED - No Longer Posted**

**Old Behavior**: Posted when user followed/unfollowed someone
**Current Behavior**: Replaced with flag-based system (`FollowManager.didFollowingListChange`)

**Remaining Listener**: `ProfileManager.handleFollowingListChange`
- Still listens to the notification (for compatibility)
- Refreshes current user's profile to get updated follow counts
- **Safe**: Won't fire since notification is never posted

**Note**: Listener can be removed in future cleanup, but keeping it doesn't cause issues.

---

## Potential Edge Cases to Monitor 👀

### 7. Race Condition: Profile Cache During Sign Out
**Status**: ⚠️ **Monitor - Low Risk**

**Scenario**:
1. User signs out
2. ProfileManager clears cache via `clearCachedProfile()`
3. But if a background profile fetch completes AFTER sign out, it might save stale data back to cache

**Current Mitigation**:
- AuthManager sets `userId = nil` on sign out
- Profile loads check `if userId == nil` before proceeding
- Cache uses user-specific keys: `"currentUserProfile_[userId]"`

**Risk Level**: Low - would only show stale profile picture on next launch, resolved after first sync

**To Monitor**: Check if any users report seeing previous user's profile after sign out

---

### 8. ImageManager Profile Picture Cache Invalidation
**Status**: ⚠️ **Monitor - Edge Case Exists**

**Issue**: When viewing another user's profile multiple times, profile pictures are cached by URL hash. If that user updates their profile picture:
1. Firebase URL changes (includes timestamp token)
2. Our cache still has old URL's image
3. Won't clear until disk cache cleanup (when exceeding size limit)

**Current Mitigation**:
- Profile pictures include Firebase tokens in URL (automatic cache busting)
- Disk cache has 200MB limit with automatic cleanup
- Memory cache clears on app restart

**Risk Level**: Low - would show stale profile pic until cache expires

**Potential Fix** (POST-MVP): 
```swift
// When fetching ANY user profile, clear old profile pic from cache
if let oldUrl = cachedProfile?.avatarUrl, oldUrl != newProfile.avatarUrl {
    ImageManager.shared.clearCachedProfilePictures(userId: userId, oldAvatarUrl: oldUrl)
}
```

---

### 9. StampsManager Cache Not Clearing on Sign Out
**Status**: ⚠️ **Verify**

**Question**: Should stamp cache clear when user signs out?

**Current Behavior**: StampsManager has `clearCache()` method, but it's only called:
- Manually for debugging
- Not automatically on sign out

**Why It Might Matter**:
- Stamp data is not user-specific (shared across all users)
- But user's collected stamps status IS user-specific
- If User A collects stamps, signs out, User B signs in → might show wrong collected status briefly

**Current Mitigation**:
- `isCollected()` checks against current user's `userCollection`
- User collection DOES clear on sign out (in `AuthManager.signOut()`)
- Stamp cache is just metadata, not collection status

**Risk Level**: Very Low - metadata cache is safe to persist across users

**Verdict**: ✅ Current behavior is correct

---

## Recommendations

### Short Term (Before Launch)
1. ✅ **DONE**: Fix ProfileManager notification issue
2. Monitor logs for any unexpected notification firing patterns
3. Add debug logging to track when caches are cleared

### Post-MVP Improvements
1. **Refactor UserProfileView** to directly call `FirebaseService.fetchUserProfile()` instead of creating local ProfileManager instances
2. **Consider singleton pattern** for managers that don't need multiple instances
3. **Add context to notifications**: Include userId in notification userInfo to allow conditional cache clearing
4. **Profile picture cache invalidation**: Clear old profile pics when user updates their photo

### Code Quality
- Consider removing the deprecated `followingListDidChange` listener from ProfileManager (safe but unnecessary)
- Add unit tests for notification flow (mock NotificationCenter)
- Document which managers should be singletons vs. instance-per-view

---

## Testing Checklist

When testing notification/cache issues, verify:

1. ✅ Viewing another user's profile doesn't clear feed
2. ✅ Collecting a stamp DOES clear feed cache
3. ✅ Updating your own profile DOES clear feed cache
4. ✅ Following/unfollowing updates profile counts correctly
5. 🔥 **CRITICAL**: Sign out clears all user-specific caches (like manager, comment manager, follow manager)
   - Test: Sign in as User A, like a post, sign out, sign in as User B → should NOT see User A's liked posts
6. ✅ Multiple FeedManager instances don't interfere with each other
7. ⚠️ Profile pictures update when user changes them (may show stale briefly)

---

## Summary

**Critical Issues**: 3 (all fixed ✅)
- Feed disappearing when viewing profiles ✅
- User data leaking between accounts ✅
- Feed not refreshing after NavigationStack follow ✅

**Safe Patterns**: 4 (verified ✅)  
**Low-Risk Edge Cases**: 3 (documented for monitoring 👀)

The architecture is generally sound. The main pattern to watch is: **local manager instances listening to global notifications**. We've now added proper context checking to prevent inappropriate cache invalidation, and ensured all follow/unfollow actions trigger feed refresh regardless of navigation pattern (sheets vs. NavigationStack).

