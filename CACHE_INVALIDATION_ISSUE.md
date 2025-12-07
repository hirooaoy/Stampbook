# Cache Invalidation Issue - Follow/Unfollow Actions

## Current Status: ⚠️ BROKEN

Your follow/unfollow actions are **NOT** invalidating the ProfileManager cache, which means:

### What Happens Now (Broken Behavior):

1. **User follows someone at 10:00 AM**
   - FollowManager optimistically updates: `following: 8 → 9` ✅
   - Cloud Function updates Firebase profile: `followingCount: 9` ✅
   - BUT ProfileManager cache is NOT cleared ❌
   
2. **User closes and reopens app at 10:05 AM**
   - ProfileManager loads cached profile (age: 2 hours)
   - Cached profile shows: `followingCount: 8` ❌ WRONG!
   - Cache won't expire for 22 more hours
   - User sees old count until they manually refresh

### The Problem

**In FollowManager.swift (lines 145-146):**
```swift
// ⚠️ DEPRECATED: NotificationCenter post removed (replaced with didFollowingListChange flag)
// NotificationCenter.default.post(name: .followingListDidChange, object: nil)
```

**The notification was commented out!** ❌

**But ProfileManager.swift (lines 58-60) is STILL listening:**
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleFollowingListChange),
    name: .followingListDidChange,  // ⚠️ Never fires anymore!
    object: nil
)
```

**Result:** ProfileManager never knows to refresh the cache after follow/unfollow!

---

## The Fix

### Option 1: Re-enable NotificationCenter (Simple) ✅ RECOMMENDED

**Uncomment the notification posts in FollowManager:**

```swift
// In followUser() - Line 145
✅ NotificationCenter.default.post(name: .followingListDidChange, object: nil)

// In unfollowUser() - Line 263  
✅ NotificationCenter.default.post(name: .followingListDidChange, object: nil)
```

**What happens:**
1. User follows someone → notification fires
2. ProfileManager catches notification → invalidates cache
3. Next app open → fetches fresh profile from Firebase
4. User sees correct counts ✅

**Pros:**
- Simple 2-line fix
- Already implemented, just commented out
- Works immediately
- No downside

**Cons:**
- None (the `didFollowingListChange` flag is for FeedView optimization, doesn't replace this)

---

### Option 2: Use didFollowingListChange Flag (Complex)

Make ProfileManager watch the `didFollowingListChange` flag instead:

```swift
// In ProfileManager.init()
// Watch FollowManager's flag changes
followManager.$didFollowingListChange
    .sink { changed in
        if changed {
            // Invalidate cache and refresh
        }
    }
    .store(in: &cancellables)
```

**Pros:**
- More "modern" reactive approach

**Cons:**
- Requires passing FollowManager to ProfileManager
- More complex dependency injection
- Not worth the effort for MVP

---

## Recommended Action

**Just uncomment those 2 lines!** That's it. Problem solved.

The comment says "DEPRECATED" but it's wrong - the notification and the flag serve **different purposes**:

- **`didFollowingListChange` flag** → Tells FeedView to refresh (cost optimization)
- **`followingListDidChange` notification** → Tells ProfileManager to clear cache (correctness)

Both should exist! They're not replacements for each other.

---

## Impact Before Fix

**User Experience:**
- Follow someone → count updates immediately ✅
- Close app → reopen app
- Count shows OLD value ❌ (cached from hours ago)
- User confused: "I just followed them, why does it say 8?"
- User manually pulls to refresh
- Count finally updates ✅

**Cost:**
- No extra cost (notification is free)
- Just fixes the broken behavior

---

## Impact After Fix  

**User Experience:**
- Follow someone → count updates immediately ✅
- Close app → reopen app  
- Count shows CORRECT value ✅ (cache was invalidated)
- App fetches fresh data on open
- Everything works as expected!

**Cost:**
- 1 extra profile read when user reopens app after follow/unfollow
- Negligible cost (only happens when user actually follows/unfollows)
- Much better than showing wrong data for 24 hours!

---

## Test Plan

1. Check current follow count (e.g., 8 following)
2. Follow someone → count shows 9 ✅
3. **Force quit app completely**
4. Reopen app
5. **BEFORE FIX:** Shows 8 ❌
6. **AFTER FIX:** Shows 9 ✅

---

## Why This Happened

Looking at the git history comment:
> "⚠️ DEPRECATED: NotificationCenter post removed (replaced with didFollowingListChange flag)"

Someone thought the flag replaces the notification, but:
- Flag is for FeedView (performance optimization)
- Notification is for ProfileManager (cache invalidation)

They serve different purposes and BOTH should exist!

---

## Conclusion

**This is a critical bug.** Users see wrong follow counts for up to 24 hours after following/unfollowing someone.

**The fix is trivial:** Uncomment 2 lines.

Do you want me to make this fix now?

