# Firebase Storage Cleanup Guide

## Problem Fixed

Previously, when users deleted photos in the app, the images were removed from local storage and Firestore, but **not always deleted from Firebase Storage**. This caused:

- **Storage Costs**: Paying for deleted images
- **Data Inconsistency**: Firebase Storage had images not referenced in Firestore
- **Privacy Issues**: Deleted user photos still existed in the cloud

### Root Causes
1. **Async Fire-and-Forget**: Deletion happened in background `Task` with silent error handling
2. **Missing Storage Paths**: Images uploaded before Firebase integration had no `userImagePaths`
3. **Empty Paths**: Some images had empty string `""` storage paths
4. **Network Failures**: If deletion failed due to network, local state was still updated
5. **Race Conditions**: App could close before async deletion completed

## Solution Implemented

### 1. Synchronous Deletion with Error Handling
- Firebase Storage deletion now happens **before** local state update
- Errors are properly caught and reported to user
- Deletion is blocking - UI shows "Deleting photo..." spinner

### 2. Intelligent Error Handling
- **Network Errors**: Queued for retry when network available
- **Permission Errors**: Shown to user immediately
- **Not Found Errors**: Treated as success (already deleted)
- **Other Errors**: Block deletion and show error to user

### 3. Offline Support with Retry Queue
- Failed deletions due to network issues are saved to `pendingDeletions`
- Automatic retry when user signs in or network becomes available
- Persisted across app restarts

### 4. Edge Case Handling
- Empty paths: Logged but don't block deletion
- Missing paths: Handled gracefully
- Invalid path formats: Caught and reported

### 5. User Feedback
- Loading spinner during deletion
- Clear error messages for failures
- Success confirmation in logs

## Files Modified

### Core Changes
1. **`UserStampCollection.swift`**
   - Changed `removeImage()` to `async throws`
   - Added pending deletions tracking and retry mechanism
   - Network error detection and queueing

2. **`ImageManager.swift`**
   - Enhanced `deleteImageFromFirebase()` with specific error handling
   - Added Firebase error code checking (-13010, -13020, -13030)
   - New cleanup utilities for orphaned images

3. **`FullScreenPhotoView.swift`**
   - Updated UI to show deletion progress
   - Proper error alerts for failed deletions
   - Async deletion with loading states

## Cleaning Up Existing Orphaned Images

### Option 1: Manual Cleanup via Firebase Console
1. Go to Firebase Console → Storage
2. Navigate to `users/{userId}/stamps/{stampId}/`
3. Compare files with your Firestore data
4. Manually delete orphaned files

### Option 2: Programmatic Cleanup (Recommended)

The app now includes cleanup utilities. To use them:

```swift
// In your debug/admin view or one-time migration:
Task {
    guard let userId = authManager.userId else { return }
    
    for collectedStamp in stampsManager.userCollection.collectedStamps {
        do {
            let deletedCount = try await ImageManager.shared.cleanupOrphanedImages(
                userId: userId,
                stampId: collectedStamp.stampId,
                validImagePaths: collectedStamp.userImagePaths
            )
            print("Cleaned up \(deletedCount) orphaned images for stamp \(collectedStamp.stampId)")
        } catch {
            print("Failed to cleanup stamp \(collectedStamp.stampId): \(error)")
        }
    }
}
```

### Option 3: Cloud Function (Most Scalable)

For production with many users, create a Cloud Function:

```javascript
// functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

exports.cleanupOrphanedImages = functions.https.onCall(async (data, context) => {
  // Verify authentication
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
  }
  
  const userId = context.auth.uid;
  const db = admin.firestore();
  const storage = admin.storage().bucket();
  
  // Get user's collected stamps from Firestore
  const stampsSnapshot = await db
    .collection('users')
    .doc(userId)
    .collection('collected_stamps')
    .get();
  
  // Build set of valid image paths
  const validPaths = new Set();
  stampsSnapshot.forEach(doc => {
    const stamp = doc.data();
    if (stamp.userImagePaths) {
      stamp.userImagePaths.forEach(path => validPaths.add(path));
    }
  });
  
  // List all files in user's storage
  const [files] = await storage.getFiles({
    prefix: `users/${userId}/stamps/`
  });
  
  // Delete orphaned files
  let deletedCount = 0;
  for (const file of files) {
    if (!validPaths.has(file.name)) {
      await file.delete();
      deletedCount++;
      console.log(`Deleted orphaned file: ${file.name}`);
    }
  }
  
  return { deletedCount, message: `Cleaned up ${deletedCount} orphaned images` };
});
```

## Testing the Fix

### Test Case 1: Normal Deletion (Online)
1. Add photo to stamp
2. Wait for upload to complete
3. Delete photo
4. ✅ Should see "Deleting photo..." spinner
5. ✅ Photo should disappear from UI
6. ✅ Check Firebase Storage - file should be gone

### Test Case 2: Offline Deletion
1. Enable Airplane Mode
2. Try to delete photo
3. ✅ Should see error: "Failed to delete photo from cloud storage"
4. ✅ Photo should remain in UI (not deleted)
5. Turn off Airplane Mode
6. Sign out and back in
7. ✅ Pending deletion should retry automatically

### Test Case 3: Image Without Storage Path
1. Delete old image (from before Firebase migration)
2. ✅ Should see warning log: "No storage path found"
3. ✅ Image should be removed from local storage
4. ✅ No Firebase Storage deletion attempted (nothing to delete)

### Test Case 4: Already Deleted Image
1. Manually delete image from Firebase Storage
2. Try to delete same image in app
3. ✅ Should succeed (Firebase returns "not found" → treated as success)

## Monitoring

### Logs to Watch For

**Success:**
```
✅ Deleted image from Firebase Storage: users/123/stamps/abc/photo.jpg
✅ Photo deleted successfully from Firebase and local storage
```

**Network Error (Queued):**
```
⚠️ Failed to delete from Firebase Storage: The Internet connection appears to be offline
📝 Network error detected - adding to pending deletions for retry
```

**Permission Error (Blocked):**
```
❌ Permission denied deleting from Firebase Storage: users/123/stamps/abc/photo.jpg
```

**Retry Success:**
```
🔄 Retrying 3 pending deletions...
✅ Successfully deleted previously failed image: users/123/stamps/abc/photo.jpg
✅ All pending deletions completed
```

## Prevention

The fix ensures future deletions work correctly, but to prevent similar issues:

1. **Always test deletion flows** before deploying
2. **Monitor Firebase Storage size** in console
3. **Set up Storage Rules** to auto-delete old files (if needed)
4. **Use Cloud Functions** for batch cleanup tasks
5. **Implement cost alerts** in Firebase Console

## Cost Savings

If you had 100 orphaned images (avg 2MB each):
- **Before**: 200MB stored = ~$0.005/month
- **After Fix**: 0MB = $0

While small per month, costs compound over time with many users.

## Questions?

If you notice orphaned images still appearing:
1. Check the logs for error messages
2. Verify `userImagePaths` are being saved correctly
3. Run the cleanup utility
4. Check Firebase Storage Rules for permission issues

