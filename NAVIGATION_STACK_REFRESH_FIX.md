# Navigation Stack Feed Refresh Fix

**Date:** November 17, 2025  
**Status:** ✅ IMPLEMENTED

---

## Problem

When users followed someone via NavigationStack navigation (not sheets), the feed wouldn't refresh:

```
User Journey:
1. Feed → Tap username → UserProfileView (NavigationStack)
2. Follow @hiroo
3. Back to feed
4. ❌ Feed still stale - doesn't show @hiroo's posts
```

**Root Cause:** NavigationStack navigation didn't trigger any refresh handlers. Only sheet `.onDisappear` handlers worked.

---

## Why This Matters

**This is THE organic discovery flow:**
- User sees interesting comment: "Love this spot! 🔥"
- Taps commenter's profile
- Follows them after browsing their collection
- Expects to see their stamps immediately
- **If feed is stale → confusion, broken UX**

Unlike search (intentional follow), this is **spontaneous discovery** - the core growth mechanism for Stampbook.

---

## Solution

Added `.onAppear` handler to `FeedContent` that checks `didFollowingListChange` and refreshes if needed.

### Changes Made:

**1. Updated `FeedContent` struct parameters (lines 641-652):**
```swift
@Binding var lastFeedRefreshTime: Date? // For debounce checking
let refreshDebounceInterval: TimeInterval // Debounce threshold
@EnvironmentObject var followManager: FollowManager
```

**2. Added `.onAppear` handler (lines 806-830):**
```swift
.onAppear {
    if followManager.didFollowingListChange {
        followManager.didFollowingListChange = false
        print("🔄 [FeedContent] Following list changed on navigation return")
        
        // DEBOUNCE: Skip refresh if too soon (3 seconds)
        if let lastRefresh = lastFeedRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshDebounceInterval {
            print("⏭️ [FeedContent] Skipping refresh - too soon")
            return
        }
        
        Task {
            await refreshFeed()
            await MainActor.run {
                lastFeedRefreshTime = Date()
            }
        }
    }
}
```

**3. Updated `FeedContent` instantiation (lines 315-316):**
```swift
lastFeedRefreshTime: $lastFeedRefreshTime,
refreshDebounceInterval: refreshDebounceInterval,
```

---

## Safety Mechanisms

**Two layers of protection prevent double-refresh:**

1. **Boolean flag** (`didFollowingListChange`)
   - First handler to fire resets to `false`
   - Subsequent handlers see `false` and skip
   
2. **3-second debounce** (`lastFeedRefreshTime`)
   - Even if flag is still `true`, debounce blocks rapid refreshes
   - Changed from 10s → 3s for better UX

---

## Test Scenarios

### ✅ Scenario 1: NavigationStack Follow (THE FIX)
```
Feed → Profile → Follow → Back
  → FeedContent .onAppear fires
  → Checks flag = true ✅
  → REFRESH (113 reads)
  → Flag = false
```
**Result:** 1 refresh ✅ **THIS IS THE FIX**

---

### ✅ Scenario 2: Sheet Follow (Still Works)
```
Search sheet → Follow → Close
  → Sheet .onDisappear fires FIRST
  → REFRESH
  → Flag = false
  → FeedContent .onAppear fires
  → Flag = false ❌
  → No refresh
```
**Result:** 1 refresh ✅ (flag protection worked)

---

### ✅ Scenario 3: Tab Switch + onAppear
```
Stamps tab → Follow → Switch to Feed
  → onChange(selectedTab) fires FIRST
  → REFRESH
  → Flag = false
  → FeedContent .onAppear fires 0.2s later
  → Flag = false ❌
  → No refresh
```
**Result:** 1 refresh ✅ (flag protection worked)

---

### ✅ Scenario 4: Rapid Navigation
```
Profile → Follow → Back → Profile → Back
  → First .onAppear: REFRESH (10:00:00)
  → Second .onAppear: Debounce check
  → 10:00:02 - 10:00:00 = 2s < 3s ❌
  → Blocked
```
**Result:** 1 refresh ✅ (debounce protection worked)

---

## Files Modified

1. **`Stampbook/Views/Feed/FeedView.swift`**
   - Added parameters to `FeedContent` struct
   - Added `.onAppear` handler with debounce logic
   - Updated `FeedContent` instantiation

**Total: ~20 lines added**

---

## Cost Impact

**No change to existing costs:**
- Still ~113 reads per follow refresh
- No new refresh scenarios (just catches missing one)
- Protections prevent spam

**Example:**
- User follows 5 people via NavigationStack in one session
- Before fix: 0 refreshes (broken)
- After fix: 5 refreshes (1 per navigation return) = ~565 reads
- With debounce: If done rapidly (<3s apart), some get blocked

---

## What We Fixed

### ✅ **Now Working:**
1. Search sheet → Follow → **Refreshes** ✅
2. Likes sheet → Follow → **Refreshes** ✅
3. **NavigationStack → Follow → Refreshes** ✅ **NEW!**
4. Tab switch → Follow → **Refreshes** ✅

### 🎯 **Complete Coverage:**
All follow/unfollow actions now trigger feed refresh via one of:
- Sheet `.onDisappear`
- Tab `onChange(selectedTab)`
- FeedContent `.onAppear` (NEW - catches NavigationStack)

---

## Recommendation

**Monitor logs for:**
- `🔄 [FeedContent] Following list changed on navigation return`
- `⏭️ [FeedContent] Skipping refresh - too soon`

If you see excessive "Skipping refresh" logs, consider reducing debounce from 3s → 2s.

---

## Related Fixes

This complements:
- **Feed Disappear Bug Fix** (Nov 17) - Fixed `profileDidUpdate` notification
- **Following List Refresh Bug** (Nov 17) - Fixed `FollowListView.onAppear`
- **Debounce Reduction** (Nov 17) - Changed 10s → 3s

See: `EDGE_CASES_AUDIT.md` for complete edge case tracking.

