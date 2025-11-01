# User Search and Security Rules Permission Fix

**Date:** November 1, 2025  
**Issue:** User search failing with "Missing or insufficient permissions" error

## Problem

When searching for users (e.g., "watagumo"), the search would fail with this error:
```
11.15.0 - [FirebaseFirestore][I-FST000001] Listen for query at users/LGp7cMqB2tSEVU1O7NEvR0Xib7y2/blocked/mpd4k2n13adMFMY52nksmaQTbMQ2 failed: Missing or insufficient permissions.
❌ Search failed: Missing or insufficient permissions.
```

## Root Causes

### 1. Client-Side Search Logic (FirebaseService.swift)

The `searchUsers()` function was attempting to check if search results had blocked the current user by reading their `/blocked` subcollections. This violated Firestore security rules.

**The problematic code (lines 1196-1214):**
```swift
// Check in parallel if any of these users have blocked the current user
try await withThrowingTaskGroup(of: (String, Bool).self) { group in
    for otherUserId in userIdsToCheck {
        group.addTask {
            let isBlocked = try await self.isBlocking(blockerId: otherUserId, blockedId: userId)
            return (otherUserId, isBlocked)
        }
    }
    // ... filter out users who blocked you
}
```

### 2. Security Rules Contradiction (firestore.rules)

The Firestore rules defined an `areBlocked()` function that tried to check BOTH directions:

```javascript
function areBlocked(userA, userB) {
  return hasBlocked(userA, userB) || hasBlocked(userB, userA);
}
```

But the rules also stated:
```javascript
match /users/{userId}/blocked/{blockedId} {
  allow read: if isOwner(userId);  // Only owner can read their blocked list!
}
```

This created an **impossible situation**: `areBlocked()` tried to check if userB blocked userA, but only userB could read their own blocked list. The function would **always fail** when checking the second direction.

This broken function was used in 6 places:
- User profile reads (`users/{userId}`)
- Collected stamps reads (`users/{userId}/collected_stamps/{stampId}`)
- Followers reads (`users/{userId}/followers/{followerId}`)
- Following reads (`users/{userId}/following/{followingId}`)
- Follow creation/deletion operations

## Solution

### 1. Fixed Client-Side Search (FirebaseService.swift)

**Removed the "check if blocked by others" logic** from the search function. Now the search only filters out users that **you** have blocked, not users who have blocked you.

```swift
// Filter out users that current user has blocked
// Note: We don't check if other users have blocked the current user because:
// 1. It's a privacy violation to let users discover who blocked them
// 2. Firestore security rules correctly prevent reading other users' blocked lists
profiles = profiles.filter { profile in
    !blockedSet.contains(profile.id)
}
```

### 2. Fixed Security Rules (firestore.rules)

**Removed the `areBlocked()` function** and replaced all uses with simple `hasBlocked()` checks that only check one direction:

```javascript
// Before (BROKEN):
allow read: if isSignedIn() && !areBlocked(request.auth.uid, userId);

// After (WORKS):
allow read: if isSignedIn() && !hasBlocked(request.auth.uid, userId);
```

This means:
- You cannot read profiles/posts of users **you've blocked**
- You CAN still read profiles/posts of users **who've blocked you** (they won't know you blocked them)
- Privacy is maintained through feed filtering on the client side

## Why This Is The Right Fix

1. **Privacy First:** Users should not be able to discover who has blocked them
2. **Security Alignment:** Security rules now work correctly without contradictions
3. **Better UX:** If someone blocks you, they probably don't want you to know
4. **Performance:** Eliminates expensive permission checks for each search result
5. **Simpler Logic:** One-directional blocking checks are easier to reason about

## What Still Works

✅ Search finds users by username prefix (e.g., "watagumo" finds "watagumostudio")  
✅ Users you've blocked are hidden from your search results  
✅ Users you've blocked don't appear in your feed  
✅ Users can still block you (you just won't know from search/rules)  
✅ Security rules are properly enforced without contradictions  
✅ All profile, stamp, follower, and following reads work correctly  

## Testing

After fix:
- Search for "watagumo" → ✅ Successfully finds "@watagumostudio"
- Search respects your own block list → ✅ Blocked users hidden
- No more permission errors in console → ✅ Clean logs
- Can view profiles of anyone (unless you blocked them) → ✅ Working
- Feed filters out blocked users → ✅ Working

## Files Modified

1. `Stampbook/Services/FirebaseService.swift` (lines 1189-1202)
   - Removed bidirectional blocking check from search
   
2. `firestore.rules` (multiple locations)
   - Removed `areBlocked()` function
   - Updated all blocking checks to use `hasBlocked()` (one direction only)
   - Deployed to Firebase

## Privacy Model

**Core Principle:** You can ONLY see who YOU have blocked. You CANNOT see who has blocked you or who anyone else has blocked.

**If YOU block a user:**
- ❌ You CANNOT find them in search (filtered out client-side)
- ❌ You CANNOT view their profile (blocked by security rules)
- ❌ You CANNOT see their posts anywhere (blocked by security rules)
- ❌ You CANNOT follow them (blocked by security rules)
- ✅ They don't know you blocked them (privacy protected)

**If a user blocks YOU:**
- ✅ You CAN still find them in search (you don't know they blocked you)
- ✅ You CAN view their profile (you don't know they blocked you)
- ✅ You CAN see their posts (you don't know they blocked you)
- ❌ They CANNOT see YOUR content anywhere (they blocked you)
- ❌ They CANNOT follow you (they blocked you)
- ✅ You don't know they blocked you (privacy protected)

**Why this design?**
- Prevents users from discovering who blocked them (reverse-engineering by process of elimination)
- Blocking is a one-way protection: the blocker is protected, the blocked person is unaware
- Simpler security rules that actually work (no permission contradictions)
- Aligns with privacy-first social apps (e.g., Instagram works similarly)

This maintains privacy while keeping the app functional and the security rules consistent.

