# Feed Disappear Bug Fix

**Date**: November 17, 2025  
**Issue**: Feed disappears after searching and viewing another user's profile

## Problem

When viewing another user's profile from search:
1. UserProfileView creates a local `ProfileManager` instance to load that user's profile
2. ProfileManager posts `profileDidUpdate` notification for ANY profile load
3. FeedManager listens to this notification and clears the feed cache
4. When search sheet closes, FeedView only refreshes if `followManager.didFollowingListChange` is true
5. Result: Feed is cleared but never reloaded → empty feed

## Root Cause

**Architectural Issue**: `ProfileManager` was designed for the current user only, but `UserProfileView` was using it to load OTHER users' profiles. The `profileDidUpdate` notification was being posted for all profile loads, causing unnecessary feed cache invalidation.

## Solution

Added `isCurrentUser` parameter to `ProfileManager.loadProfile()`:
- Default: `true` (maintains backward compatibility)
- When viewing other users: pass `false` to prevent posting `profileDidUpdate`
- Only the current user's profile updates should clear the feed cache

## Changes Made

### 1. ProfileManager.swift
- Added `isCurrentUser: Bool = true` parameter to `loadProfile()`
- Only posts `profileDidUpdate` notification when `isCurrentUser == true`
- Updated documentation to clarify this loads "a user's profile" not just current user

### 2. UserProfileView.swift  
- Updated to pass `isCurrentUser: isCurrentUser` when calling `loadProfile()`
- This correctly passes `false` when viewing other users, `true` when viewing own profile

## Testing

To verify the fix works:
1. Open app and ensure feed loads ✅
2. Tap search icon
3. Search for and view another user's profile (e.g., @watagumostudio)
4. Close search
5. **Expected**: Feed should still be visible with all posts
6. **Before fix**: Feed would be empty with "No posts yet"

## Impact

**Benefits**:
- Fixes UX bug where feed disappears after viewing profiles
- Reduces unnecessary Firestore reads (no feed reload after viewing other users)
- Maintains proper separation: only current user profile changes trigger feed refresh

**Backward Compatibility**: ✅ All existing calls to `loadProfile()` use default parameter, no breaking changes

## Notes

- This reveals an architectural issue: `ProfileManager` being reused for non-current users
- **Post-MVP**: Consider refactoring UserProfileView to directly call `FirebaseService.fetchUserProfile()` instead of creating local ProfileManager instances
- For now, the `isCurrentUser` parameter provides a clean fix with minimal changes

