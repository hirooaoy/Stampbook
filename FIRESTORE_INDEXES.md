# Firestore Indexes Required

This document lists all **required** Firestore indexes for the Stampbook app to function correctly.

## ⚠️ Critical: User Ranking Index

**Without this index, user ranking will NOT work.**

### Index Configuration

**Collection:** `users`  
**Fields Indexed:**
- `totalStamps` (Ascending)

### Why Needed?

The app calculates user ranks by querying:
```swift
db.collection("users")
  .whereField("totalStamps", isGreaterThan: userTotalStamps)
  .count
```

Firestore requires a composite index for queries that:
- Filter on a field (`totalStamps`)
- Use inequality operators (`isGreaterThan`)
- Count results

### How to Create

#### Option 1: Automatic (Recommended)
1. Run the app and view a profile (your own or someone else's)
2. **The app will fail** with an error message
3. Click the link in the error message - it will open Firebase Console
4. Click **"Create Index"** - Firebase will auto-configure it
5. Wait 2-5 minutes for index to build
6. ✅ Done!

#### Option 2: Manual via Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Firestore Database** → **Indexes**
4. Click **"Create Index"**
5. Configure:
   - **Collection ID:** `users`
   - **Fields to index:**
     - Field: `totalStamps` | Order: **Ascending**
   - **Query scope:** Collection
6. Click **"Create"**
7. Wait 2-5 minutes for index to build

#### Option 3: Using Firebase CLI
Add to `firestore.indexes.json`:
```json
{
  "indexes": [
    {
      "collectionGroup": "users",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "totalStamps",
          "order": "ASCENDING"
        }
      ]
    }
  ]
}
```

Then deploy:
```bash
firebase deploy --only firestore:indexes
```

### Verification

After creating the index:
1. Wait for "Building" → "Enabled" status in Firebase Console
2. Open the app and view a profile
3. Rank should display (e.g., "#42" instead of "...")
4. Check console logs for: `✅ User rank: #42`

---

## Future Indexes (Not Required Yet)

These are optional optimizations for future features:

### Feed Sorting Optimization
Currently, the feed fetches all stamps from followed users and sorts them in-app.

**Future optimization:** If following many users (50+), consider sorting in Firestore:
- Collection: `users/{userId}/collected_stamps`
- Fields: `userId` (Ascending), `collectedDate` (Descending)

This would allow fetching only the most recent N stamps per user.

### Leaderboard Query
If you add a leaderboard page showing top users:
- Collection: `users`
- Fields: `totalStamps` (Descending)

### Search by Username
If you add user search by prefix:
- Already works without index (uses existing equality + range query)

---

## Cost Considerations

**Index Storage:** Negligible (<1MB for 10k users)  
**Index Writes:** 1 write per user per stamp collected  
**Query Reads:** 1 count aggregation per profile view

**Estimated Cost (10k users, 100 profile views/day):**
- ~$0.03/day (~$1/month)

---

## Troubleshooting

### "Missing Index" Error
**Symptom:** Rank shows "..." forever, console shows index error  
**Fix:** Create the index using Option 1 above

### "Building" for too long
**Symptom:** Index stuck in "Building" status for >10 minutes  
**Fix:** Cancel and recreate the index

### Rank shows incorrect value
**Symptom:** Rank doesn't match expected value  
**Check:**
1. Is the index fully built? (Check Firebase Console)
2. Is `totalStamps` updating correctly in Firestore?
3. Check console logs for calculation errors

---

## Need Help?

If you encounter issues:
1. Check Firebase Console → Firestore → Indexes
2. Look for error messages in Xcode console
3. Verify your Firestore rules allow reading `users` collection

