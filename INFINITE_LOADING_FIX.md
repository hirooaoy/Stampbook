# Infinite Loading Fix

## Issue Summary
User reported two infinite loading issues after logging out and back in:
1. **Profile Picture**: Infinite loading spinner on profile picture in StampsView
2. **Collections Tab**: Infinite loading on collections tab in StampsView

The feed was working fine, suggesting the issue was isolated to the StampsView profile-related components.

## Root Causes

### 1. Profile Picture Infinite Loading
**File**: `Stampbook/Views/Shared/ProfileImageView.swift`

**Problem**: The retry mechanism in `ProfileImageView` was scheduling retries even when there was no valid avatar URL or when the URL was empty. This caused an infinite retry loop:
```swift
// OLD CODE (lines 64-82)
.onAppear {
    guard avatarUrl != nil, image == nil else { return }
    // ... would retry forever if avatarUrl was ""
}
```

**Fix**: Added validation to only retry when a valid, non-empty avatar URL exists:
```swift
.onAppear {
    guard let url = avatarUrl, !url.isEmpty, image == nil else { return }
    // ... only retry if URL is valid and non-empty
}
```

Additionally, replaced `AsyncImage` in StampsView with `ProfileImageView` for consistency and better error handling.

### 2. Collections Tab Infinite Loading
**File**: `Stampbook/Views/Profile/StampsView.swift`

**Problem**: The `isLoadingMetadata` state was initialized to `true` instead of `false`, and there was no timeout mechanism to handle stuck loads.

**Fixes Applied**:
1. **Fixed Initial State**: Changed `isLoadingMetadata` from `true` to `false`
   ```swift
   // OLD: @State private var isLoadingMetadata = true
   // NEW: @State private var isLoadingMetadata = false
   ```

2. **Added Guard with Logging**: Enhanced the duplicate load prevention with debug logging
   ```swift
   guard !isLoadingMetadata else {
       print("⚠️ [CollectionsContent] Already loading metadata, skipping")
       return
   }
   ```

3. **Added Timeout Mechanism**: Implemented 10-second timeout to prevent infinite hangs
   - Uses task groups to race the load task against a timeout task
   - If timeout occurs, gracefully exits loading state and shows empty/error UI
   - Logs detailed debug information for troubleshooting

4. **Enhanced Debug Logging**: Added comprehensive logging throughout the metadata load process
   ```swift
   print("🔄 [CollectionsContent] Starting metadata load")
   print("📚 [CollectionsContent] Processing \(collections.count) collections")
   print("✅ [CollectionsContent] \(collection.name): \(collected)/\(total)")
   ```

### 3. ProfileManager Duplicate Load Prevention
**File**: `Stampbook/Managers/ProfileManager.swift`

**Problem**: Multiple calls to `loadProfile()` could occur simultaneously, causing duplicate network requests and potential state issues.

**Fix**: Added guard to prevent duplicate loads:
```swift
func loadProfile(userId: String, loadRank: Bool = false) {
    if isLoading {
        print("⚠️ [ProfileManager] Already loading profile, skipping duplicate request")
        return
    }
    isLoading = true
    // ...
}
```

## Testing Instructions

1. **Test Profile Picture Loading**:
   - Sign out and sign back in
   - Navigate to Stamps tab
   - Verify profile picture loads without infinite spinner
   - Test with and without avatar URL set

2. **Test Collections Tab**:
   - Navigate to Stamps tab
   - Switch to "Collections" tab
   - Verify collections load within 10 seconds
   - Check console logs for detailed load information

3. **Test Edge Cases**:
   - Test with poor network connection
   - Test with empty avatar URL
   - Test with no collections
   - Test with many collections (>5)

## Debug Output

When running the app, you should see console logs like:

**Profile Loading**:
```
🔄 [ProfileManager] Loading profile for userId: xxx
✅ [ProfileManager] Loaded user profile: John Doe
🖼️ [ProfileImageView] Loading profile picture for userId: xxx, attempt: 0
✅ [ProfileImageView] Profile picture loaded for userId: xxx
```

**Collections Loading**:
```
🔄 [CollectionsContent] Starting metadata load
📚 [CollectionsContent] Processing 5 collections
📚 [StampsManager] Fetching stamps in collection: sf-attractions
✅ [StampsManager] Fetched 12 stamps in collection
✅ [CollectionsContent] San Francisco Attractions: 3/12
... (repeat for each collection)
✅ [CollectionsContent] Metadata load complete
```

**Error Cases**:
```
⚠️ [ProfileImageView] Failed to load profile picture for userId: xxx
❌ [CollectionsContent] Metadata load failed or timed out
```

## Performance Improvements

The fixes also include performance optimizations:
- Profile picture retry logic only triggers for valid URLs (prevents unnecessary work)
- Duplicate profile loads are prevented (reduces Firestore reads)
- Collections loading has timeout protection (prevents UI freeze)
- Enhanced logging helps diagnose issues faster

## Next Steps

If issues persist:
1. Check console logs for specific error messages
2. Verify Firebase connection is working (feed should load)
3. Check if user profile exists in Firestore
4. Verify collections exist in Firestore
5. Test network connection stability

## Files Modified

1. `Stampbook/Views/Shared/ProfileImageView.swift`
   - Fixed retry logic to validate avatar URL
   - Added better null/empty checks

2. `Stampbook/Views/Profile/StampsView.swift`
   - Fixed `isLoadingMetadata` initial state
   - Added timeout mechanism for collections loading
   - Replaced AsyncImage with ProfileImageView
   - Enhanced debug logging

3. `Stampbook/Managers/ProfileManager.swift`
   - Added duplicate load prevention
   - Enhanced debug logging

