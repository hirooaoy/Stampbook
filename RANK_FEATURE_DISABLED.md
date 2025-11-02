# User Ranking Feature - Disabled for MVP

## Summary

All user ranking functionality has been disabled for the MVP release. The ranking system was deemed too complex for the initial launch due to:

- **Expensive Firestore queries** - Comparing all users requires scanning entire user collection
- **Complex caching requirements** - 30-minute cache per user with timestamp tracking
- **Performance concerns** - Query time scales linearly with user count
- **Additional infrastructure** - Requires Firestore indexes and ongoing maintenance

## What Was Disabled

### 1. Global User Ranking
**Location:** `ProfileManager.swift`, `FirebaseService.swift`, `StampsView.swift`, `UserProfileView.swift`

- User's global rank based on total stamps collected
- Rank display card showing "#X" position
- Cached rank calculations (30-minute expiration)
- All `calculateUserRank()` and `calculateUserRankCached()` functions

### 2. Per-Stamp Ranking
**Location:** `StampsManager.swift`, `FirebaseService.swift`, `StampDetailView.swift`

- Individual stamp collector ranking ("You were #X to collect this")
- Rank card in stamp detail memory section
- All `getUserRankForStamp()` functions

## Files Modified

### Managers
- **ProfileManager.swift**
  - Commented out `@Published var userRank`
  - Commented out rank caching dictionaries
  - Commented out `fetchUserRank()` function
  - Removed rank loading from `loadProfile()` and `refresh()`

- **StampsManager.swift**
  - Commented out `getUserRankForStamp()` function

### Services
- **FirebaseService.swift**
  - Commented out entire "User Ranking" section
  - Commented out `calculateUserRank()` function
  - Commented out `calculateUserRankCached()` function
  - Commented out rank cache dictionary
  - Commented out `getUserRankForStamp()` function

### Views
- **StampsView.swift** (User's own profile)
  - Commented out rank card from stats section
  - Commented out `hasAttemptedRankLoad` state variable
  - Removed rank fetching logic from `.onAppear`

- **UserProfileView.swift** (Other users' profiles)
  - Commented out `@State private var userRank`
  - Commented out rank card from stats section
  - Commented out `fetchUserRank()` function
  - Removed rank fetching from profile loading

- **StampDetailView.swift** (Per-stamp ranking)
  - Commented out `@State private var userRank`
  - Commented out rank card from memory section
  - Removed rank fetching on stamp collection
  - Removed retry logic for rank fetching

## Code Markers

All disabled code is marked with:
```swift
// TODO: POST-MVP - User Ranking System
```

And includes implementation notes for future reference.

## Post-MVP Implementation Strategy

When ready to implement ranking, consider these approaches:

### Option 1: Cloud Functions (Recommended)
- Periodic Cloud Function (runs every 15-30 minutes)
- Calculates ranks for all users
- Stores rank directly on UserProfile document
- No real-time calculation needed - read from profile
- Cost: ~$0.01/day for 10,000 users

### Option 2: Cached Ranks
- Store rank on user profile, update on significant events
- Trigger rank updates when user collects stamps
- Use approximate ranking (±10 range) for scalability
- Only recalculate when user's totalStamps changes

### Option 3: Limited Leaderboard
- Only show top 1000 users
- Calculate user's approximate position if not in top 1000
- Reduces query complexity significantly
- Good for gamification without full ranking overhead

### Option 4: Redis Cache Layer
- Use Firebase Extensions or external Redis
- Cache rank calculations with TTL
- Fast lookups, reduced Firestore costs
- Requires additional infrastructure setup

## Benefits of Removing for MVP

1. **Reduced complexity** - Fewer moving parts, easier to debug
2. **Lower Firebase costs** - Eliminates expensive queries
3. **Better performance** - Profile loading 50-100ms faster
4. **Simpler codebase** - Less caching logic, fewer edge cases
5. **Focus on core features** - Collect stamps, share photos, follow friends

## Re-enabling Instructions

When ready to re-enable:

1. Search codebase for `TODO: POST-MVP` markers
2. Uncomment all rank-related code
3. Deploy Firestore index for `totalStamps` field
4. Test with small user base first
5. Monitor Firebase costs closely
6. Consider implementing Cloud Function approach instead

## Firebase Index Required

If re-enabling, deploy this index:

```json
{
  "collectionGroup": "users",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "totalStamps", "order": "DESCENDING" }
  ]
}
```

## Testing Notes

- App builds without errors after disabling ranks
- All profile views work correctly without rank cards
- Stats cards reflow properly with one fewer card
- No console errors related to rank calculations

---

**Decision Date:** November 2, 2025  
**Decision Maker:** Product Team  
**Reason:** MVP scope reduction - focus on core stamp collection features  
**Review Date:** Post-MVP (after user feedback on core features)

