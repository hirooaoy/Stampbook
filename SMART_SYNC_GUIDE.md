# Smart Sync Guide 🔄

Your sync scripts now have **intelligent safety checks** to prevent accidental data loss!

## How It Works

Both scripts now compare Firebase and local JSON before syncing:
- **Detects differences** between Firebase and local JSON
- **Warns you** if data will be deleted
- **Aborts by default** if there's a risk of data loss
- **Suggests the right action** to fix the problem

---

## Your Workflow (Web Admin → Firebase First)

Since you'll be adding stamps via https://stampbook-app.web.app/admin-upload-stamp.html, follow this workflow:

### ✅ After Adding Stamps via Web Admin

```bash
# Step 1: Export from Firebase to local JSON (ALWAYS safe)
node export_stamps_from_firestore.js
```

This will:
- Pull all Firebase stamps into your local `stamps.json`
- Show you how many stamps were added
- ✅ Safe to run anytime - only adds new stamps to local

```bash
# Step 2: Commit to git for backup
git add Stampbook/Data/stamps.json
git commit -m "Add new stamps: [stamp names]"
git push
```

---

## The Scripts

### 📥 `export_stamps_from_firestore.js` (Firebase → JSON)

**Normal behavior:**
- Checks if local JSON has stamps that Firebase doesn't
- If yes: **ABORTS** and tells you to run upload first
- If no: **Safely exports** Firebase to local JSON

**Example warning:**
```
⚠️  WARNING: Your local JSON has stamps that are NOT in Firebase!
⚠️  Running this script will DELETE these stamps from your local JSON:

   🗑️  Grand Canyon South Rim (us-az-grand-canyon-south-rim)
   🗑️  Desert View Watchtower (stamp-desert-view-watchtower-1763159893662)

❌ EXPORT ABORTED FOR SAFETY!

💡 What you probably want to do:
   1. Run: node upload_stamps_to_firestore.js
   2. This will push your local stamps to Firebase
   3. THEN run this script again

🚨 If you really want to OVERWRITE local JSON with Firebase data:
   Run: node export_stamps_from_firestore.js --force
```

**Force overwrite:**
```bash
node export_stamps_from_firestore.js --force
```
⚠️ This will replace local JSON with Firebase data, deleting any local-only stamps

---

### 📤 `upload_stamps_to_firestore.js` (JSON → Firebase)

**Normal behavior:**
- Checks if Firebase has stamps that local JSON doesn't
- If yes: **ABORTS** and tells you to export first
- If no: **Safely uploads** local JSON to Firebase

**Example warning:**
```
⚠️  WARNING: Firebase has stamps that are NOT in your local JSON!
⚠️  Running this script will DELETE these stamps from Firebase:

   🗑️  Grand Canyon South Rim (us-az-grand-canyon-south-rim)
   🗑️  Desert View Watchtower (stamp-desert-view-watchtower-1763159893662)

❌ SYNC ABORTED FOR SAFETY!

💡 What you probably want to do:
   1. Run: node export_stamps_from_firestore.js
   2. This will pull Firebase stamps into your local JSON
   3. THEN run this script again

🚨 If you really want to DELETE these stamps from Firebase:
   Run: node upload_stamps_to_firestore.js --force
```

**Force delete:**
```bash
node upload_stamps_to_firestore.js --force
```
⚠️ This will make Firebase match local JSON, deleting any Firebase-only stamps

---

## Safe Scenarios (Auto-Proceed)

The scripts will automatically proceed without warnings in these cases:

### ✅ Scenario 1: Same stamps everywhere
```
📊 Firebase: 72 stamps
📊 Local JSON: 72 stamps
📊 Only in Firebase: 0 stamps
📊 Only in Local: 0 stamps

✅ Safe to sync: Firebase and local JSON have the same stamps
```

### ✅ Scenario 2: Firebase has new stamps (export)
```
📊 Firebase: 75 stamps
📊 Local JSON: 72 stamps
📊 Only in Firebase: 3 stamps
📊 Only in Local: 0 stamps

✅ Safe to export: Firebase has new stamps, local JSON will be updated
```

### ✅ Scenario 3: Local has new stamps (upload)
```
📊 Firebase: 72 stamps
📊 Local JSON: 75 stamps
📊 Only in Firebase: 0 stamps
📊 Only in Local: 3 stamps

✅ Safe to sync: JSON has new stamps, Firebase will be updated
```

---

## What Caused the Grand Canyon Deletion?

**Timeline:**
1. You added Grand Canyon stamps via web admin → stamps in Firebase ✅
2. Stamps were NOT in local `stamps.json` ❌
3. You ran `upload_stamps_to_firestore.js` → deleted Grand Canyon from Firebase 💀

**Why?**
The old script would silently delete anything in Firebase that wasn't in local JSON. No warning, no confirmation.

**Now:**
The new script would have **STOPPED** and shown you:
```
⚠️  WARNING: Firebase has 2 stamps that are NOT in your local JSON!
   🗑️  Grand Canyon South Rim
   🗑️  Desert View Watchtower

❌ SYNC ABORTED FOR SAFETY!
Run: node export_stamps_from_firestore.js first
```

---

## Best Practices

1. **Always export after using web admin:**
   ```bash
   node export_stamps_from_firestore.js
   ```

2. **Commit to git regularly:**
   ```bash
   git add Stampbook/Data/stamps.json
   git commit -m "Add stamps"
   git push
   ```

3. **Never use `--force` unless you're 100% sure**

4. **Keep Firebase as source of truth** since you're using web admin

---

## Emergency Recovery

If you accidentally delete stamps:

1. Check git history:
   ```bash
   git log -- Stampbook/Data/stamps.json
   ```

2. Restore from previous commit:
   ```bash
   git checkout <commit-hash> -- Stampbook/Data/stamps.json
   node upload_stamps_to_firestore.js
   ```

3. If not in git, check Firebase backups (if enabled)

---

**🎉 You're now protected from accidental deletions!**

