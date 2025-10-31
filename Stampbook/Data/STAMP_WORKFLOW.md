# 📍 Stamp Addition Workflow

## Quick Start

1. **Add stamps to `stamps.json`** (see template below)
2. **Run migration:** `node migrate_to_firebase.js`
3. **Restart app** → New stamps appear!

---

## Stamp JSON Template

```json
{
  "id": "us-ca-sf-your-new-spot",
  "name": "Your New Spot Name",
  "latitude": 37.12345678,
  "longitude": -122.12345678,
  "address": "123 Main St\nSan Francisco, CA, USA 94103",
  "imageName": "empty",
  "collectionIds": ["sf-must-visits"],
  "about": "Description of what this place is...",
  "notesFromOthers": [
    "User tip or review 1",
    "User tip or review 2"
  ],
  "thingsToDoFromEditors": [
    "Editor recommendation 1",
    "Editor recommendation 2"
  ]
}
```

---

## ⚠️ CRITICAL: GPS Coordinates

**ALWAYS use exact coordinates from Google Maps pin drops!**

### How to Get Coordinates:

1. Open Google Maps (desktop or mobile)
2. **Drop a pin at the EXACT experience location:**
   - For viewpoints: the actual viewing spot
   - For cafes: the front entrance
   - For parks: the main entrance or iconic spot
   - For summits: the actual peak
3. Click on the pin → coordinates appear at top
4. Copy coordinates (should have 8+ decimal places)
   - Example: `37.79367890, -122.48374567`
5. Paste into JSON

**Why precision matters:**
- App has 100-meter collection radius
- Imprecise coordinates = users can't collect the stamp
- 8 decimal places = ~1 millimeter accuracy

---

## Image Setup (Optional)

### Using "empty" (placeholder):
```json
"imageName": "empty"
```

### Adding Custom Image:

1. **In Xcode:**
   - Open `Assets.xcassets`
   - Right-click → New Image Set
   - Name it exactly like stamp ID: `us-ca-sf-your-new-spot`
   - Drag image into 1x slot

2. **In stamps.json:**
   ```json
   "imageName": "us-ca-sf-your-new-spot"
   ```

---

## Collections

### Using Existing Collections:

Available collection IDs:
- `sf-must-visits` - San Francisco Must Visits
- `sf-coffee` - Great Coffee in San Francisco
- `sf-golden-gate-park` - Explore Golden Gate Park
- `sf-community-gardens` - Community Gardens in San Francisco
- `acadia-must-visits` - Acadia National Park Explorer's Log

### Creating New Collection:

Edit `collections.json`:

```json
{
  "id": "your-collection-id",
  "name": "Your Collection Name",
  "description": "Brief description",
  "region": "san-francisco"
}
```

Then reference in stamps:
```json
"collectionIds": ["your-collection-id"]
```

---

## ID Naming Convention

Format: `country-state-city-location-name`

Examples:
- `us-ca-sf-golden-gate-bridge`
- `us-ca-sf-blue-bottle-coffee`
- `us-ny-nyc-central-park`
- `us-me-acadia-bubble-rock`

Rules:
- All lowercase
- Hyphens for spaces
- No special characters
- Unique across all stamps

---

## Bulk Adding Workflow

Adding 10+ stamps at once:

```bash
# 1. Collect data in spreadsheet:
#    - Name, GPS coords, Address, Description, Collection
#
# 2. Copy JSON template, fill in details
#    Start with "empty" images
#
# 3. Add all stamps to stamps.json
#
# 4. Run migration once:
cd /path/to/Stampbook
node migrate_to_firebase.js

# 5. Restart app
#    All new stamps appear!
#
# 6. (Later) Add images for priority stamps
```

---

## Migration Script

### What it does:
- ✅ Uploads new stamps to Firestore
- ✅ Updates existing stamps (by ID)
- ✅ Adds new collections
- ✅ Initializes stamp statistics
- ✅ Safe to run multiple times (won't duplicate)

### Command:
```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
node migrate_to_firebase.js
```

### Output:
```
✅ Successfully uploaded 37 stamps to Firestore
✅ Successfully uploaded 5 collections to Firestore
✅ Successfully initialized statistics for 37 stamps
```

---

## Testing

1. **After migration, verify in Firebase Console:**
   - https://console.firebase.google.com/project/stampbook-app/firestore/data/stamps

2. **In app:**
   - Restart app
   - New stamps appear on map
   - Navigate to stamp detail to verify all fields

3. **Collection radius test:**
   - Go to stamp location physically
   - App should show "Collect" button when within 100m

---

## Troubleshooting

**Stamp not appearing on map:**
- Check coordinates are correct format (number, not string)
- Verify stamp has valid `collectionIds`
- Restart app after migration

**Can't collect stamp at location:**
- Coordinates likely imprecise
- Drop new pin at exact spot in Google Maps
- Update stamps.json with new coordinates
- Re-run migration

**Image not showing:**
- Verify image name matches stamp ID exactly
- Check image exists in Assets.xcassets
- Restart app

---

## JSON vs Firestore

**Source of Truth:** JSON files (`stamps.json`, `collections.json`)

**Workflow:**
1. Edit JSON (version controlled, backed up)
2. Run migration script
3. Changes deploy to Firestore
4. App reads from Firestore

**If you edit directly in Firebase Console:**
- Changes will work in app
- But JSON will be out of sync
- Update JSON later to keep them aligned

---

## Quick Reference

```bash
# Edit stamps
code Stampbook/Data/stamps.json

# Edit collections  
code Stampbook/Data/collections.json

# Run migration
node migrate_to_firebase.js

# View in Firebase
open https://console.firebase.google.com/project/stampbook-app/firestore
```

