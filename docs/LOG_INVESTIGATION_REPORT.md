# Log Investigation Report

**Date:** November 12, 2025  
**Investigator:** AI Assistant  
**Scope:** App launch logs analysis for bugs and performance issues

---

## Executive Summary

Four critical issues identified in app launch logs:

1. **CRITICAL UI BUG:** Sheet presentation warning (50+ occurrences) - Active issue affecting user experience
2. **PERFORMANCE BUG:** NotificationRow redundant profile fetching (13x for same user) - Wasting Firebase reads
3. **LOGGING BUG:** Cost savings calculation showing incorrect math (0% reported as 94%)
4. **WARNING:** Network connection metadata access - May indicate timing issue

---

## Issue #1: Sheet Presentation Warning (CRITICAL)

### Symptoms
```
Currently, only presenting a single sheet is supported.
The next sheet will be presented when the currently presented sheet gets dismissed.
```

**Frequency:** 50+ times in single app launch  
**Severity:** Critical - Affects user experience

### Root Cause Analysis

SwiftUI enforces a **one-sheet-at-a-time rule** per view hierarchy. This warning occurs when multiple `@State` boolean flags controlling sheets are set to `true` simultaneously, or when child views inherit multiple sheet modifiers from parent views.

#### Problematic Pattern Identified

**StampsView** has **12 sheet modifiers** chained on a single view:

```swift:580:631:Stampbook/Views/Profile/StampsView.swift
.sheet(isPresented: $showFeedback) { ... }
.sheet(isPresented: $showProblemReport) { ... }
.sheet(isPresented: $showAccountDeletion) { ... }
.sheet(isPresented: $showDataDownload) { ... }
.sheet(isPresented: $showAboutStampbook) { ... }
.sheet(isPresented: $showForLocalBusiness) { ... }
.sheet(isPresented: $showForCreators) { ... }
.sheet(isPresented: $showSuggestStamp) { ... }
.sheet(isPresented: $showSuggestCollection) { ... }
.sheet(item: $welcomeStamp) { stamp in ... }
.sheet(isPresented: $showInviteCodeSheet) { ... }
.sheet(isPresented: $showEditProfile) { ... }
```

**FeedView** has **13 sheet modifiers** (including 3 nested in FeedCard):

```swift:344:396:Stampbook/Views/Feed/FeedView.swift
.sheet(isPresented: $showNotifications) { ... }
.sheet(isPresented: $showUserSearch) { ... }
.sheet(isPresented: $showFeedback) { ... }
.sheet(isPresented: $showProblemReport) { ... }
.sheet(isPresented: $showAboutStampbook) { ... }
.sheet(isPresented: $showForLocalBusiness) { ... }
.sheet(isPresented: $showForCreators) { ... }
.sheet(isPresented: $showSuggestStamp) { ... }
.sheet(isPresented: $showSuggestCollection) { ... }
.sheet(isPresented: $showInviteCodeSheet) { ... }

// Inside FeedCard (nested):
.sheet(isPresented: $showNotesEditor) { ... }
.sheet(isPresented: $showComments) { ... }
.sheet(isPresented: $showLikes) { ... }
```

### Why This Is A Problem

1. **SwiftUI View Updates:** When the view body is re-evaluated (which happens frequently during app launch), SwiftUI checks ALL sheet modifiers
2. **Race Conditions:** Multiple ProfileImageViews rendering simultaneously (6+ in feed) can trigger state changes that affect parent views
3. **Nested Sheets:** FeedCard is rendered multiple times (once per post), creating duplicate sheet modifier registrations
4. **State Propagation:** `onChange` modifiers throughout the view hierarchy can inadvertently trigger state changes that cascade to sheet presentation flags

### Evidence From Logs

The warning appears in clusters:

```
⏱️ [FeedManager] UI updated with 6 posts
Currently, only presenting a single sheet is supported. (x50)
⏱️ [ProfileImageView] Profile picture loaded...
```

This timing suggests the warnings fire when:
- Feed posts are rendered (6 FeedCards = 6 x 3 sheet modifiers = 18 potential sheet registrations)
- Profile images load (triggering view updates)
- StampsView and FeedView load simultaneously in TabView

### Impact

