# Photo Flow in Stampbook - Simple Explanation

## 📸 Two Types of Images

### 1. **Stamp Images** (Official stamp artwork)
- Source: Firebase Storage `stamps/` folder
- Created by: You (admin) using ChatGPT + Figma
- Display: `.fit` (shows full stamp, no cropping)

### 2. **User Photos** (User-uploaded photos)
- Source: Local device + Firebase Storage `users/{userId}/stamps/` folder
- Created by: Users via PhotosPicker
- Display: `.fill` (fills square, crops edges)

---

## 🔄 User Photo Flow (Step by Step)

### Step 1: User Picks Photo
```
User taps "Add Photos" 
→ PhotosPicker opens
→ User selects 1-5 photos from camera roll
```

### Step 2: Save Locally
```swift
// ImageManager.saveImage()

1. Compress full-res image (max 2400px, 0.8MB)
   Original: 4032×3024 (12MP photo)
   Saved: 2400×1800 (~800KB)
   
2. Generate thumbnail (512×512 with PADDING)
   ⚠️ Key: Thumbnail has white/transparent padding around it
   Why: Uses generateThumbnail() which is aspect-FIT
   
3. Save both to Documents folder:
   - Full-res: "stampId_timestamp_uuid.jpg"
   - Thumbnail: "stampId_timestamp_uuid_thumb.jpg"
```

**Example Files:**
```
Documents/
  us-ca-sf-ferry-building_1731789123_ABC123.jpg       ← Full-res (800KB)
  us-ca-sf-ferry-building_1731789123_ABC123_thumb.jpg ← Thumbnail (40KB, WITH PADDING)
```

### Step 3: Upload to Firebase
```swift
// ImageManager.uploadPhotos()

Uploads both files to Firebase Storage:
  - Full-res: users/{userId}/stamps/{stampId}/filename.jpg
  - Thumbnail: users/{userId}/stamps/{stampId}/filename_thumb.jpg
```

### Step 4: Update Firestore
```swift
// StampsManager.userCollection.addImage()

Updates Firestore document:
users/{userId}/collectedStamps/{stampId}
{
  userImageNames: ["filename.jpg"],
  userImagePaths: ["users/.../filename.jpg"]
}
```

---

## 🖼️ Display Flow (How Photos Appear)

### Viewing YOUR OWN Photos
```
PhotoGalleryView
  → AsyncThumbnailView
    → 1. Check memory cache (ImageCacheManager)
    → 2. Check disk cache (Documents folder)
    → 3. If found: Display thumbnail
    → 4. If not: Download from Firebase
```

### Viewing OTHER USERS' Photos (Feed)
```
FeedView / PostDetailView
  → PhotoGalleryView (userId + userPhotos passed in)
    → AsyncThumbnailView
      → 1. Check memory cache
      → 2. Try disk cache (won't find it)
      → 3. Download from Firebase Storage
      → 4. Cache for next time
```

---

## 🎨 Display Logic (THE KEY PART)

### Stamp Images (CachedImageView.stampPhoto)
```swift
// Uses .fit - shows full stamp
aspectRatio(contentMode: .fit)
frame(width: 106, height: 106)
cornerRadius: 0

Result: Full stamp visible, might have padding (that's OK!)
```

### User Photos (AsyncThumbnailView)
```swift
// Uses .fill - crops edges
aspectRatio(contentMode: .fill)  // Scales to fill
frame(width: 106, height: 106)   // Constrains size (CRITICAL!)
clipped()                         // Crops overflow

Result: Fills entire square, padding is hidden by cropping!
```

---

## 🧠 Why This Works

### The Thumbnail Has Padding (512×512 with image centered)
```
┌─────────────────┐  512×512 thumbnail
│░░░░░░░░░░░░░░░░░│  ← Padding (transparent/white)
│░░┌───────────┐░░│
│░░│   PHOTO   │░░│  ← Actual photo (smaller)
│░░└───────────┘░░│
│░░░░░░░░░░░░░░░░░│  ← Padding
└─────────────────┘
```

### Stamp Image Display (.fit)
```
Shows entire 512×512 → Padding visible ✅
Perfect for stamps (want to see full artwork)
```

### User Photo Display (.fill)
```
Scales to fill 106×106 → Crops padding ✅
Only center of photo visible (crops edges)
Perfect for user photos (want filled square)
```

---

## 📝 Key Takeaways

1. **Thumbnails** always have padding (generated with aspect-fit)
2. **Stamp images** use `.fit` → padding is visible (shows full stamp)
3. **User photos** use `.fill` → padding is cropped (shows center, fills square)
4. **The frame(width:height:)** BEFORE `.clipped()` is CRITICAL for `.fill` to work!

Without the frame:
```swift
.aspectRatio(contentMode: .fill)  // Doesn't know what to fill!
.clipped()                         // ❌ Doesn't work
```

With the frame:
```swift
.aspectRatio(contentMode: .fill)  // Fill a 106×106 space
.frame(width: 106, height: 106)   // Here's the space!
.clipped()                         // ✅ Crops overflow perfectly
```

---

## 🔍 Cache Layers

### Memory Cache (ImageCacheManager)
- Fast: ~0.001s lookup
- Limit: 200 thumbnails (~1MB total)
- Cleared: On memory warning, app background

### Disk Cache (Documents folder)
- Medium: ~0.01s lookup
- Limit: No limit (100-200 photos typical)
- Cleared: Never (unless user deletes app)

### Firebase Storage
- Slow: ~0.5-2s download
- Limit: Unlimited
- Cleared: Never (permanent storage)

---

## ✅ Final Summary

**Stamp images** → Use `.fit` → Show full stamp with any padding
**User photos** → Use `.fill` + frame + clip → Fill square, crop edges

Simple! No complex thumbnail regeneration needed. Just different display logic for different image types.

