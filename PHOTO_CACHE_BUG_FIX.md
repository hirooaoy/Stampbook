# Photo Cache Bug Fix

## Bug Report

**Issue**: After deleting photo 1 from a stamp with 2 photos, the feed still displays the deleted photo 1, but when clicked, it shows photo 2 instead.

**Root Cause**: The `AsyncThumbnailView` in the feed was displaying stale cached thumbnails because:

1. When a photo is deleted, the arrays in `UserStampCollection` are updated (photo 2 becomes photo 1)
2. The deleted image is removed from the memory cache
3. However, the `AsyncThumbnailView` component in the feed retained its `@State private var thumbnail` value
4. Since SwiftUI uses `id: \.offset` for the ForEach, it didn't recognize that the image at index 0 had changed
5. There was also a cache key inconsistency: `AsyncThumbnailView` used `imageName` as the cache key, while `ImageManager` used `imageName_thumb.jpg`

## Fix Applied

### 1. Force View Recreation with `.id()` Modifier

**File**: `Stampbook/Views/Shared/PhotoGalleryView.swift`

**Change**: Added `.id(imageName)` to the `AsyncThumbnailView` to force SwiftUI to recreate the view when the image name changes.

```swift
AsyncThumbnailView(
    imageName: imageName,
    storagePath: getStoragePath(for: imageName),
    stampId: stampId
)
.frame(width: 120, height: 120)
.cornerRadius(12)
.id(imageName) // 🔧 FIX: Force view recreation when imageName changes
```

**Why This Works**: When photo 1 is deleted, photo 2 (with a different filename) moves to index 0. The `.id(imageName)` tells SwiftUI that this is a completely different image, forcing it to:
- Dispose of the old `AsyncThumbnailView` instance
- Create a new instance with the new image name
- Load the correct thumbnail from cache or Firebase

### 2. Fix Cache Key Inconsistency

**File**: `Stampbook/Views/Shared/PhotoGalleryView.swift`

**Change**: Updated `AsyncThumbnailView.loadThumbnail()` to use the thumbnail filename (with `_thumb` suffix) as the cache key, consistent with how `ImageManager` stores thumbnails.

**Before**:
```swift
if let cachedThumbnail = ImageCacheManager.shared.getThumbnail(key: imageName) {
    // ...
}
```

**After**:
```swift
let thumbnailKey = imageName.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")

if let cachedThumbnail = ImageCacheManager.shared.getThumbnail(key: thumbnailKey) {
    // ...
}
```

**Why This Works**: The cache keys are now consistent across the codebase:
- `ImageManager.deleteImage()` removes thumbnails using the `_thumb` suffix
- `AsyncThumbnailView` now checks the cache using the same `_thumb` suffix
- When a photo is deleted, its thumbnail is properly cleared from the cache

## Testing

To verify the fix:

1. Add 2 photos to any stamp
2. Go to the stamp detail view
3. Delete photo 1
4. Return to the feed
5. Verify that photo 2 is now displayed (not the deleted photo 1)
6. Click the photo in the feed to open the detail view
7. Verify that the correct photo is shown

## Technical Details

### How SwiftUI Views are Identified

SwiftUI uses the following to determine if a view should be reused or recreated:
1. The `id` parameter in `ForEach` (we use `id: \.offset` which is the array index)
2. The `.id()` modifier on the view itself (we added this)

Without the `.id(imageName)` modifier:
- Photo 1 at index 0 is deleted
- Photo 2 moves to index 0
- SwiftUI sees "index 0 still exists" and reuses the existing view
- The view's `@State private var thumbnail` retains the old photo 1 image

With the `.id(imageName)` modifier:
- Photo 1 at index 0 is deleted
- Photo 2 (different filename) moves to index 0
- SwiftUI sees "the view at index 0 has a different id" and creates a new view
- The new view loads the correct thumbnail

### Cache Key Strategy

The app uses a two-tier caching strategy:
1. **Memory cache** (fast, volatile): Stores recently used images in RAM
2. **Disk cache** (slower, persistent): Stores images in the app's documents directory

For thumbnails:
- Disk filename: `stamp_id_timestamp_uuid_thumb.jpg`
- Memory cache key: Same as disk filename (with `_thumb` suffix)
- This ensures consistency across both cache layers

## Related Files

- `Stampbook/Views/Shared/PhotoGalleryView.swift` - Photo gallery UI and thumbnail loading
- `Stampbook/Managers/ImageManager.swift` - Image caching and Firebase operations
- `Stampbook/Managers/ImageCacheManager.swift` - In-memory cache management
- `Stampbook/Models/UserStampCollection.swift` - Stamp data management and deletion logic