- **User Experience:** Sheets may not appear when tapped
- **Performance:** SwiftUI debugging overhead from warning spam
- **Reliability:** Unpredictable sheet behavior, especially under load
- **App Store Review Risk:** Could be flagged during review if severe enough

### Recommended Fix

**Option 1: Sheet Coordinator Pattern (Preferred)**

Create a single sheet coordinator with enum-based routing:

```swift
enum SheetDestination: Identifiable {
    case feedback
    case problemReport
    case accountDeletion
    case dataDownload
    case aboutStampbook
    case forLocalBusiness
    case forCreators
    case suggestStamp
    case suggestCollection
    case welcomeStamp(Stamp)
    case inviteCode
    case editProfile
    
    var id: String {
        switch self {
        case .feedback: return "feedback"
        case .problemReport: return "problemReport"
        // ... etc
        case .welcomeStamp(let stamp): return "welcomeStamp-\(stamp.id)"
        }
    }
}

// In StampsView:
@State private var activeSheet: SheetDestination?

.sheet(item: $activeSheet) { destination in
    switch destination {
    case .feedback:
        SimpleFeedbackView()
            .environmentObject(authManager)
    case .problemReport:
        SimpleProblemReportView()
            .environmentObject(authManager)
    // ... handle all cases
    }
}
```

**Benefits:**
- Single sheet modifier per view
- Guaranteed one-sheet-at-a-time
- Easier to debug sheet state
- Better testability

**Option 2: Extract Sheet-Heavy Logic to Dedicated Views**

Move groups of related sheets into separate child views:

```swift
struct SettingsSheetHost: View {
    @Binding var activeSheet: SettingsSheet?
    
    var body: some View {
        EmptyView()
            .sheet(item: $activeSheet) { sheet in
                // Handle settings-related sheets
            }
    }
}
```

**Option 3: Immediate Mitigation (Quick Fix)**

Add guards to ensure only one sheet flag can be true at a time:

```swift
private func showSheet(_ type: SheetType) {
    // Reset all other sheet flags
    showFeedback = false
    showProblemReport = false
    // ... reset all flags
    
    // Then set the desired one
    switch type {
    case .feedback: showFeedback = true
    // ...
    }
}
```

---

## Issue #2: NotificationRow Redundant Profile Fetches (PERFORMANCE BUG)

### Symptoms

```
🐌 [NotificationRow] Fetching profile individually for LGp7cMqB2tSEVU1O7NEvR0Xib7y2
```

**Frequency:** 13 identical calls for the same user  
**Expected:** 0 calls (should use pre-fetched profile from batch)  
**Actual Firebase Reads:** 13 wasted reads (1 batch read + 13 redundant individual reads)

### Root Cause Analysis

The batch profile optimization in `NotificationView` IS working:

```swift:95:127:Stampbook/Views/NotificationView.swift
.task {
    // Initial load
    if let userId = authManager.userId {
        await notificationManager.fetchNotifications(userId: userId)
        isInitialLoad = false
        
        // ✅ OPTIMIZATION: Batch fetch all actor profiles (94% cost reduction)
        let uniqueActorIds = Array(Set(notificationManager.notifications.map { $0.actorId }))
        
        if !uniqueActorIds.isEmpty {
            do {
                let profiles = try await FirebaseService.shared.fetchProfilesBatched(userIds: uniqueActorIds)
                
                // Store in dictionary for O(1) lookup
                actorProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
                
                print("✅ [NotificationView] Batch fetched \(profiles.count) profiles in ...")
            } catch {
                print("⚠️ [NotificationView] Batch profile fetch failed: \(error.localizedDescription)")
            }
        }
    }
}
```

**However, the NotificationRow is STILL fetching individually:**

```swift:182:199:Stampbook/Views/NotificationView.swift
.task {
    // ✅ OPTIMIZED: Use pre-fetched profile if available (instant rendering)
    if let preFetched = preFetchedProfile {
        actorProfile = preFetched
        #if DEBUG
        print("⚡️ [NotificationRow] Using pre-fetched profile for \(notification.actorId)")
        #endif
    } else {
        // Fallback: Fetch individually (only happens if batch fetch failed)
        #if DEBUG
        print("🐌 [NotificationRow] Fetching profile individually for \(notification.actorId)")
        #endif
        do {
            actorProfile = try await FirebaseService.shared.fetchUserProfile(userId: notification.actorId)
        } catch {
            print("❌ Error fetching actor profile: \(error.localizedDescription)")
        }
    }
}
```

