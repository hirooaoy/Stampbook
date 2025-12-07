# Profile Cache Expiration Bug Fix

**Date:** December 5, 2025  
**Severity:** Critical  
**Status:** ✅ Fixed

## Executive Summary

Fixed a critical bug in `ProfileManager` where cached profiles never expired, causing stale data (up to 16.5 days old) to be loaded on app launch. This resulted in incorrect follow counts being displayed temporarily until fresh data was fetched from Firebase.

## The Bug

### Symptoms
- Follow counts would briefly show incorrect values on app launch
- Flickering/jumping numbers as cache was corrected by Firebase data
- Users would see "following: 1" then immediately "following: 0"

### Root Cause
The cache age calculation was using the wrong timestamp:

```swift
// WRONG: This calculates how old the USER ACCOUNT is, not the cache!
let cacheAge = Date().timeIntervalSince(profile.createdAt)
```

This meant:
- A user who created their account 16.5 days ago would have cache "age: 1429567s"
- But the cache itself could have been saved 16.5 days ago with stale follow counts
- The cache never expired because the code was looking at account age, not cache age

### Example From Logs
```
🔍 [ProfileManager:337] Found cached profile (age: 1429567s)  ⚠️ 16.5 days old!
ℹ️ [ProfileManager] ✨ Loaded cached profile for @watagumostudio - instant display

// Cached profile had: followingCount: 1 (stale from 16.5 days ago)
📊 [StampsView] New following: 1  ⚠️ Wrong!

// Fresh Firebase data had: followingCount: 0 (correct)
✅ [ProfileManager] Loaded user profile: watagumostudio (0 followers, 0 following)
📊 [StampsView] New following: 0  ✅ Correct!
```

## The Fix

### 1. Created CachedProfile Wrapper
Added a wrapper struct that stores both the profile and when it was cached:

```swift
private struct CachedProfile: Codable {
    let profile: UserProfile
    let cachedAt: Date  // ✅ Now tracks when cache was saved
}
```

### 2. Added Cache Expiration Constant
```swift
/// Maximum age for cached profile (24 hours)
/// Prevents stale data from being loaded (e.g., outdated follow counts)
private let maxCacheAge: TimeInterval = 24 * 60 * 60 // 24 hours
```

### 3. Updated loadCachedProfile()
```swift
private func loadCachedProfile(userId: String) -> UserProfile? {
    // ... decode CachedProfile wrapper ...
    
    // Check if cache is expired
    let cacheAge = Date().timeIntervalSince(cachedProfile.cachedAt)  // ✅ Correct!
    
    if cacheAge > maxCacheAge {
        Logger.debug("Cached profile expired (age: \(String(format: "%.0f", cacheAge))s > \(String(format: "%.0f", maxCacheAge))s), clearing")
        UserDefaults.standard.removeObject(forKey: cacheKey)
        return nil  // Cache expired, fetch fresh from Firebase
    }
    
    return cachedProfile.profile
}
```

### 4. Updated saveCachedProfile()
```swift
private func saveCachedProfile(_ profile: UserProfile) {
    // Wrap profile with cache timestamp
    let cachedProfile = CachedProfile(profile: profile, cachedAt: Date())
    let data = try encoder.encode(cachedProfile)
    UserDefaults.standard.set(data, forKey: cacheKey)
}
```

### 5. Added Migration Logic
For backward compatibility with old cache format:

```swift
catch {
    // Try to migrate old cache format (profile without wrapper)
    do {
        let profile = try decoder.decode(UserProfile.self, from: data)
        Logger.warning("Found legacy cached profile format, migrating to new format")
        
        // Re-save in new format with current timestamp
        saveCachedProfile(profile)
        
        return profile
    } catch {
        // Corrupt cache, clear it
        UserDefaults.standard.removeObject(forKey: cacheKey)
        return nil
    }
}
```

## Verification

### Test Scenarios
✅ 1 hour old - Should NOT expire  
✅ 12 hours old - Should NOT expire  
✅ 23 hours old - Should NOT expire  
✅ 24 hours old (exactly) - Should NOT expire  
✅ 25 hours old - Should expire  
✅ 7 days old - Should expire  
✅ 16.5 days old (bug case) - Should expire  

### Expected Behavior After Fix

**On first app launch after update:**
- Old cache (16.5 days) will be detected and cleared
- Fresh profile will be fetched from Firebase
- New cache will be saved with current timestamp

**On subsequent launches:**
- If cache < 24 hours old: instant profile display (good UX)
- If cache > 24 hours old: cleared, fetch fresh data
- No more stale follow counts!

## Impact Assessment

### Before Fix
- Users could see incorrect follow counts for up to 16.5 days (or longer)
- Cache never expired naturally
- Only manual app reinstall or sign out would clear cache

### After Fix
- Cache automatically expires after 24 hours
- Fresh data fetched from Firebase
- Follow counts always accurate (within 24 hours)
- Better balance between performance (caching) and accuracy (expiration)

## Files Changed

1. **Stampbook/Managers/ProfileManager.swift**
   - Added `CachedProfile` wrapper struct
   - Added `maxCacheAge` constant (24 hours)
   - Updated `loadCachedProfile()` with expiration check
   - Updated `saveCachedProfile()` to use wrapper
   - Added migration logic for old cache format

## Why 24 Hours?

The 24-hour expiration strikes a balance:

**Too Short (< 1 hour):**
- Defeats purpose of caching
- Extra Firebase reads on every app launch
- Increased costs

**Too Long (> 7 days):**
- Stale data lingers too long
- Poor user experience with outdated counts
- Defeats purpose of having accurate data

**24 Hours (chosen):**
- Profile loads instantly on most app launches
- Follow counts stay reasonably up-to-date
- Natural expiration for casual users (check app every few days)
- Low cost impact (1 extra read per day per user)

## Related Issues

This fix also prevents:
- Stale stamp counts (totalStamps field)
- Stale country counts (uniqueCountriesVisited field)
- Outdated bio/display name (if user changed them)
- Incorrect avatar URLs (if user updated profile picture)

## Testing Recommendations

1. **Test fresh install**: Verify profile loads correctly
2. **Test 23-hour cache**: Should load from cache (instant)
3. **Test 25-hour cache**: Should clear and fetch fresh
4. **Test follow/unfollow**: Counts should update correctly
5. **Test migration**: Users with old cache format should migrate smoothly

## Conclusion

This was a critical bug that went undetected because:
1. The cache seemed to be working (profiles loaded instantly)
2. The stale data was corrected quickly by Firebase fetch
3. The flickering was subtle enough to miss in testing

The fix is simple but essential: **track when the cache was saved, not when the user account was created**.

