# 🚀 Quick Start: Moving Stamps to Firebase

**Full guide:** See `MOVING_STAMPS_TO_FIREBASE_GUIDE.md`

---

## What You Need

1. Firebase project ID (find in Firebase Console → Project Settings)
2. Your stamp images (named like: `us-ca-sf-baker-beach.jpg`)

---

## Step-by-Step Commands

### 1. Find Your Firebase Project ID

```bash
# Go to: https://console.firebase.google.com/
# Click your project → ⚙️ Settings
# Copy "Project ID" (example: stampbook-app)
```

### 2. Generate Firebase Storage URLs

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook

# Replace YOUR-PROJECT-ID with your actual project ID
node generate_image_urls.js YOUR-PROJECT-ID
```

This automatically updates all stamps in `stamps.json` with correct Firebase Storage URLs.

### 3. Upload Images to Firebase Storage

**Option A: Use the helper script (easiest)**

```bash
# Put all your stamp images in a folder, then:
./upload_stamp_images.sh /path/to/your/images/folder
```

**Option B: Upload via Firebase Console**
1. Go to [Firebase Console](https://console.firebase.google.com/) → Storage
2. Create `stamps/` folder
3. Upload images one by one (filename must match stamp ID)

### 4. Update Firebase Storage Rules (Make Images Public)

```bash
# Go to: Firebase Console → Storage → Rules tab
# Copy-paste these rules:
```

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Stamp images - public read
    match /stamps/{imageId} {
      allow read: if true;
      allow write: if false;
    }
    
    // User photos (keep existing)
    match /users/{userId}/photos/{photoId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

Click **"Publish"**

### 5. Upload Stamps to Firestore

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
node upload_stamps_to_firestore.js
```

Should see: `✅ Successfully uploaded X stamps`

### 6. Build & Test

```bash
# Open in Xcode
open Stampbook.xcodeproj

# Build and run (Cmd + R)
# Stamps should appear on map with images from Firebase
```

---

## Verify Everything Works

1. **Firebase Console → Storage**
   - Check `stamps/` folder has your images
   - Example: `us-ca-sf-baker-beach.jpg`

2. **Firebase Console → Firestore**
   - Check `stamps` collection exists
   - Click any stamp document
   - Should see `imageUrl` field with Firebase Storage URL

3. **In Your App**
   - Open app → Map view
   - Stamps should appear
   - Tap a stamp → image should load (might take 1-2 seconds)

---

## For Stamps WITHOUT Images Yet

Edit `stamps.json` and set:
```json
{
  "id": "stamp-with-no-image",
  "imageUrl": ""  ← Empty string
}
```

Then run:
```bash
node upload_stamps_to_firestore.js
```

The app will show a placeholder image.

---

## Adding New Stamps (After Initial Setup)

```bash
# 1. Add to stamps.json
code Stampbook/Data/stamps.json

# 2. Generate URL (auto-adds imageUrl field)
node generate_image_urls.js YOUR-PROJECT-ID

# 3. Upload image to Firebase Storage → stamps/ folder
firebase storage:upload ./new-image.jpg stamps/us-ca-sf-new-spot.jpg

# OR use the helper script:
./upload_stamp_images.sh /path/to/new/images

# 4. Upload to Firestore
node upload_stamps_to_firestore.js

# 5. Done! (No app rebuild needed)
```

---

## Troubleshooting

### Images not showing

```bash
# Check Storage Rules are public
# Go to: Firebase Console → Storage → Rules
# Must have: allow read: if true;
```

### Wrong Firebase URLs

```bash
# Re-generate URLs with correct project ID
node generate_image_urls.js YOUR-CORRECT-PROJECT-ID

# Then re-upload to Firestore
node upload_stamps_to_firestore.js
```

### Script not found

```bash
# Make sure you're in the right directory
cd /Users/haoyama/Desktop/Developer/Stampbook

# Make scripts executable
chmod +x upload_stamp_images.sh
```

---

## Summary

```bash
# Complete setup in 5 commands:
node generate_image_urls.js YOUR-PROJECT-ID
./upload_stamp_images.sh /path/to/images
# → Update Storage Rules in Firebase Console
node upload_stamps_to_firestore.js
# → Build & run app in Xcode
```

**That's it!** Your stamps are now in Firebase. 🎉

You can now add 500+ stamps without rebuilding the app!