### The Real Problem: SwiftUI Rendering Race Condition

**NotificationRow renders 13 times BEFORE actorProfiles dictionary is populated.**

Timeline:
1. `NotificationView.body` renders
2. `LazyVStack` starts rendering `NotificationRow` views
3. Each `NotificationRow` immediately executes its `.task` modifier
4. At this point, `actorProfiles` is still `[:]` (empty dictionary)
5. `preFetchedProfile` is `nil` for all rows
6. All 13 rows fall back to individual fetching
7. Batch fetch completes AFTER individual fetches already started

### Why This Happens

`LazyVStack` + `.task` modifier creates a race condition:

- **LazyVStack** renders views as they appear in viewport
- **`.task`** executes immediately when view appears
- **Parent `.task`** runs concurrently, not sequentially
- SwiftUI doesn't guarantee parent `.task` completes before child `.task` starts

### Evidence From Logs

```
🔄 [NotificationView] Batch fetching 1 actor profiles...
🐌 [NotificationRow] Fetching profile individually for LGp7cMqB2tSEVU1O7NEvR0Xib7y2 (x13)
✅ [NotificationView] Batch fetched 1 profiles in 0.055s
```

The batch fetch START log appears, then immediately all 13 individual fetches happen, THEN the batch fetch completes. This proves the rows are rendering before the batch completes.

### Impact

- **Firebase Reads:** 14x instead of 1x (13 redundant reads per user per notification load)
- **Cost:** At scale (50 notifications, 10 unique users): 50 + 10 = 60 reads instead of 10 reads (6x cost)
- **Performance:** 13 concurrent Firebase calls instead of 1 batched call
- **Cache Pollution:** 13 redundant cache entries

### Recommended Fix

**Option 1: Block Rendering Until Batch Completes (Preferred)**

```swift
struct NotificationView: View {
    @State private var actorProfiles: [String: UserProfile] = [:]
    @State private var hasFetchedProfiles = false // NEW
    
    var body: some View {
        NavigationStack {
            ZStack {
                if notificationManager.isLoading && isInitialLoad {
                    ProgressView()
                } else if !hasFetchedProfiles { // NEW: Show loading during profile batch
                    ProgressView("Loading profiles...")
                } else if notificationManager.notifications.isEmpty {
                    // Empty state
                } else {
                    // Notifications list - only renders AFTER profiles are fetched
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notificationManager.notifications) { notification in
                                NotificationRow(
                                    notification: notification,
                                    preFetchedProfile: actorProfiles[notification.actorId],
                                    onProfileTap: { ... },
                                    onPostTap: { ... }
                                )
                            }
                        }
                    }
                }
            }
            .task {
                if let userId = authManager.userId {
                    await notificationManager.fetchNotifications(userId: userId)
                    isInitialLoad = false
                    
                    // Batch fetch profiles BEFORE rendering list
                    let uniqueActorIds = Array(Set(notificationManager.notifications.map { $0.actorId }))
                    
                    if !uniqueActorIds.isEmpty {
                        do {
                            let profiles = try await FirebaseService.shared.fetchProfilesBatched(userIds: uniqueActorIds)
                            actorProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
                        } catch {
                            print("⚠️ [NotificationView] Batch profile fetch failed")
                        }
                    }
                    
                    hasFetchedProfiles = true // NEW: Allow rendering
                    
                    await notificationManager.markAllAsRead(userId: userId)
                }
            }
        }
    }
}
```

**Option 2: Remove `.task` from NotificationRow**

Since profiles are pre-fetched, the row shouldn't need to fetch at all:

```swift
struct NotificationRow: View {
    let notification: AppNotification
    let actorProfile: UserProfile // NOT optional - require it
    let stamp: Stamp? // Fetch this in parent view too
    
    var body: some View {
        // Just render - no fetching
        HStack {
            ProfileImageView(
                avatarUrl: actorProfile.avatarUrl,
                userId: notification.actorId,
                size: 36
            )
            // ...
        }
    }
}
```

**Option 3: Add Delay to NotificationRow `.task`**

```swift
.task {
    // Wait for batch fetch to complete (hack, but works)
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    if let preFetched = preFetchedProfile {
        actorProfile = preFetched
    } else {
        // Fallback
    }
}
```

