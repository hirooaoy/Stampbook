# Instant Notification Badge Implementation

**Date**: November 13, 2025  
**Status**: ✅ Implemented

## Problem

Users had to wait up to 5 minutes to see the notification red dot after receiving a notification (follow, like, comment). The app only checked for unread notifications via 5-minute polling, so the badge felt laggy and broken.

### Example Scenario (BEFORE)
```
12:00 PM - Watagumostudio follows Hiroo
12:00 PM - Notification created in Firebase
12:01 PM - Hiroo opens app and switches to Feed tab
12:01 PM - ❌ Red dot DOES NOT appear
12:02 PM - Hiroo refreshes feed  
12:02 PM - ❌ Red dot STILL DOES NOT appear
12:05 PM - 5-minute polling timer fires
12:05 PM - ✅ Red dot FINALLY appears (5 minutes late!)
```

## Solution

Added throttled on-demand notification checks when:
1. **FeedView appears** (user switches to feed tab)
2. **User pulls-to-refresh** in the feed

Throttled to max once per 30 seconds to prevent excessive Firestore reads.

### Example Scenario (AFTER)
```
12:00 PM - Watagumostudio follows Hiroo
12:00 PM - Notification created in Firebase
12:01 PM - Hiroo opens app and switches to Feed tab
12:01 PM - ✅ Red dot appears IMMEDIATELY (within 1 second!)
```

## Implementation

### 1. NotificationManager.swift

Added throttling mechanism:
```swift
// Throttling for on-demand checks (prevent excessive reads)
private var lastCheckTime: Date?
private let throttleInterval: TimeInterval = 30 // Check at most once per 30 seconds
```

Added new function:
```swift
/// Check for unread notifications if throttle allows (used for feed view/refresh)
/// Throttled to once per 30 seconds to prevent excessive reads
func checkHasUnreadNotificationsIfNeeded(userId: String) async {
    // Check if we're within throttle interval
    if let lastCheck = lastCheckTime {
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
        if timeSinceLastCheck < throttleInterval {
            print("⏭️ [NotificationManager] Skipping check - throttled (\(Int(timeSinceLastCheck))s ago, need \(Int(throttleInterval))s)")
            return
        }
    }
    
    print("🔔 [NotificationManager] Checking for unread notifications (on-demand)")
    await checkHasUnreadNotifications(userId: userId)
}
```

### 2. FeedView.swift

Added check when feed appears:
```swift
// If user is already signed in when view appears (handles first launch + returning user)
if let userId = authManager.userId, authManager.isSignedIn, profileManager.currentUserProfile != nil {
    Task {
        // Check for unread notifications when feed appears (throttled to 30s)
        await notificationManager.checkHasUnreadNotificationsIfNeeded(userId: userId)
        
        // Load feed content
        await feedManager.loadFeed(userId: userId, stampsManager: stampsManager, forceRefresh: false)
    }
}
```

Added check on pull-to-refresh:
```swift
private func refreshFeedData() async {
    guard let userId = authManager.userId else { return }
    
    // Check for unread notifications (throttled to prevent excessive reads)
    await notificationManager.checkHasUnreadNotificationsIfNeeded(userId: userId)
    
    // ... rest of refresh logic
}
```

## Cost Analysis

### Current Cost (Polling Only)
- Checks every 5 minutes while app is open
- Average user: 2 hours/day active = 24 checks/day = 720 checks/month
- 100 users × 720 checks = **72,000 reads/month = $4.32/month**

### New Cost (Polling + On-Demand)
- **Polling**: 72,000 reads/month (unchanged)
- **On-demand checks**:
  - Average user opens feed ~20 times/day
  - With 30-second throttle: ~15 actual checks/day (duplicates ignored)
  - 15 checks/day × 30 days = 450 checks/month/user
  - 100 users × 450 = 45,000 reads/month
- **Total**: 72,000 + 45,000 = 117,000 reads/month = **$7.02/month**

### Cost Increase
- **+$2.70/month for 100 users**
- **+$0.027 per user/month** (less than 3 cents per user!)

### Pricing Breakdown
- Firestore reads: $0.06 per 100,000 reads
- 45,000 extra reads/month = $0.027/month per 100 users

## Benefits

1. **Instant feedback**: Users see notification badge within 1 second
2. **Better UX**: App feels responsive and "real-time"
3. **Minimal cost**: Only $0.027 per user per month
4. **Still cost-efficient**: Throttling prevents spam, polling handles background updates
5. **Best of both worlds**: Instant on-demand + efficient polling

## Testing

Test the implementation:

1. Sign in as user A
2. Have user B follow user A
3. User A switches to feed tab → Red dot should appear within 1 second ✅
4. Test throttling: Switch away and back quickly (< 30s) → Should skip check ✅
5. Test pull-to-refresh → Should also check for notifications ✅

## Technical Notes

- **Throttling**: Prevents excessive reads if user spam-switches tabs
- **Polling continues**: 5-minute polling still runs for background updates
- **No breaking changes**: All existing functionality preserved
- **Graceful degradation**: If check fails, polling will catch it within 5 minutes
- **Thread-safe**: All updates on @MainActor

## Files Modified

1. `Stampbook/Managers/NotificationManager.swift`
   - Added throttling properties
   - Added `checkHasUnreadNotificationsIfNeeded()` function
   - Updated `checkHasUnreadNotifications()` to track last check time

2. `Stampbook/Views/Feed/FeedView.swift`
   - Added notification check in `.onAppear` 
   - Added notification check in `refreshFeedData()`

## Future Optimizations

If needed, we could:
1. Adjust throttle interval (currently 30s, could go to 60s)
2. Only check on feed appear, not on refresh
3. Use Firebase Cloud Messaging (FCM) for push notifications (more complex)

But for MVP with 100 users, current implementation is perfect balance of UX and cost.

