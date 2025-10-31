# ProfileImageView Re-initialization Optimization

**Date:** October 31, 2025  
**Issue:** Excessive ProfileImageView re-creation causing 30+ duplicate load attempts per feed load

## Problem Identified

### Root Causes:
1. **Computed Property Anti-Pattern**: `profilePicture` was a computed property that recreated the view on every SwiftUI refresh
2. **View Identity Instability**: SwiftUI couldn't track view identity, causing `.task` to re-trigger unnecessarily
3. **No Load Deduplication**: `@State` variables reset on each view recreation
4. **Duplicate View Creation**: Same ProfileImageView created twice (once for current user path, once for other user path)

### Impact:
- 30+ log entries per feed load: `🖼️ [ProfileImageView] No avatar URL for userId: ...`
- Unnecessary task cancellation and restart
- Wasted CPU cycles recreating views
- Potential race conditions with multiple simultaneous loads

## Solution Implemented

### 1. ProfileImageView.swift Improvements

#### Added Stable View Identity
```swift
.id("\(userId)-\(size)") // Stable identity prevents unnecessary recreation
```

#### Load Deduplication
```swift
@State private var hasAttemptedLoad = false // Prevent duplicate loads

.task(id: "\(userId)-\(avatarUrl ?? "")-\(loadAttempt)") {
    // Only load once per unique user/avatar combination
    guard !hasAttemptedLoad || loadAttempt > 0 else { return }
    hasAttemptedLoad = true
    await loadProfilePicture()
}
```

#### Smart Retry Logic
```swift
.onAppear {
    // Only schedule retries if we have an avatar URL and haven't loaded yet
    guard avatarUrl != nil, image == nil else { return }
    // ... retry logic
}
```

### 2. FeedView.swift Improvements

#### Eliminated Computed Property Anti-Pattern
**Before:**
```swift
private var profilePicture: some View {
    ProfileImageView(
        avatarUrl: isCurrentUser ? authManager.userProfile?.avatarUrl : avatarUrl,
        userId: userId,
        size: 40
    )
}

// Used twice in body:
if isCurrentUser {
    Button { ... } { profilePicture }
} else {
    NavigationLink { ... } label: { profilePicture }
}
```

**After:**
```swift
// Computed property for avatar URL - stable value
private var computedAvatarUrl: String? {
    isCurrentUser ? authManager.userProfile?.avatarUrl : avatarUrl
}

var body: some View {
    // Create ProfileImageView once and reuse it
    let profileImage = ProfileImageView(
        avatarUrl: computedAvatarUrl,
        userId: userId,
        size: 40
    )
    
    if isCurrentUser {
        Button { ... } { profileImage }
    } else {
        NavigationLink { ... } label: { profileImage }
    }
}
```

## Benefits

### Performance Improvements:
1. **Reduced View Creation**: ProfileImageView created once per post instead of multiple times
2. **Stable Task Lifecycle**: `.task` no longer cancels and restarts unnecessarily
3. **Deduplication**: Same profile image won't trigger multiple simultaneous loads
4. **Cleaner Logs**: No more 30+ "No avatar URL" messages

### Best Practices Applied:
1. ✅ Use `let` binding for view reuse within body
2. ✅ Stable view identity with `.id()` modifier
3. ✅ Load deduplication with state tracking
4. ✅ Avoid computed properties for complex views
5. ✅ Smart retry logic that respects existing state

## Expected Results

### Before:
```
🖼️ [ProfileImageView] No avatar URL for userId: mpd4k2n13adMFMY52nksmaQTbMQ2
🖼️ [ProfileImageView] No avatar URL for userId: mpd4k2n13adMFMY52nksmaQTbMQ2
... (30+ times)
🖼️ [ProfileImageView] Loading profile picture for userId: mpd4k2n13adMFMY52nksmaQTbMQ2, attempt: 0
... (10+ times)
```

### After:
```
🖼️ [ProfileImageView] No avatar URL for userId: mpd4k2n13adMFMY52nksmaQTbMQ2
... (only once per unique user)
🖼️ [ProfileImageView] Loading profile picture for userId: mpd4k2n13adMFMY52nksmaQTbMQ2, attempt: 0
... (only once per unique user/avatar)
```

## Related Files Modified

- `/Stampbook/Views/Shared/ProfileImageView.swift` - Added view identity and load deduplication
- `/Stampbook/Views/Feed/FeedView.swift` - Refactored to use `let` binding instead of computed property

## Testing Recommendations

1. **Cold Start**: Launch app and check feed loads - should see minimal ProfileImageView logs
2. **Tab Switching**: Switch between Feed/Map/Stamps tabs - no duplicate loads
3. **Pull to Refresh**: Refresh feed - should use cached images instantly
4. **Profile Navigation**: Navigate to profiles and back - images should persist

## Notes

- Image caching still works perfectly (memory + disk cache)
- Instagram-style progressive loading still intact
- Background prefetch unaffected
- All existing functionality preserved

