# Firestore Indexes - MVP Configuration

This document lists all **required** Firestore indexes for the Stampbook app MVP.

## ⚠️ Note: User Ranking Index (DISABLED FOR MVP)

The `totalStamps` index exists in `firestore.indexes.json` but is **NOT actively used** in the MVP.

### Why It's Still There

The index was created during development for the user ranking feature, which has been disabled for MVP (see `RANK_FEATURE_DISABLED.md`).

**You can:**
- ✅ **Leave it:** Won't hurt, takes minimal storage (<1MB for 10k users)
- ✅ **Remove it:** Won't break anything since rank queries are commented out

### To Remove the Index

If you want to clean up unused indexes:

#### Option 1: Remove from firestore.indexes.json
```json
{
  "indexes": [
    // Remove this entire block:
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "totalStamps",
          "order": "ASCENDING"
        }
      ]
    },
    // Keep the other indexes below...
  ]
}
```

Then deploy:
```bash
firebase deploy --only firestore:indexes
```

#### Option 2: Via Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Firestore Database** → **Indexes**
4. Find the `users` collection index on `totalStamps`
5. Click the **Delete** button (trash icon)
6. Confirm deletion

---

## ✅ Required Indexes for MVP

### 1. Geohash Index (Stamps by Location)
**Collection:** `stamps`  
**Fields:**
- `geohash` (Ascending)
- `__name__` (Ascending)

**Used for:** Loading nearby stamps on the map based on user's location

### 2. Likes by Post Index
**Collection:** `likes`  
**Fields:**
- `postId` (Ascending)
- `createdAt` (Descending)

**Used for:** Showing likes on posts in the social feed, ordered by most recent

### 3. Comments by Post Index
**Collection:** `comments`  
**Fields:**
- `postId` (Ascending)
- `createdAt` (Ascending)

**Used for:** Showing comments on posts in the social feed, ordered chronologically

---

## Cost Considerations (MVP)

**Index Storage:** ~1-2 MB total (negligible)  
**Index Writes:** Minimal - only on stamp collection, likes, comments  
**Query Performance:** Fast lookups with proper indexes

**Estimated Cost:**
- Geohash queries: ~$0.01/day
- Like/comment queries: ~$0.02/day
- **Total: ~$1/month for active usage**

---

## Post-MVP: If Re-enabling Rank Feature

If you decide to re-enable user ranking post-MVP:

1. Keep/restore the `totalStamps` index (it's already defined)
2. Uncomment all rank-related code (see `RANK_FEATURE_DISABLED.md`)
3. Deploy indexes: `firebase deploy --only firestore:indexes`
4. Wait 2-5 minutes for index to build
5. Test with small user base first

---

## Verification

To verify indexes are working:

1. **Check Firebase Console:**
   - All indexes show "Enabled" status (not "Building" or "Error")

2. **Test in App:**
   - Map loads stamps near your location
   - Feed shows likes and comments
   - No "missing index" errors in console

3. **Monitor Costs:**
   - Firebase Console → Usage tab
   - Should be <10,000 reads/day for typical MVP usage

---

## Troubleshooting

### "Missing Index" Error
**Symptom:** App shows index error in console  
**Fix:** 
1. Click the error link to create index automatically
2. OR manually create via Firebase Console
3. Wait 2-5 minutes for indexing to complete

### Slow Queries
**Symptom:** Map or feed loads slowly  
**Check:**
1. Are all indexes "Enabled" in Firebase Console?
2. Is network connection stable?
3. Are you querying too much data? (check limits)

### High Costs
**Symptom:** Firebase bill is unexpectedly high  
**Check:**
1. Firestore Console → Usage → Reads per day
2. Look for excessive queries (should be <10k/day for MVP)
3. Check for infinite loops in feed loading

---

## Need Help?

If you encounter index issues:
1. Check Firebase Console → Firestore → Indexes
2. Review Xcode console for specific error messages
3. Verify Firestore rules allow required operations
4. Check `firestore.rules` for permission issues

