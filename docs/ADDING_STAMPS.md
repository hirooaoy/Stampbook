# 📍 Complete Guide: Managing Stamps in Stampbook

## 🆕 Adding a New Stamp

### Step 1: Get GPS Coordinates [[memory:10452842]]
⚠️ **CRITICAL**: Always use exact coordinates from Google Maps!

1. Open Google Maps (desktop or mobile)
2. **Drop a pin at the EXACT experience location:**
   - Viewpoints: the actual viewing spot
   - Cafes: the front entrance
   - Parks: main entrance or iconic spot
   - Summits: the actual peak
3. Click the pin → coordinates appear at top
4. Copy coordinates (must have **8+ decimal places**)
   - Example: `37.79367890, -122.48374567`
5. Keep these for Step 2

**Why precision matters:**
- App has **100-meter collection radius**
- Imprecise = users can't collect the stamp
- 8+ decimals = ~1mm accuracy (perfect!)

### Step 2: Add to stamps.json

```bash
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/stamps.json
```

Add your stamp using this template:

```json
{
  "id": "us-ca-sf-your-new-spot",
  "name": "Your New Spot Name",
  "latitude": 37.12345678,
  "longitude": -122.12345678,
  "address": "123 Main St\nSan Francisco, CA, USA 94103",
  "imageUrl": "",
  "collectionIds": ["sf-must-visits"],
  "about": "What makes this place special? History, vibe, why visit, etc.",
  "notesFromOthers": [
    "💡 Pro tip from locals",
    "🎯 What to look for when you visit"
  ],
  "thingsToDoFromEditors": [
    "📸 Take a photo from the west side",
    "🌅 Best at sunset",
    "☕ Grab coffee at nearby cafe after"
  ]
}
```

**Field Guide:**

| Field | Required? | Description | Example |
|-------|-----------|-------------|---------|
| `id` | ✅ | Unique ID (format: `country-state-city-name`) | `us-ca-sf-baker-beach` |
| `name` | ✅ | Display name | `Baker Beach` |
| `latitude` | ✅ | GPS latitude (8+ decimals) | `37.79367890` |
| `longitude` | ✅ | GPS longitude (8+ decimals) | `-122.48374567` |
| `address` | ✅ | Two-line format: `Street\nCity, State, Country ZIP` | `Gibson Rd\nSan Francisco, CA, USA 94129` |
| `imageUrl` | ⚠️ | Firebase Storage URL (leave `""` for now) | `""` |
| `collectionIds` | ✅ | Which collections include this stamp | `["sf-must-visits"]` |
| `about` | ✅ | Rich description (200-500 chars) | `"A stunning Pacific-facing beach..."` |
| `notesFromOthers` | ✅ | Tips, insights (2-5 items) | `["Best at sunset", "Cold + windy"]` |
| `thingsToDoFromEditors` | ✅ | Action items (2-5 items) | `["Walk to Battery to Bluffs"]` |

**Available Collections:**
- `sf-must-visits` - San Francisco Must Visits
- `sf-coffee` - Great Coffee in San Francisco
- `sf-golden-gate-park` - Explore Golden Gate Park
- `sf-community-gardens` - Community Gardens
- `acadia-must-visits` - Acadia National Park

### Step 3: Upload to Firebase

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
node upload_stamps_to_firestore.js
```

✨ **Geohashes are auto-generated!** The script will:
- Upload all stamps to Firestore
- Automatically generate geohash for map queries
- Update existing stamps if already present

### Step 4: Add Stamp Image (Optional)

**Option A: Firebase Storage** (Recommended - Best Quality)

```bash
# Upload image to Firebase Storage
cd /Users/haoyama/Desktop/Developer/Stampbook
./upload_stamp_images.sh
```

Then update the stamp in Firebase Console with the storage URL, or re-run the upload script.

**Option B: Local Assets** (Fastest - Bundled with App)

1. Find a high-quality photo (landscape, 1200x800px minimum)
2. Open Xcode
3. Navigate to `Stampbook/Assets.xcassets`
4. Right-click → **New Image Set**
5. Name it **exactly** like stamp ID: `us-ca-sf-your-new-spot`
6. Drag image into **1x slot only**
7. Update `stamps.json`:
   ```json
   "imageName": "us-ca-sf-your-new-spot"
   ```
8. Re-run: `node upload_stamps_to_firestore.js`

**Option C: Use Placeholder** (Quickest - Add Image Later)

Just leave `imageUrl: ""` - the app will show a clean placeholder.

### Step 5: Test in App

1. **Force quit** the app (swipe up from app switcher)
2. **Reopen** the app
3. Check **Map tab** → stamp appears at correct location
4. Check **Stamps tab** → stamp appears in collections
5. Go to location physically → verify 100m collection radius works

---

## ✏️ Editing an Existing Stamp

### Quick Edit (Text Only)

**If editing description, tips, or minor details:**

```bash
# 1. Edit the stamp in stamps.json
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/stamps.json

# 2. Re-upload (updates existing stamp)
node upload_stamps_to_firestore.js

