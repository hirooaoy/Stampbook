# Image Cache Key Mismatch Fix

## Problem

Users were seeing "Image will load when you have a strong connection" banner even when they had strong internet connection and the images were already cached.

## Root Cause

**Cache key mismatch** between how images are stored and how they're checked:

### When Caching (ImageManager)
Images are cached using URL-based keys that include the stamp ID and URL hash:
```swift
let urlHash = abs(imageUrl.hashValue)
let cacheKey = "\(stampId)_\(urlHash).png"
```

### When Checking Cache (StampDetailView - BEFORE FIX)
The check was using just the filename from the storage path:
```swift
let filename = (storagePath as NSString).lastPathComponent  // Wrong!
if ImageCacheManager.shared.getFullImage(key: filename) != nil {
    return true
}
```

Since the keys didn't match, the check always returned `false` even when images were cached.

## Solution

Updated `StampDetailView.swift` to use the **same cache key generation logic** as ImageManager:

### Fixed `isStampImageCached` (line 182-206)
```swift
private var isStampImageCached: Bool {
    guard let imageUrl = stamp.imageUrl, !imageUrl.isEmpty else {
        return true
    }
    
    // Generate the same cache key used by ImageManager when downloading
    let urlHash = abs(imageUrl.hashValue)
    let cacheKey = "\(stamp.id)_\(urlHash).png"
    
    // Check both memory cache and disk cache
    if ImageCacheManager.shared.getFullImage(key: cacheKey) != nil {
        return true
    }
    
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let fileURL = documentsPath.appendingPathComponent(cacheKey)
    if FileManager.default.fileExists(atPath: fileURL.path) {
        return true
    }
    
    return false
}
```

### Fixed `copyStampImage()` (line 1059-1078)
Also updated the copy function to use the correct cache key:
```swift
// Generate the same cache key used by ImageManager when downloading
let urlHash = abs(imageUrl.hashValue)
let cacheKey = "\(stamp.id)_\(urlHash).png"

// Try to get from cache (memory or disk)
imageToCopy = ImageCacheManager.shared.getFullImage(key: cacheKey)
    ?? ImageManager.shared.loadImage(named: cacheKey)

// Pass imageUrl to download function for consistent cache key
imageToCopy = try await ImageManager.shared.downloadAndCacheImage(
    storagePath: storagePath,
    stampId: stamp.id,
    imageUrl: imageUrl  // Added this parameter
)
```

## Result

✅ Banner no longer shows when images are already cached  
✅ Proper detection of both memory and disk cache  
✅ Copy function uses correct cache keys  
✅ No unnecessary re-downloads

## Files Changed

- `Stampbook/Views/Shared/StampDetailView.swift`
  - Fixed `isStampImageCached` computed property (lines 182-206)
  - Fixed `copyStampImage()` function (lines 1059-1078)
  - Added smooth fade animation to status banner (0.3s ease-in)

## Testing

1. Collect a stamp with an image
2. Navigate to stamp detail view
3. ✅ Banner should NOT appear (image loads from cache)
4. Go offline
5. Navigate to stamp detail view again  
6. ✅ Image still shows (disk cache works)
7. Copy stamp image
8. ✅ Copy works instantly (uses cached image)
9. For slow connections: banner fades in smoothly (0.3s animation)

