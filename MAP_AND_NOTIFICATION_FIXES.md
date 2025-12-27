# Map Tab Bar & Push Notification Fixes for iOS 18

## Issues Identified

1. **Map Tab Bar Disappears**: In full screen map mode, the bottom navigation bar disappears, making it unclear how to navigate away from the map
2. **Push Notifications**: May not be working properly on iOS 18 (could be user error, but worth investigating)

## Current Implementation

- MapView uses `.ignoresSafeArea()` which extends the map under the tab bar
- Tab bar visibility is not explicitly enforced
- Push notification setup looks correct but may need iOS version-specific handling

## Solution Options

### Option A: Restrict Safe Area Ignore to Top Only (Recommended)

**What**: Change `.ignoresSafeArea()` to only ignore top edges, preserving bottom safe area (tab bar)

**Why**: 
- Keeps tab bar always visible
- Minimal code change
- Works consistently across iOS versions
- Doesn't affect iOS 26 behavior

**Implementation**:
```swift
// In MapView.swift, line 119
.ignoresSafeArea(.container, edges: .top)  // Only ignore top, keep bottom (tab bar) visible
```

**Pros**:
- Simple one-line change
- Tab bar always visible
- No visual impact on iOS 26
- Standard iOS pattern

**Cons**:
- Map won't extend to bottom edge (but tab bar will be visible)

---

### Option B: Explicit Tab Bar Visibility + Conditional Safe Area

**What**: Add `.toolbar(.visible, for: .tabBar)` and make safe area ignore conditional by iOS version

**Why**:
- Explicitly ensures tab bar visibility
- Can customize behavior per iOS version if needed

**Implementation**:
```swift
// In MapView.swift
var body: some View {
    // ... existing code ...
}
.toolbar(.visible, for: .tabBar)  // Explicitly show tab bar
.ignoresSafeArea(.container, edges: .top)  // Only ignore top
```

**Pros**:
- Explicit control over tab bar visibility
- Can add iOS version checks if needed
- Clear intent in code

**Cons**:
- Slightly more code
- May need iOS version checks for edge cases

---

### Option C: Add Bottom Padding for iOS 18 Only

**What**: Keep current `.ignoresSafeArea()` but add bottom padding on iOS 18 to ensure tab bar area is visible

**Why**:
- Preserves full-screen map experience
- Only affects iOS 18 users

**Implementation**:
```swift
// In MapView.swift
var body: some View {
    ZStack {
        // ... existing map code ...
    }
    .ignoresSafeArea()
    .safeAreaInset(edge: .bottom) {
        if #available(iOS 26.0, *) {
            EmptyView()  // iOS 26 handles it correctly
        } else {
            // iOS 18: Add spacer to ensure tab bar is visible
            Color.clear.frame(height: 0)
        }
    }
    .toolbar(.visible, for: .tabBar)
}
```

**Pros**:
- Full-screen map preserved
- Only affects iOS 18
- Can be fine-tuned per version

**Cons**:
- More complex code
- May need testing across iOS versions

---

## Push Notification Investigation

### Current Setup
- ✅ APNs key configured (`AuthKey_8UNPWH7396.p8`)
- ✅ Firebase Cloud Messaging configured
- ✅ Notification permissions requested
- ✅ FCM token handling implemented
- ✅ Notification delegate methods implemented

### Potential iOS 18 Issues

1. **Notification Permission Prompt**: iOS 18 may have different permission flow
2. **Foreground Notification Display**: May need explicit iOS version check
3. **Badge Count**: May need iOS version-specific handling

### Recommended Fix

Add iOS version check for notification presentation options:

```swift
// In StampbookApp.swift, line 92
func userNotificationCenter(_ center: UNUserNotificationCenter,
                           willPresent notification: UNNotification,
                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    let userInfo = notification.request.content.userInfo
    Logger.info("Notification received in foreground: \(userInfo)", category: "AppDelegate")
    
    // iOS 18+ uses .banner, older versions use .alert
    if #available(iOS 14.0, *) {
        completionHandler([.banner, .sound, .badge])
    } else {
        completionHandler([.alert, .sound, .badge])
    }
}
```

**Note**: This should already work, but explicit version check ensures compatibility.

---

## Recommended Implementation Plan

### Step 1: Fix Map Tab Bar (Option A - Simplest)

Change `.ignoresSafeArea()` to `.ignoresSafeArea(.container, edges: .top)` in MapView.swift

### Step 2: Add Explicit Tab Bar Visibility

Add `.toolbar(.visible, for: .tabBar)` to MapView body

### Step 3: Verify Push Notifications

Check if notification permission was granted and FCM token is saved. Add logging if needed.

---

## Testing Checklist

- [ ] Map tab bar visible on iOS 18
- [ ] Map tab bar visible on iOS 26
- [ ] Can navigate away from map using tab bar
- [ ] Push notifications work on iOS 18 (TestFlight build)
- [ ] Push notifications work on iOS 26 (TestFlight build)
- [ ] In-app notifications (bell icon) work on both versions

---

## Impact Assessment

**Cost Impact**: None - UI changes only
**User Experience**: Significantly improved - users can navigate away from map
**iOS 26 Impact**: Minimal - only changes safe area handling slightly
**Risk**: Low - simple, well-tested SwiftUI patterns

