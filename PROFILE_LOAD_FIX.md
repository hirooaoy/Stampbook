# Profile Loading Fix - November 2, 2025

## Issue
After signing out and signing back in, the profile wasn't loading properly and the profile picture didn't get loaded.

## Root Cause Analysis

The issue was a potential race condition and insufficient error handling in the profile loading flow:

1. **Multiple loading triggers**: Both `AuthManager` and `ContentView` were trying to load the profile independently
2. **Missing onChange trigger**: Only watching `authManager.userId` but not `authManager.isSignedIn`
3. **Insufficient logging**: Hard to debug what was happening during sign-in
4. **No duplicate load prevention**: ProfileManager could be called multiple times unnecessarily

## Fixes Applied

### 1. ProfileManager.swift
- **Added duplicate load prevention**: Skip loading if profile is already loaded for the same user
- **Improved logging**: Added detailed logging to track profile loading, updates, and clearing
- **Better error context**: Log when profile loading is skipped vs when it fails

### 2. ContentView.swift
- **Added dual watchers**: Watch both `authManager.isSignedIn` AND `authManager.userId` to ensure profile loading is triggered correctly
- **Comprehensive logging**: Added detailed logging for all auth state changes
- **Better coordination**: Explicit handling of sign-in and sign-out states

### 3. AuthManager.swift
- **Enhanced sign-in logging**: Track every step of the sign-in process
- **Profile creation logging**: Detailed logging when creating/updating user profiles
- **State tracking**: Log when auth state changes and profile loads

## Technical Details

### Sign-In Flow (Fixed)
1. User initiates sign-in with Apple
2. `AuthManager.signInWithApple()` triggered
3. Firebase authentication succeeds → `isSignedIn = true`, `userId = <uid>`
4. `ContentView` detects `isSignedIn` change → calls `profileManager.loadProfile(userId)`
5. `ContentView` detects `userId` change → calls `profileManager.loadProfile(userId)` (may be skipped if already loaded)
6. `ProfileManager.loadProfile()` fetches profile from Firestore
7. `ProfileManager.currentUserProfile` updated
8. `ContentView` detects `currentUserProfile` change → syncs to `authManager.userProfile`
9. Profile data and profile picture are now available throughout the app

### Sign-Out Flow
1. User initiates sign-out
2. `AuthManager.signOut()` → `isSignedIn = false`, `userId = nil`
3. `ContentView` detects auth state changes → calls `profileManager.clearProfile()`
4. All profile data is cleared from both managers

## How to Debug

The app now has extensive logging. When testing sign-in/sign-out:

**Look for these log sequences:**

### Successful Sign-In:
```
✅ [AuthManager] Firebase sign in successful for user: <userId>
✅ [AuthManager] Updated auth state - userId: <userId>, isSignedIn: true
🔄 [AuthManager] Creating/updating user profile for userId: <userId>
✅ [AuthManager] Found existing profile: @<username>
✅ [AuthManager] Updated user profile for <displayName> (@<username>)
🔄 [ContentView] Auth state changed - isSignedIn: true
🔄 [ContentView] User signed in, loading profile for userId: <userId>
🔄 [ContentView] UserId changed: <userId>
🔄 [ContentView] Loading profile for new userId: <userId>
✅ [ProfileManager] Profile already loaded for userId: <userId> (skipped duplicate)
🔄 [ProfileManager] Loading profile for userId: <userId>
✅ [ProfileManager] Loaded user profile: <displayName>
```

### Successful Sign-Out:
```
🔄 [ContentView] Auth state changed - isSignedIn: false
🔄 [ContentView] User signed out, clearing profile
🗑️ [ProfileManager] Clearing profile data
🔄 [ContentView] UserId changed: nil
🔄 [ContentView] Clearing profile (signed out or nil userId)
🗑️ [ProfileManager] Clearing profile data
```

### If Profile Fails to Load:
```
❌ [ProfileManager] Failed to load profile: <error>
```

or

```
❌ [AuthManager] Failed to create/update user profile: <error>
```

## Testing Instructions

1. **Clean test**: 
   - Build and run the app
   - Sign out if already signed in
   - Sign in with Apple
   - Check console logs for successful sign-in sequence
   - Verify profile displays in Stamps tab (should show @username, not "@user")
   - Verify profile picture loads

2. **Sign-out test**:
   - Sign out from Stamps tab
   - Check console logs for successful sign-out sequence
   - Verify profile is cleared (should show "@user" or signed-out state)

3. **Multiple sign-in test**:
   - Sign out
   - Sign in
   - Check console logs - should see "Profile already loaded" messages (good!)
   - Profile should load instantly

## Profile Picture Loading

Profile pictures are loaded by `ProfileImageView` which:
1. Checks memory cache first (instant if cached)
2. Checks disk cache (fast if previously downloaded)
3. Downloads from Firebase Storage (only if not cached)

If profile picture doesn't load:
- Check for profile URL: `avatarUrl` must be non-nil and non-empty
- Check console logs for image download errors
- Verify network connectivity
- Check Firebase Storage rules

## Next Steps

If the issue persists after this fix:
1. Collect console logs from sign-in/sign-out attempts
2. Check if profile data is loading but not displaying (UI issue)
3. Check if profile picture URL is valid
4. Verify Firebase connectivity

## Summary

This fix improves the robustness of profile loading by:
- Adding redundant triggers for profile loading (belt and suspenders approach)
- Preventing duplicate loads to improve performance
- Adding comprehensive logging to diagnose issues
- Ensuring proper cleanup on sign-out

