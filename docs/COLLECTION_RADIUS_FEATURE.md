# Collection Radius Feature

## Overview
Added variable collection radiuses to stamps to support different types of locations (e.g., small viewpoints vs. large airports or fields).

## Implementation

### Radius Categories
- **`regular`**: 150m (~1.5 blocks) - Default for most stamps
- **`large`**: 500m - Parks, beaches, neighborhoods  
- **`xlarge`**: 1000m (1km) - Airports, huge parks like Bison Paddock, large fields

### Data Model Changes

#### Stamp Model (`Stampbook/Models/Stamp.swift`)
- Added `collectionRadius: String` property
- Added computed property `collectionRadiusInMeters: Double` that converts category to meters
- Updated CodingKeys, init, decoder, and encoder to support the new field

#### Stamps Data (`Stampbook/Data/stamps.json`)
- All 37 stamps now have explicit `"collectionRadius": "regular"` field
- Ready for easy updates to "large" or "xlarge" as needed

### Code Updates
Updated collection range checks in:
- `StampDetailView.swift` - Changed from `MapView.stampCollectionRadius` to `stamp.collectionRadiusInMeters`
- `MapView.swift` - Updated 3 locations to use stamp-specific radius

### Firestore Sync
✅ All changes uploaded to Firestore via `upload_stamps_to_firestore.js`

## Usage

### Changing a Stamp's Collection Radius

1. Edit `Stampbook/Data/stamps.json`
2. Change `"collectionRadius"` from `"regular"` to `"large"` or `"xlarge"`
3. Run sync script: `node upload_stamps_to_firestore.js`

Example for Bison Paddock:
```json
{
  "id": "us-ca-sf-ggp-bison-paddock",
  "name": "Bison Paddock",
  "collectionRadius": "xlarge"
}
```

### Examples of When to Use Each Size

**Regular (150m):**
- Specific monuments or viewpoints
- Coffee shops
- Building entrances
- Most stamps

**Large (500m):**
- Medium-sized parks
- Beaches
- Neighborhoods
- Gardens

**XLarge (1000m):**
- Airports
- Massive parks (like Bison Paddock in Golden Gate Park)
- Large agricultural fields
- Sports stadiums
- Large natural areas

## Testing
- ✅ No linter errors
- ✅ All stamps synced to Firestore
- ✅ Backward compatible (defaults to "regular" if field missing)
- ✅ Ready to test in app

## Next Steps
1. Test in the iOS app
2. Identify stamps that should be "large" or "xlarge"
3. Update those stamps in `stamps.json`
4. Run upload script

## Notes
- The old hardcoded `MapView.stampCollectionRadius` constant (150m) is still in the code but no longer used
- All distance checks now use the stamp's individual `collectionRadiusInMeters` property