---

## Issue #3: Cost Savings Calculation Bug (LOGGING BUG)

### Symptoms

```
💰 [NotificationView] Cost savings: 1 reads → 1 reads (94% reduction)
```

**Math doesn't add up:** 1 read to 1 read = 0% reduction, not 94%

### Root Cause

```swift:121:121:Stampbook/Views/NotificationView.swift
print("💰 [NotificationView] Cost savings: \(uniqueActorIds.count) reads → \((uniqueActorIds.count + 9) / 10) reads (94% reduction)")
```

**The Problem:**
- Formula assumes `uniqueActorIds.count` represents "old way" (individual fetches)
- But when there's only 1 unique actor, formula becomes: `1 reads → ((1 + 9) / 10) reads = 1 reads`
- The "94% reduction" is **hardcoded**, not calculated

**Actual calculation for 94% reduction:**
- Should be: `((old - new) / old) * 100`
- For 50 actors: `((50 - 5) / 50) * 100 = 90%` ✓
- For 1 actor: `((1 - 1) / 1) * 100 = 0%` (not 94%)

### Impact

- **Misleading metrics** in production logs
- **False confidence** in optimization effectiveness
- **Debugging confusion** when troubleshooting costs

### Recommended Fix

```swift
let oldReads = uniqueActorIds.count
let newReads = (uniqueActorIds.count + 9) / 10 // Batch size 10
let reduction = oldReads > 0 ? Int(((Double(oldReads - newReads) / Double(oldReads)) * 100)) : 0

print("💰 [NotificationView] Cost savings: \(oldReads) reads → \(newReads) reads (\(reduction)% reduction)")
```

**Expected output:**
- 1 actor: `1 reads → 1 reads (0% reduction)`
- 10 actors: `10 reads → 1 reads (90% reduction)`
- 50 actors: `50 reads → 5 reads (90% reduction)`

---

## Issue #4: Network Connection Warnings (MINOR)

### Symptoms

```
nw_connection_copy_protocol_metadata_internal_block_invoke [C6] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_connected_local_endpoint_block_invoke [C6] Client called nw_connection_copy_connected_local_endpoint on unconnected nw_connection
nw_connection_copy_connected_remote_endpoint_block_invoke [C6] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection
```

### Context

These warnings appear right before:
```
✅ Unliked post: mpd4k2n13adMFMY52nksmaQTbMQ2-us-ca-sf-ballast
✅ Like synced to Firebase: mpd4k2n13adMFMY52nksmaQTbMQ2-us-ca-sf-ballast -> false
```

### Root Cause

Apple's Network framework warnings indicating code is trying to access connection metadata (local/remote endpoints, protocol info) **before** the network connection is fully established.

This typically happens when:
1. A network request is made
2. Code tries to inspect the connection immediately
3. Connection hasn't completed TCP/TLS handshake yet

### Likely Source

Firebase SDK or URLSession code is checking connection details too early. This is usually internal to Firebase/URLSession and not directly controllable by app code.

### Impact

- **Functional:** None (these are warnings, not errors)
- **Performance:** Negligible
- **Logging:** Noise in console

### Recommended Fix

**No fix required** - this is a Firebase SDK timing issue, not an app bug. However, if this becomes frequent:

1. Check if using custom URLSession configuration with aggressive timeouts
2. Verify Firebase SDK is up to date
3. Consider adding retry logic with exponential backoff if requests are failing

---

## Priority Recommendations

### Immediate Action (This Sprint)

1. **Fix Sheet Presentation Warning** - Implement Sheet Coordinator pattern in StampsView and FeedView
   - **Impact:** Eliminates 50+ warnings, improves sheet reliability
   - **Effort:** 4-6 hours
   - **Risk:** Low (well-established pattern)

2. **Fix NotificationRow Redundant Fetches** - Block rendering until batch completes
   - **Impact:** Reduces Firebase reads from 14x to 1x (93% cost reduction)
   - **Effort:** 1-2 hours
   - **Risk:** Low (simple conditional rendering)

3. **Fix Cost Savings Calculation** - Calculate actual percentage
   - **Impact:** Accurate metrics for cost monitoring
   - **Effort:** 15 minutes
   - **Risk:** None (logging only)

### Monitor (No Action Needed)

