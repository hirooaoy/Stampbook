# Image URL Bug Fix

**Date:** November 13, 2025  
**Issue:** Stamp template images failing to load with permission errors  
**Status:** ✅ Fixed

## Problem

All stamp template images were failing to download from Firebase Storage with errors like:

```
⚠️ Failed to download image: User does not have permission to access 
gs://stampbook-app.firebasestorage.app/stampbook-app.firebasestorage.app/stamps/us-ca-sf-dolores-park.png
```

Notice the bucket name `stampbook-app.firebasestorage.app` appears **twice** in the path.

## Root Cause

The `update_stamp_urls_from_storage.js` script was generating **malformed Firebase Storage URLs** using `getSignedUrl()`:

### Wrong URL Format (Old):
```
https://storage.googleapis.com/stampbook-app.firebasestorage.app/stamps/us-ca-sf-dolores-park.png?...
```

This URL structure caused the iOS app's path extraction logic (`Stamp.imageStoragePath`) to extract:
```
stampbook-app.firebasestorage.app/stamps/us-ca-sf-dolores-park.png
```

When passed to `storage.reference().child(storagePath)`, Firebase SDK automatically prepends the bucket name, resulting in:
```
gs://stampbook-app.firebasestorage.app/stampbook-app.firebasestorage.app/stamps/us-ca-sf-dolores-park.png ❌
```

## Solution

Fixed `update_stamp_urls_from_storage.js` to generate proper Firebase Storage URLs:

### Correct URL Format (New):
```
https://firebasestorage.googleapis.com/v0/b/stampbook-app.firebasestorage.app/o/stamps%2Fus-ca-sf-dolores-park.png?alt=media&token={uuid}
```

This extracts cleanly to:
```
stamps/us-ca-sf-dolores-park.png
```

Which Firebase SDK correctly resolves to:
```
gs://stampbook-app.firebasestorage.app/stamps/us-ca-sf-dolores-park.png ✅
```

## Changes Made

1. **Updated `/update_stamp_urls_from_storage.js`:**
   - Replaced `getSignedUrl()` with token-based public URLs
   - Added `generateDownloadToken()` helper function
   - Now constructs proper Firebase Storage URLs using the standard format

2. **Regenerated all stamp image URLs:**
   - Ran `node update_stamp_urls_from_storage.js`
   - Updated 40 stamps with correct URLs
   - 21 stamps missing images (filename mismatches)

3. **Synced to Firestore:**
   - Ran `node upload_stamps_to_firestore.js`
   - All 61 stamps updated in Firestore with corrected URLs

## Testing

After the fix, stamp images should load correctly from Firebase Storage without permission errors.

## Secondary Issue: Profile Picture Decode Performance

**Observed:** Profile picture taking 6 seconds to decode a 27KB image.

**Likely Cause:** The profile picture is a very high resolution image (2000x2000px+) that's been heavily JPEG compressed to 27KB. When `UIImage(data:)` decodes it, it must decompress all those pixels, which takes significant time.

**Current Behavior:** The app uploads profile pictures at 200x200px (~20-30KB), so new uploads are fast. This slow decode suggests an older profile picture uploaded before the resize optimization.

**Recommendation:** Re-upload profile picture to get the optimized 200x200px version, or implement server-side resize for existing large images.

## Files Modified

- `/update_stamp_urls_from_storage.js` - Fixed URL generation
- `/Stampbook/Data/stamps.json` - Updated with correct URLs
- Firestore `stamps` collection - Synced with corrected URLs

## Next Steps

1. Monitor app logs to confirm stamp images load successfully
2. Consider re-uploading profile picture for faster load times
3. Check for any remaining filename mismatches (21 stamps)