# 3. Force quit + reopen app
```

### Location Fix (Coordinates Changed)

**If stamp is uncollectable due to wrong GPS:**

```bash
# 1. Drop NEW pin at exact location in Google Maps
# 2. Copy new coordinates (8+ decimals)
# 3. Update stamps.json with new lat/long
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/stamps.json

# 4. Re-upload (geohash auto-recalculates)
node upload_stamps_to_firestore.js

# 5. Force quit + reopen app
```

### Image Update

**Replace stamp image:**

```bash
# Option A: Firebase Storage
./upload_stamp_images.sh

# Option B: Local Assets (Xcode)
# 1. Open Assets.xcassets
# 2. Find existing image set (stamp ID)
# 3. Replace image in 1x slot
# 4. Rebuild app
```

---

## 🗂️ Managing Collections

### Add New Collection

**Edit collections.json:**

```bash
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/collections.json
```

**Template:**

```json
{
  "id": "your-collection-id",
  "name": "Your Collection Name",
  "description": "What makes this collection special",
  "region": "san-francisco",
  "totalStamps": 10
}
```

**Then upload:**

```bash
node upload_stamps_to_firestore.js
```

### Add Stamp to Existing Collection

Just update the stamp's `collectionIds` array:

```json
"collectionIds": ["sf-must-visits", "sf-coffee"]
```

Then re-upload stamps.

---

## 🔧 Advanced: Bulk Operations

### Add 10+ Stamps at Once

```bash
# 1. Prepare data in spreadsheet:
#    Name | GPS Coords | Address | Description | Collection

# 2. Convert to JSON using template (one by one)
#    Start with imageUrl: "" for all

# 3. Add all stamps to stamps.json

# 4. Upload once (all stamps + geohashes generated)
node upload_stamps_to_firestore.js

# 5. Test in app

# 6. Add priority images later
```

### Update All Stamps (Mass Edit)

```bash
# 1. Edit multiple stamps in stamps.json
# 2. Re-upload (existing stamps update, new ones add)
node upload_stamps_to_firestore.js
```

The script uses `.set()` which means:
- Existing stamps → update
- New stamps → add
- Safe to run multiple times

---

## 📋 Quick Reference

### Commands

```bash
# Edit stamps
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/stamps.json

# Edit collections
code /Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/collections.json

# Upload to Firebase (auto-generates geohashes)
cd /Users/haoyama/Desktop/Developer/Stampbook
node upload_stamps_to_firestore.js

# Upload stamp images
./upload_stamp_images.sh

# Check stamps in Firebase
node check_stamps_in_firebase.js

# Fix missing geohashes (if added via Firebase Console)
node add_geohash_to_stamps.js

# Open Firebase Console
open https://console.firebase.google.com/project/stampbook-app/firestore
```

### ID Naming Convention

Format: `country-state-city-location-name`

**Examples:**
- `us-ca-sf-golden-gate-bridge`
- `us-ca-sf-blue-bottle-coffee`
- `us-ny-nyc-central-park`
- `us-me-acadia-bubble-rock`

**Rules:**
- All lowercase
- Hyphens for spaces
- No special characters
- Unique across all stamps

### Address Format

```
Street Address
City, State, Country ZIP
```

**Examples:**
- `Gibson Rd\nSan Francisco, CA, USA 94129`
- `1 Ferry Building\nSan Francisco, CA, USA 94111`
- `Tokyo, Japan` (for international without full address)

---

## 🐛 Troubleshooting

### Stamp not appearing on map
- ✅ Check coordinates are numbers (not strings)
- ✅ Verify geohash was generated: `node check_stamps_in_firebase.js`
- ✅ Force quit + reopen app
- ✅ Check Firebase Console for the stamp document

### Can't collect stamp at location
- ⚠️ **Most common**: Coordinates not precise enough
- Drop new pin at **exact spot** in Google Maps (not "nearby")
- Update `stamps.json` with 8+ decimal coordinates
- Re-run: `node upload_stamps_to_firestore.js`
- Test collection radius = 100 meters

### Image not showing
- If using local assets: Verify image name matches stamp ID exactly
- Check image exists in `Assets.xcassets`
- Restart Xcode and rebuild app
- If using Firebase Storage: Check `imageUrl` in Firestore

### Stamps missing geohash (added via Console)
```bash
# If you added stamps directly in Firebase Console
node add_geohash_to_stamps.js
```

---

## 📝 Notes

**Source of Truth:**
- `Stampbook/Data/stamps.json` (local, version controlled)
- `Stampbook/Data/collections.json` (local, version controlled)

**Workflow:**
1. Edit JSON locally ← source of truth
2. Run upload script → syncs to Firestore
3. App reads from Firestore → shows to users

**Direct Firebase Console edits:**
- Changes work in app immediately ✅
- But JSON will be out of sync ⚠️
- Update JSON later to keep aligned

**MVP Scale** [[memory:10673613]]:
- 37 stamps, <100 users, 2 test accounts
- Simple workflows optimized for this scale
- No need for complex automation (yet!)

---

**Remember**: Always get exact GPS coordinates from Google Maps pin drops! The 100-meter collection radius requires precision. 📍
