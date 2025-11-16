# Thumbnail Migration Plan

## Problem
Beta testers have old "padded" thumbnails cached locally. After we fixed Firebase Storage thumbnails (using `fix_firebase_thumbnails.js`), existing users still see the old versions from their local cache.

## Solution
Automatic version-based re-download that forces one-time refresh of all thumbnails.

## How It Works

### For Beta Testers (Now):
1. User opens app after update
2. App checks: `thumbnailVersion < 2` → TRUE
3. **Forces re-download** from Firebase (ignores local cache)
4. Downloads new cropped thumbnails
5. Sets `thumbnailVersion = 2`
6. Future loads use fast cache

### For Production Users (After Launch):
1. Fresh install → thumbnails are cropped from day 1
2. No migration needed
3. Normal caching works perfectly

## Code Location

**File:** `Stampbook/Managers/ImageManager.swift`
**Function:** `downloadAndCacheThumbnail()`
**Lines:** 338-356, 376-379

```swift
// TODO: REMOVE BEFORE LAUNCH - This is only for fixing thumbnails during beta/testing
// ==================================================================================
let thumbnailVersion = UserDefaults.standard.integer(forKey: "thumbnailVersion")
let currentThumbnailVersion = 2

let shouldForceRedownload = thumbnailVersion < currentThumbnailVersion

if !shouldForceRedownload, let cachedThumbnail = loadThumbnail(named: baseCacheKey) {
    return cachedThumbnail
}
// ================== END OF MIGRATION CODE TO REMOVE ==================
```

## ⚠️ BEFORE LAUNCH CHECKLIST

- [ ] Remove migration code (lines 338-356 in `ImageManager.swift`)
- [ ] Remove version update code (lines 376-379 in `ImageManager.swift`)
- [ ] Revert to simple cache check:
  ```swift
  // Check if thumbnail already cached
  if let cachedThumbnail = loadThumbnail(named: baseCacheKey) {
      return cachedThumbnail
  }
  ```
- [ ] Delete this file (`THUMBNAIL_MIGRATION_PLAN.md`)
- [ ] Delete `fix_firebase_thumbnails.js` (no longer needed)
- [ ] Delete `find_all_users_with_photos.js` (no longer needed)

## Cost Impact

### During Beta (With Migration):
- Each user re-downloads ~5-10 thumbnails once
- Cost: ~50KB/thumbnail × 10 = ~500KB per user
- 3 beta testers = ~1.5KB bandwidth

### After Launch (Normal Operation):
- No migration needed
- 66% bandwidth savings from memory cache
- Zero duplicate downloads

## Timeline

- **2024-11-16**: Ran `fix_firebase_thumbnails.js` to fix Firebase Storage
- **2024-11-16**: Added migration code for beta testers
- **Before launch**: Remove migration code
- **After launch**: Production users get cropped thumbnails from day 1

## Testing

Test the migration by:
1. Install current version (with old thumbnails)
2. Update to new version (with migration code)
3. Open app and view photos
4. Check logs for "✅ Downloaded thumbnail from Firebase"
5. Verify photos are now cropped properly
6. Close and reopen app
7. Check logs for "Disk cache hit" (no re-download)

## Notes

- Migration is **progressive** - happens as user browses
- No loading screen or user notification needed
- Thumbnails refresh naturally as they're viewed
- Old cached files remain on disk (harmless, iOS clears when storage is low)

