# Firebase Setup Guide

## Overview

Your app now loads stamps and collections from Firebase Firestore instead of local JSON files. This allows you to add/edit stamps without app updates.

## Migration Steps

### 1. Upload Existing Data to Firebase

You have two options:

#### Option A: Using the Migration Script (Recommended)

1. **Install Node.js dependencies:**
   ```bash
   cd /Users/haoyama/Desktop/Developer/Stampbook
   npm install firebase-admin
   ```

2. **Download Firebase Service Account Key:**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Go to Project Settings → Service Accounts
   - Click "Generate New Private Key"
   - Save the JSON file as `serviceAccountKey.json` in the project root

3. **Run the migration script:**
   ```bash
   node migrate_to_firebase.js
   ```

This will upload all 44 stamps, collections, and initialize statistics.

#### Option B: Manual Upload via Firebase Console

1. Go to Firebase Console → Firestore Database
2. Create collections: `stamps`, `collections`, `stamp_statistics`
3. For each stamp in `Stampbook/Data/stamps.json`:
   - Click "Add document"
   - Set Document ID to the stamp's `id` field
   - Add all fields manually

### 2. Deploy Firestore Security Rules

```bash
firebase deploy --only firestore:rules
```

This allows:
- ✅ Anyone can read stamps/collections (even when not signed in)
- ✅ Only authenticated users can update stamp statistics (when collecting)
- ✅ Only you (via Firebase Console) can write stamps/collections

### 3. Test the App

1. Build and run the app
2. Check console logs - you should see:
   ```
   ✅ Loaded 44 stamps from Firebase
   ✅ Loaded X collections from Firebase
   ```
3. If Firebase is empty or offline, it will fall back to local JSON files

## Adding New Stamps

### Via Firebase Console

1. Go to Firestore Database → `stamps` collection
2. Click "Add document"
3. Set the Document ID to a unique slug (e.g., `us-ca-sf-mission-dolores`)
4. Add these fields:

| Field | Type | Example |
|-------|------|---------|
| `id` | string | `us-ca-sf-mission-dolores` |
| `name` | string | `Mission Dolores` |
| `latitude` | number | `37.76341` |
| `longitude` | number | `-122.42693` |
| `address` | string | `3321 16th St\nSan Francisco, CA, USA 94114` |
| `imageName` | string | `us-ca-sf-mission-dolores` |
| `collectionIds` | array | `["sf-must-visits"]` |
| `about` | string | `Historic Spanish mission...` |
| `notesFromOthers` | array | `["Amazing history!", "Beautiful architecture"]` |
| `thingsToDoFromEditors` | array | `["Visit the cemetery", "Tour the basilica"]` |

5. Click "Save"

**Important:** Remember to follow the [[memory:10452842]] coordinate precision guidelines - always use exact GPS coordinates with 8+ decimal places from Google Maps pin drops.

### Initialize Stamp Statistics

After adding a new stamp, also create a statistics document:

1. Go to Firestore → `stamp_statistics` collection
2. Click "Add document"
3. Set Document ID to the same stamp ID
4. Add these fields:

| Field | Type | Value |
|-------|------|-------|
| `stampId` | string | (same as stamp ID) |
| `totalCollectors` | number | `0` |
| `collectorUserIds` | array | `[]` |
| `lastUpdated` | timestamp | (auto) |

The app will automatically update these when users collect stamps.

## Editing Existing Stamps

1. Go to Firestore Database → `stamps` collection
2. Click on the stamp document you want to edit
3. Modify any field
4. Click "Update"
5. Changes are live immediately - no app update needed!

## Collections Structure

Collections are stored in the `collections` collection:

| Field | Type | Example |
|-------|------|---------|
| `id` | string | `sf-must-visits` |
| `name` | string | `SF Must-Visits` |
| `description` | string | `Essential San Francisco experiences` |

## Database Structure

```
firestore
├── stamps (read: public, write: admin only)
│   └── {stampId}
│       ├── id: string
│       ├── name: string
│       ├── latitude: number
│       ├── longitude: number
│       ├── address: string
│       ├── imageName: string
│       ├── collectionIds: array<string>
│       ├── about: string
│       ├── notesFromOthers: array<string>
│       └── thingsToDoFromEditors: array<string>
│
├── collections (read: public, write: admin only)
│   └── {collectionId}
│       ├── id: string
│       ├── name: string
│       └── description: string
│
├── stamp_statistics (read: public, write: authenticated users)
│   └── {stampId}
│       ├── stampId: string
│       ├── totalCollectors: number
│       ├── collectorUserIds: array<string> (ordered by collection time)
│       └── lastUpdated: timestamp
│
└── users/{userId}/collected_stamps (per-user data)
    └── {stampId}
        ├── stampId: string
        ├── userId: string
        ├── collectedDate: timestamp
        ├── userNotes: string
        ├── userImageNames: array<string>
        └── userImagePaths: array<string>
```

## Troubleshooting

### App shows "Using offline data"

- Firebase Firestore might be empty
- Check internet connection
- Verify Firestore rules are deployed

### "Permission denied" errors

- Ensure Firestore rules are deployed: `firebase deploy --only firestore:rules`
- Check Firebase Console → Rules tab for syntax errors

### Stamps not updating after editing in console

- Force quit and restart the app
- Check Firebase Console logs for errors

## Cost Considerations

**Current Firebase Spark Plan (Free):**
- ✅ 1GB storage (plenty for stamps metadata)
- ✅ 50K document reads/day
- ✅ 20K document writes/day
- ✅ Should support 100+ active users easily

**When to Upgrade to Blaze Plan:**
- Photo uploads (Firebase Storage requires paid plan)
- 100+ concurrent users
- Push notifications

## Future Enhancements

### Remote Image Storage

Currently, stamp images are still in the app's Assets. To enable truly dynamic stamps:

1. Upload stamp images to Firebase Storage or CDN (Cloudflare R2)
2. Add `imageUrl` field to stamp documents
3. Update `StampDetailView` to use `AsyncImage` with URLs
4. Keep `imageName` as fallback for local images

### Real-Time Updates

Enable live updates without app restart:

```swift
// In StampsManager
func observeStamps() {
    db.collection("stamps").addSnapshotListener { snapshot, error in
        // Update stamps in real-time
    }
}
```

### Geohash Queries (for 1000+ stamps)

For better performance with many stamps:

1. Add `geohash` field to stamps
2. Query only stamps near user's location
3. Use [GeoFirestore](https://github.com/imperiumlabs/GeoFirestore-iOS)

---

**Next Steps:**
1. Run migration script to upload data
2. Deploy Firestore rules
3. Test the app
4. Start adding new stamps via Firebase Console! 🎉

