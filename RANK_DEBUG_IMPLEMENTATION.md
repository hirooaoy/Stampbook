# Rank Debug Implementation

## Problem
The rank card shows "..." (loading state) for an extended period when viewing user profiles.

## Root Cause

The rank is showing "..." because:

1. **Lazy Loading Design**: Rank is loaded only when the rank card appears on screen (via `.onAppear` callback)
2. **Initial State**: `profileManager.userRank` starts as `nil` and the UI shows "..." while it's nil
3. **Query Performance**: The rank query fetches all user documents where `totalStamps > currentUserStamps` from Firestore, which can be slow depending on:
   - Network latency
   - Number of users in the database
   - Firestore index performance
   - Cache state (cold vs warm)

## Debug Logging Added

### 1. ProfileManager (`Managers/ProfileManager.swift`)
- **Start**: Logs when rank fetch begins with userId, displayName, and totalStamps
- **Cache Hit**: Shows cached rank with cache age and retrieval time
- **Cache Miss**: Indicates when fetching from Firestore is required
- **Success**: Shows final rank and total time taken
- **Error**: Detailed error info including domain, code, and duration

Example output:
```
🔍 [ProfileManager] Fetching rank for John Doe (userId: abc123, totalStamps: 42)
✅ [ProfileManager] Using cached rank for John Doe: #15 (cache age: 120s, query took: 0.001s)
```

Or:
```
🔍 [ProfileManager] Fetching rank for John Doe (userId: abc123, totalStamps: 42)
🔄 [ProfileManager] Cache miss - fetching rank from Firestore...
✅ [ProfileManager] User rank fetched: #15 (total time: 2.345s)
```

### 2. StampsView (`Views/Profile/StampsView.swift`)
- **Card Appearance**: Logs when rank card becomes visible
- **Current State**: Shows whether rank is already loaded or nil
- **Fetch Trigger**: Indicates when rank fetch is triggered
- **Profile State**: Warns if profile isn't loaded yet

Example output:
```
🎯 [StampsView] Rank card appeared - userRank: nil
🔄 [StampsView] Triggering rank fetch for John Doe...
```

Or:
```
🎯 [StampsView] Rank card appeared - userRank: 15
✅ [StampsView] Rank already loaded: #15
```

### 3. UserProfileView (`Views/Profile/UserProfileView.swift`)
- Similar logging as StampsView but for viewing other users' profiles
- Shows timing for each rank fetch attempt

Example output:
```
🎯 [UserProfileView] Rank card appeared for user xyz789 - userRank: nil
🔄 [UserProfileView] Triggering rank fetch for Jane Smith...
✅ [UserProfileView] Fetched rank for Jane Smith: #23 (took 1.234s)
```

### 4. FirebaseService (`Services/FirebaseService.swift`)

#### calculateUserRankCached()
- Shows cache checks and results
- Logs total time including cache operations

Example output:
```
🔍 [FirebaseService] calculateUserRankCached called for userId: abc123, totalStamps: 42
✅ [FirebaseService] Using cached rank for abc123: #15 (cache age: 300s, took 0.001s)
```

Or:
```
🔍 [FirebaseService] calculateUserRankCached called for userId: abc123, totalStamps: 42
🔄 [FirebaseService] Cache miss - fetching from Firestore...
✅ [FirebaseService] Rank cached: #15 (total time: 2.456s)
```

#### calculateUserRank()
- **Query Start**: Shows the exact Firestore query being executed
- **Query Complete**: Shows query duration and number of users found
- **Final Result**: Shows calculated rank and total time
- **Error Handling**: Detailed error analysis with specific error codes:
  - Code 9 (FAILED_PRECONDITION): Missing Firestore index
  - Code 14 (UNAVAILABLE): Network/server issues
  - Code 4 (DEADLINE_EXCEEDED): Query timeout

Example output:
```
🔍 [FirebaseService] Starting calculateUserRank for userId: abc123 with 42 stamps...
📡 [FirebaseService] Querying Firestore: users collection where totalStamps > 42...
✅ [FirebaseService] Query completed in 1.234s - Found 14 users ahead
✅ [FirebaseService] Calculated rank: #15 (total time: 1.235s)
```

