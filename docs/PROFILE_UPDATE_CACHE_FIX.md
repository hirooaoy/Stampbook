# Cache Synchronization Fixes

**Date:** November 6, 2025  
**Issues:** Multiple cache synchronization bugs causing stale data across the app

## Problem Analysis

When a user updated their profile (photo or displayName) in ProfileEditView, the changes weren't reflected in:
1. **FeedView**: Feed posts showed old profile picture and name
2. **ProfileImageView**: Cached images weren't refreshed
3. **Pull-to-refresh**: Didn't help because feed data was cached

### Root Causes

1. **No cache invalidation**: FeedManager cached feed posts with stale user data
2. **No notification system**: Views had no way to know when profile updated
3. **Disk persistence**: Feed cache was saved to disk, persisting stale data even after app restart
4. **ProfileImageView not reactive**: Didn't respond to avatarUrl changes

## Solution Implemented

### 1. Profile Update Notification System

**ProfileManager.swift** - Added notification when profile updates:
```swift
extension Notification.Name {
    static let profileDidUpdate = Notification.Name("profileDidUpdate")
}

func updateProfile(_ profile: UserProfile) {
    currentUserProfile = profile
    
    // Notify the app that profile has been updated
    NotificationCenter.default.post(
        name: .profileDidUpdate,
        object: nil,
        userInfo: ["profile": profile]
    )
}
```

### 2. FeedManager Cache Invalidation

**FeedManager.swift** - Listen for profile updates and clear cache:
```swift
init() {
    // Listen for profile updates to invalidate feed cache
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleProfileUpdate),
        name: .profileDidUpdate,
        object: nil
    )
}

@objc private func handleProfileUpdate(_ notification: Notification) {
    // Clear all cached feed data (memory and disk)
    clearCache()
    
    // Clear published arrays to force refresh on next view
    DispatchQueue.main.async {
        self.feedPosts = []
        self.myPosts = []
    }
}
```

### 3. ProfileImageView Reactivity

**ProfileImageView.swift** - Made view react to avatarUrl changes:
```swift
.id("\(userId)-\(avatarUrl ?? "nil")-\(size)") // Add avatarUrl to id to force refresh
.task(id: avatarUrl) { // Retrigger task when avatarUrl changes
    // Load image logic...
}
.onChange(of: avatarUrl) { oldValue, newValue in
    // Reset state when avatarUrl changes
    if oldValue != newValue {
        hasAttemptedLoad = false
        image = nil
    }
}
```

### 4. FeedView Profile Update Listener

**FeedView.swift** - Added Combine listener for profile updates:
```swift
import Combine

@State private var profileUpdateListener: AnyCancellable?

.onAppear {
    // Listen for profile updates to refresh feed with new avatar/name
    profileUpdateListener = NotificationCenter.default.publisher(for: .profileDidUpdate)
        .sink { _ in
            // Feed will be automatically refreshed next time tab is visited
            // FeedManager already cleared the cache
        }
}
```

## How It Works Now

### User Flow
1. User edits profile photo/name in ProfileEditView
2. ProfileEditView calls `profileManager.updateProfile(updatedProfile)`
3. ProfileManager posts `.profileDidUpdate` notification
4. FeedManager receives notification and clears all cached feed data (memory + disk)
5. ProfileImageView detects avatarUrl change and reloads image
6. Next time user opens Feed tab, fresh data is fetched from Firestore
7. New profile photo/name appears everywhere

### Benefits
- ✅ Profile updates appear immediately in ProfileImageView (using new avatarUrl)
- ✅ Feed refreshes with new data next time tab is visited
- ✅ Disk cache is cleared, preventing stale data after app restart
- ✅ No need to kill the app or manually refresh

## Testing Checklist

Test the following scenarios to verify the fix:

### 1. Profile Photo Update
- [ ] Edit profile photo in Profiletab
- [ ] Check ProfileEditView shows new photo immediately
- [ ] Navigate to Feed tab
- [ ] Verify your profile pic in feed posts shows new photo
- [ ] Navigate to Stamps tab
- [ ] Verify your profile pic in collected stamps shows new photo
- [ ] Kill and restart app
- [ ] Verify new photo still appears everywhere

### 2. Display Name Update
- [ ] Edit display name in Profile tab
- [ ] Navigate to Feed tab
- [ ] Verify your name in feed posts shows new name
- [ ] Pull to refresh (should show new name)
- [ ] Kill and restart app
- [ ] Verify new name still appears

### 3. Username Update
- [ ] Edit username in Profile tab
- [ ] Navigate to Feed tab
- [ ] Verify your username in feed posts shows new username
- [ ] Kill and restart app
- [ ] Verify new username still appears

### 4. Multiple Updates
- [ ] Update both photo and name
- [ ] Verify both update correctly in all views
- [ ] Switch between tabs multiple times
- [ ] Verify consistency across all views

## Technical Notes

### Cache Strategy
- **Memory cache**: ImageCacheManager stores recently used images
- **Disk cache**: FeedManager persists feed to disk for instant cold start
- **Invalidation**: Both cleared when profile updates

### Notification Pattern
Used NotificationCenter for decoupled communication:
- ProfileManager doesn't need to know about FeedManager
- FeedManager doesn't need to know about ProfileEditView
- Easy to add more listeners in future (e.g., CommentView, UserProfileView)

### Alternative Approaches Considered
1. **Combine publishers**: More SwiftUI-native but adds complexity
2. **Manual refresh on tab switch**: Would miss updates if already on tab
3. **Polling**: Inefficient, wastes resources

Went with NotificationCenter as it's:
- Simple and well-understood
- Works across SwiftUI and UIKit
- No additional dependencies
- Easy to debug

## Files Modified

### Profile Update Fix
1. `Stampbook/Managers/ProfileManager.swift` - Added notification posting
2. `Stampbook/Managers/FeedManager.swift` - Added cache invalidation listener
3. `Stampbook/Views/Shared/ProfileImageView.swift` - Made reactive to avatarUrl changes  
4. `Stampbook/Views/Feed/FeedView.swift` - Added Combine import and profile update listener

### Comment Count Fix
5. `Stampbook/Views/Feed/FeedView.swift` - Hooked up comment count callback (line 369-371)
6. `Stampbook/Managers/FeedManager.swift` - Extended updatePostCommentCount to update both "All" and "Only Yours" feeds

## Additional Bug Fixed: Comment Counts

### Problem
When you added or deleted a comment, the count in the feed didn't update until app restart.

### Root Cause
`CommentManager` had a callback mechanism (`onCommentCountChanged`) but it was never hooked up in FeedView.

### Fix Applied
**FeedView.swift** - Connected the callback:
```swift
.onAppear {
    // Hook up comment count updates to feed
    commentManager.onCommentCountChanged = { [weak feedManager] postId, newCount in
        feedManager?.updatePostCommentCount(postId: postId, newCount: newCount)
    }
}
```

**FeedManager.swift** - Extended to update both feeds:
```swift
func updatePostCommentCount(postId: String, newCount: Int) {
    // Update in "All" feed
    if let index = feedPosts.firstIndex(where: { $0.id == postId }) { ... }
    
    // Update in "Only Yours" feed  
    if let index = myPosts.firstIndex(where: { $0.id == postId }) { ... }
}
```

## Future Improvements

- [ ] Consider updating feed posts in-place for profile updates (more efficient than clearing cache)
- [ ] Add loading indicator when feed is refreshing after profile update
- [ ] Extend to other profile fields (bio, etc.) if needed
- [ ] Consider WebSocket for real-time updates across devices

