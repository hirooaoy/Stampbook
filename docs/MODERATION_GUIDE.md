# 🗑️ Stamp Moderation Tools

Quick reference for managing stamps in production.

## ✅ Implementation Complete

The visibility system is now active! You can:
- Remove reported stamps (soft delete)
- Restore mistakenly removed stamps
- Ready for temporary event stamps (just add dates to JSON)

---

## 🛠️ Admin Scripts

### Remove a Stamp (Moderation)

When users report inappropriate content:

```bash
node remove_stamp.js <stamp-id> "<reason>"
```

**Example:**
```bash
node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"
```

**What happens:**
- ❌ Stamp disappears from map/collections for all users
- ✅ Users who collected it keep it (fair!)
- ✅ Data preserved in Firebase for audit
- ⏱️ Takes effect on next app open (usually seconds)

---

### Restore a Stamp

If you removed it by mistake:

```bash
node restore_stamp.js <stamp-id>
```

**Example:**
```bash
node restore_stamp.js us-ca-sf-good-stamp
```

**What happens:**
- ✅ Stamp reappears on map/collections
- ⏱️ Takes effect on next app open

---

### List Removed Stamps (Audit)

See what's currently hidden:

```bash
node list_removed_stamps.js
```

Shows:
- Total active/removed/hidden stamps
- Reasons for removal
- Dates removed

---

## 📅 Temporary Event Stamps (Future)

Ready to use! Just add dates to `stamps.json`:

```json
{
  "id": "sf-outside-lands-2025",
  "name": "Outside Lands Festival",
  "status": "active",
  "availableFrom": "2025-08-08T00:00:00Z",
  "availableUntil": "2025-08-10T23:59:59Z",
  ...
}
```

Run `node upload_stamps_to_firestore.js` and it automatically:
- ⏰ Appears August 8
- ⏰ Disappears August 11
- ✅ Collectors keep it forever

---

## 🔄 Workflow Examples

### Scenario 1: User Reports Stamp

1. User emails: "Stamp XYZ shows inappropriate content"
2. You review and confirm
3. Run: `node remove_stamp.js us-ca-sf-xyz "User reported inappropriate"`
4. Stamp disappears for all users
5. Done! ✅

### Scenario 2: Permanent Deletion

If you made a mistake adding it:

1. Remove from `Stampbook/Data/stamps.json`
2. Run: `node upload_stamps_to_firestore.js`
3. Script deletes it from Firebase
4. Collectors still keep it
5. Done! ✅

### Scenario 3: Create Weekend Event

1. Add to `stamps.json` with dates:
   ```json
   "availableFrom": "2025-12-06T00:00:00Z",
   "availableUntil": "2025-12-08T23:59:59Z"
   ```
2. Run: `node upload_stamps_to_firestore.js`
3. Stamp auto-appears/disappears on schedule
4. Done! ✅

---

## 🔍 How It Works

### Soft Delete (Moderation)
- Stamp gets `status: "removed"` in Firebase
- Firebase cache updates with new status
- App filters it out via `isCurrentlyAvailable`
- No app reinstall needed!

### Why It's Fast
- Firebase persistent cache propagates status changes
- Users see updates within seconds
- No network issues - cache handles it

### Why Users Keep Collected Stamps
- Filtering only affects uncollected stamps
- `collected_stamps` collection is separate
- Fair to users who collected legitimately

---

## 📊 Status Reference

| Status | Map | Collections | Firebase | User's Collection |
|--------|-----|-------------|----------|-------------------|
| `active` or `null` | ✅ Shows | ✅ Shows | ✅ Exists | ✅ If collected |
| `removed` | ❌ Hidden | ❌ Hidden | ✅ Exists | ✅ Keep it |
| `hidden` | ❌ Hidden | ❌ Hidden | ✅ Exists | ✅ Keep it |
| (deleted from JSON) | ❌ Gone | ❌ Gone | ❌ Deleted | ✅ Keep it |

---

## 🚨 Important Notes

1. **Soft delete vs Hard delete:**
   - Soft (remove_stamp.js): Data stays, audit trail
   - Hard (remove from JSON): Data deleted, no recovery

2. **Users keep collected stamps:**
   - This is intentional and fair
   - They earned it when it was available

3. **Cache updates:**
   - Usually instant (seconds)
   - Force quit + reopen guarantees fresh data

4. **Backup before removal:**
   - Upload script has backup: `upload_stamps_to_firestore.js.backup`
   - Can restore if needed

---

## ✅ Quick Command Reference

```bash
# Remove reported stamp
node remove_stamp.js <id> "<reason>"

# Restore stamp
node restore_stamp.js <id>

# Check what's removed
node list_removed_stamps.js

# Sync all changes
node upload_stamps_to_firestore.js
```

---

## 📖 Full Documentation

See `docs/VISIBILITY_SYSTEM_IMPLEMENTATION.md` for complete technical details.