4. **Network Connection Warnings** - SDK-level issue, not app bug
   - Monitor for frequency increase
   - Update Firebase SDK if new version addresses this

---

## Testing Plan

### Issue #1: Sheet Presentation Warning

**Test Case 1:** Rapid sheet triggers
1. Launch app
2. Quickly tap 3 different buttons that trigger sheets
3. **Expected:** Only 1 sheet shows, others queue
4. **Verify:** No "Currently, only presenting a single sheet is supported" warnings

**Test Case 2:** Feed scroll with sheets
1. View feed with 10+ posts
2. Scroll rapidly
3. Tap comment button on multiple posts quickly
4. **Expected:** Smooth sheet presentation, no warnings

### Issue #2: NotificationRow Redundant Fetches

**Test Case 1:** Notification load with unique actors
1. Clear app cache
2. Have 10 notifications from 5 different users
3. Open notifications
4. **Expected:** 
   - Log shows "Batch fetching 5 actor profiles"
   - No "Fetching profile individually" logs
   - 1 Firebase batch read (5 profiles)

**Test Case 2:** Notification load with duplicate actors
1. Have 20 notifications from 2 users (10 each)
2. Open notifications
3. **Expected:**
   - Batch fetches 2 profiles
   - All 20 rows render with pre-fetched profiles
   - Total Firebase reads: 1 batch (2 profiles)

### Issue #3: Cost Savings Calculation

**Test Case:** Various actor counts
1. Test with 1, 5, 10, 20, 50 unique actors
2. **Expected logs:**
   - 1 actor: "1 reads → 1 reads (0% reduction)"
   - 5 actors: "5 reads → 1 reads (80% reduction)"
   - 10 actors: "10 reads → 1 reads (90% reduction)"
   - 50 actors: "50 reads → 5 reads (90% reduction)"

---

## Additional Findings

### Positive Observations

1. **Profile Caching Works Well:**
   ```
   ⚡️ [FirebaseService] Using cached profile (age: 0.1s / 300s)
   ```
   Profile manager's 5-minute cache is preventing redundant fetches ✅

2. **Image Caching Optimized:**
   ```
   ⏱️ [AsyncThumbnail] Disk cache hit: 0.002s
   ```
   Disk cache is fast and effective ✅

3. **Feed Load Performance Good:**
   ```
   ✅ [Instagram-style] Fetched 6 chronological posts in 17.366s
   ```
   For 6 posts with full data, 17s is reasonable on cold start ✅

4. **Deduplication Working:**
   ```
   ⏱️ [FirebaseService] Waiting for in-flight profile fetch
   ```
   Multiple concurrent requests for same profile are correctly deduplicated ✅

### Performance Metrics (App Launch)

| Metric | Value | Assessment |
|--------|-------|------------|
| App init → Firebase ready | ~0.5s | ✅ Excellent |
| Auth check | ~0.1s | ✅ Excellent |
| Feed fetch (6 posts) | 17.4s | ⚠️ Could improve |
| Profile fetch | 17.1s | ⚠️ Slow (but cached) |
| Stamp sync | 17.1s | ⚠️ Parallel with profile |
| Total to usable UI | ~17.5s | ⚠️ Target: <10s |

**Note:** The 17s feed load appears to be dominated by the profile fetch. This could be optimized by:
- Prefetching current user profile during auth check
- Loading feed posts before fetching user profiles
- Showing skeleton UI while loading

---

## Conclusion

Four issues identified, three requiring fixes:

1. ✅ **Sheet Warning** - Fix with coordinator pattern (4-6 hours)
2. ✅ **Redundant Fetches** - Fix with blocking render (1-2 hours)
3. ✅ **Cost Calculation** - Fix formula (15 minutes)
4. ℹ️ **Network Warnings** - Monitor only (SDK issue)

**Total estimated effort:** 6-9 hours

**Expected improvements:**
- Eliminate 50+ warnings per launch
- Reduce notification Firebase reads by 93%
- Accurate cost metrics for monitoring

**Risk level:** Low - all fixes are localized and well-understood patterns

---

## Next Steps

1. Review this report with team
2. Prioritize fixes (recommend all 3 in next sprint)
3. Implement fixes in order: Sheet → Fetch → Calculation
4. Test thoroughly using testing plan above
5. Monitor production logs for improvement