Or on error:
```
🔍 [FirebaseService] Starting calculateUserRank for userId: abc123 with 42 stamps...
📡 [FirebaseService] Querying Firestore: users collection where totalStamps > 42...
❌ [FirebaseService] Rank calculation failed after 30.000s
❌ [FirebaseService] Error: The operation couldn't be completed
❌ [FirebaseService] Error domain: FIRFirestoreErrorDomain, code: 4
❌ [FirebaseService] Full error info: ...
💡 [FirebaseService] Query timeout - too many users or slow connection
```

## How to Use Debug Logs

### 1. Identify Slow Queries
Look for high duration times in the logs:
- **< 0.5s**: Fast (usually cached)
- **0.5s - 2s**: Normal (uncached with good connection)
- **2s - 5s**: Slow (network issues or many users)
- **> 5s**: Very slow (investigate immediately)

### 2. Check Cache Effectiveness
Monitor cache hit/miss patterns:
- Frequent cache hits = good (30-minute cache is working)
- Frequent cache misses = investigate (cache not persisting properly)

### 3. Network Issues
Look for:
- Error code 14 (UNAVAILABLE): Network connectivity problems
- Error code 4 (DEADLINE_EXCEEDED): Timeouts (query too large or network too slow)

### 4. Index Issues
Look for:
- Error code 9 (FAILED_PRECONDITION): Missing Firestore composite index
  - Solution: Check Firestore console for index creation link in error message

## Performance Optimization Strategies

### Current Optimizations (Already Implemented)
1. **30-minute cache** at ProfileManager level
2. **30-minute cache** at FirebaseService level (double-layer caching)
3. **Lazy loading**: Only fetch rank when card appears
4. **Error resilience**: Preserve previous rank on fetch failure

### Future Optimizations (If Needed)
1. **Preload rank on profile load**: Start fetching rank immediately instead of waiting for card appearance
2. **Store rank in Firestore user document**: Update rank via Cloud Function nightly
3. **Approximate ranking**: Show "Top 10%" instead of exact rank for users outside top 1000
4. **Pagination**: Only calculate exact rank for top 1000 users
5. **Count aggregation**: Use Firestore count aggregation query (requires proper indexes)

## Testing Recommendations

### 1. Test with Different Network Conditions
```
Settings → Developer → Network Link Conditioner
- WiFi
- 4G
- 3G
- Edge
```

### 2. Test Cache Behavior
- Open profile (should trigger rank fetch)
- Close and reopen within 30 minutes (should use cache)
- Wait 31 minutes and reopen (should fetch again)

### 3. Test Error Scenarios
- Enable Airplane Mode before opening profile
- Check error handling and preservation of previous rank

### 4. Monitor Console Logs
Run app in Xcode and watch console for the debug logs:
```
🔍 [StampsView] Rank card appeared...
🔍 [ProfileManager] Fetching rank...
🔍 [FirebaseService] calculateUserRankCached...
📡 [FirebaseService] Querying Firestore...
✅ [FirebaseService] Query completed in X.XXXs
```

## Expected Behavior

### First Load (Cache Miss)
1. User opens profile
2. Rank card shows "..."
3. 0.5-2 seconds later, rank appears (e.g., "#15")

### Second Load (Cache Hit)
1. User opens profile
2. Rank card shows "..." briefly (< 0.01s)
3. Rank appears almost immediately from cache

### Error Case
1. User opens profile (no network)
2. Rank card shows "..."
3. Previous rank persists (if available) or stays as "..."
4. Error logged to console (not shown to user - rank is optional)

## Next Steps

1. **Run the app** and monitor console logs
2. **Identify the bottleneck** using the debug output:
   - Is it network latency?
   - Is it the Firestore query?
   - Is it missing indexes?
3. **Report findings** with example log output
4. **Implement targeted optimization** based on the root cause

## Summary

The "..." appears because rank loading takes time. The comprehensive debug logging now added will help identify exactly where the time is spent:
- Cache lookup: Should be < 0.01s
- Firestore query: Should be 0.5-2s typically
- Network latency: Varies based on connection

Use the debug logs to pinpoint the exact bottleneck and implement the appropriate optimization strategy.

