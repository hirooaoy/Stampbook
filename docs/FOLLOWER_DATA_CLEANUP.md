# Follower Data Cleanup - November 13, 2025

## Issue
User `mpd4k2n13adMFMY52nksmaQTbMQ2` was showing follower `LGp7cMqB2tSEVU1O7NEvR0Xib7y2` in Firebase, but the app correctly showed they weren't following each other.

## Root Cause
Orphaned documents existed in the `followers` subcollection, which is **NOT used by the app's follow system**. These were leftover bad data from an old implementation or bug.

## How the Follow System Actually Works

### Data Structure (Unidirectional)
The app uses a **unidirectional follow system** where only the `following` subcollection is used:

```
users/{followerUserId}/following/{followeeUserId}
  - id: {followeeUserId}
  - createdAt: timestamp
```

**There is NO `followers` subcollection** - it's not part of the architecture.

### Follow Flow
1. **When User A follows User B:**
   - Document created at: `users/{UserA}/following/{UserB}`
   - That's it! No reciprocal document is created.

2. **To check if User A is following User B:**
   - Check if document exists: `users/{UserA}/following/{UserB}`
   - See: `FirebaseService.isFollowing()`

3. **To get User B's followers:**
   - Query collection group "following" where `id == UserB`
   - This finds all users who have User B in their following subcollection
   - See: `FirebaseService.fetchFollowers()`

### Code References
- **Follow/Unfollow:** `FirebaseService.swift` lines 815-875
- **Check Following:** `FirebaseService.swift` lines 878-887
- **Fetch Followers:** `FirebaseService.swift` lines 926-949
- **Manager:** `FollowManager.swift` (handles UI state and optimistic updates)

## Resolution
Deleted orphaned documents from the `followers` subcollections:
- `users/mpd4k2n13adMFMY52nksmaQTbMQ2/followers/LGp7cMqB2tSEVU1O7NEvR0Xib7y2`
- `users/LGp7cMqB2tSEVU1O7NEvR0Xib7y2/followers/mpd4k2n13adMFMY52nksmaQTbMQ2`

Verified no other orphaned `followers` subcollection documents exist in the system.

## Key Takeaways
1. The app's follow system uses ONLY the `following` subcollection
2. Any documents in `followers` subcollections are orphaned/ignored by the app
3. The app was working correctly - it showed they weren't following each other because neither user had documents in their `following` subcollection
4. The Firebase data is now clean and matches the app's architecture

## Prevention
- Only use `FirebaseService.followUser()` and `FirebaseService.unfollowUser()` for follow operations
- Never manually create documents in `followers` subcollections
- If migrating/testing, ensure data matches the unidirectional follow structure

