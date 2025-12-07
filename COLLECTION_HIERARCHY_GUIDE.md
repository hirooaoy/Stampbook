# Quick Reference: Collection Hierarchy in collections.json

## Example Structure

```
📱 Collections Tab (Top Level - parentId: null)
│
├── 🗾 Japan (container)
│   │
│   ├── 🏯 Osaka (container, parentId: "japan")
│   │   ├── 🏯 Osaka Must Visits (leaf, parentId: "japan-osaka") → STAMPS
│   │   ├── 🍜 Osaka Must Eats (leaf, parentId: "japan-osaka") → STAMPS
│   │   └── ☕ Osaka Coffee (leaf, parentId: "japan-osaka") → STAMPS
│   │
│   ├── 🗼 Tokyo (container, parentId: "japan")
│   │   ├── 🗼 Tokyo Must Visits (leaf, parentId: "japan-tokyo") → STAMPS
│   │   ├── 🍣 Tokyo Must Eats (leaf, parentId: "japan-tokyo") → STAMPS
│   │   └── ☕ Tokyo Coffee (leaf, parentId: "japan-tokyo") → STAMPS
│   │
│   └── ⛩️ Kyoto (container, parentId: "japan")
│       ├── ⛩️ Kyoto Temples (leaf, parentId: "japan-kyoto") → STAMPS
│       └── 🌸 Kyoto Gardens (leaf, parentId: "japan-kyoto") → STAMPS
│
├── 🌉 San Francisco (container)
│   ├── 🌉 SF Must Visits (leaf, parentId: "san-francisco") → STAMPS
│   ├── ☕ SF Coffee (leaf, parentId: "san-francisco") → STAMPS
│   ├── 🌱 SF Community Gardens (leaf, parentId: "san-francisco") → STAMPS
│   └── 🌳 Golden Gate Park (leaf, parentId: "san-francisco") → STAMPS
│
├── 🏞️ US National Parks (container)
│   ├── 🏔️ Yosemite (leaf, parentId: "us-national-parks") → STAMPS
│   ├── 🏜 Grand Canyon (leaf, parentId: "us-national-parks") → STAMPS
│   ├── 🦬 Yellowstone (leaf, parentId: "us-national-parks") → STAMPS
│   └── ... (more parks)
│
├── 🗽 New York (container)
│   └── 🐴 Central Park (leaf, parentId: "new-york") → STAMPS
│
├── 🎬 TV & Movie Landmarks (container)
│   ├── 🎥 Iconic Movie Landmarks (leaf, parentId: "movie-tv-landmarks") → STAMPS
│   └── 💕 Offline Love Nice (leaf, parentId: "movie-tv-landmarks") → STAMPS
│
└── ✈️ Airports of the World (leaf) → STAMPS DIRECTLY
```

## Collection Types Explained

### 🗂️ Container (has children)
- Shows list of child collections when tapped
- Progress bar aggregates from all descendants
- Uses `ParentCollectionDetailView`
- Can be at ANY depth level

**Examples:** Japan, Osaka, US National Parks

### 📄 Leaf (has stamps)
- Shows grid of stamps when tapped
- Progress bar shows actual stamp collection progress
- Uses `CollectionDetailView`
- Must be the final level in a hierarchy

**Examples:** Osaka Must Visits, SF Coffee, Airports

### 📊 Top-Level (no parent)
- Appears in main Collections tab
- Can be either container OR leaf
- `parentId: null` (or not present)

**Examples:** Japan, San Francisco, Airports

## Adding New Collections

### Pattern 1: Simple Collection (2 levels)
```json
// Parent
{ "id": "paris", "name": "Paris", "parentId": null }

// Children (leaves)
{ "id": "paris-landmarks", "name": "Paris Landmarks", "parentId": "paris" }
{ "id": "paris-cafes", "name": "Paris Cafes", "parentId": "paris" }
```

### Pattern 2: Nested Collection (3+ levels)
```json
// Grandparent (top level)
{ "id": "europe", "name": "Europe", "parentId": null }

// Parent (middle tier)
{ "id": "europe-france", "name": "France", "parentId": "europe" }

// Children (leaves)
{ "id": "france-paris", "name": "Paris", "parentId": "europe-france" }
{ "id": "france-nice", "name": "Nice", "parentId": "europe-france" }
```

### Pattern 3: Standalone Collection (1 level)
```json
// No children, contains stamps directly
{ "id": "airports", "name": "Airports", "parentId": null, "totalStamps": 9 }
```

## ID Naming Convention

**Format:** `{region}-{city}-{category}`

**Examples:**
- `japan` (top level)
- `japan-osaka` (middle tier)
- `osaka-must-visits` (leaf)
- `tokyo-coffee` (leaf)

**Why:** Keeps IDs organized and prevents conflicts

## Fields Reference

```json
{
  "id": "osaka-must-visits",          // Unique identifier
  "emoji": "🏯",                       // Display emoji
  "name": "Osaka Must Visits",         // Display name
  "description": "Essential spots",    // Subtitle
  "region": "osaka",                   // For future filtering
  "totalStamps": 5,                    // Count (0 for containers)
  "parentId": "japan-osaka",           // Parent collection ID (null for top-level)
  "isParent": true                     // Legacy field (optional now)
}
```

## Rules

✅ **DO:**
- Keep depth to 2-3 levels max
- Use clear, descriptive names
- Set `totalStamps` for leaf collections
- Use consistent emoji themes

❌ **DON'T:**
- Create circular references (A→B→A)
- Mix stamps and children in one collection
- Nest more than 4 levels deep (UX suffers)
- Use duplicate IDs

## Quick Test

After adding collections to `collections.json`:

1. Run: `node upload_collections_to_firestore.js`
2. Open app → Collections tab
3. Verify:
   - Top-level collections appear
   - Tapping container shows children
   - Tapping leaf shows stamps
   - Back button works through all levels
   - Progress bars show correct totals

