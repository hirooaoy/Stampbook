# Testing URL-Based Image Cache

## Test Plan: Verify Ballast Coffee Image Update

### Prerequisites
- Ballast Coffee stamp already collected in test account
- Old image cached on device
- New image URL in Firestore: `token=73cb8451-e9a8-4c91-a12b-22d7162c4ca4`

---

## Test 1: Verify New Cache Keys Are Generated

**Steps:**
1. Run app in simulator
2. Check console logs when viewing Ballast Coffee stamp
3. Look for log line: `✅ Image loaded from disk cache: us-ca-sf-ballast_XXXXXXXX.png`

**Expected:**
- Cache key includes stampId (`us-ca-sf-ballast`) + hash number
- NOT just `us-ca-sf-ballast-coffee.png`

**Status:** ⬜ Not tested yet

---

## Test 2: Verify Old Cached Image Still Shows (Before Firestore Refresh)

**Steps:**
1. Fresh install or clear Firestore cache
2. Open app offline (airplane mode)
3. View Ballast Coffee stamp

**Expected:**
- Shows old cached image (if available)
- No crash, no error

**Status:** ⬜ Not tested yet

---

## Test 3: Verify New Image Downloads (After Firestore Refresh)

**Steps:**
1. Delete app and reinstall (clean slate)
2. Open app online
3. Collect Ballast Coffee stamp
4. View stamp detail

**Expected:**
- Downloads NEW image (token=73cb8451...)
- Console shows: `⬇️ Downloading image from Firebase: stamps/us-ca-sf-ballast-coffee.png`
- Console shows: `✅ Image cached locally: us-ca-sf-ballast_XXXXXXXX.png`
- New image displayed

**Status:** ⬜ Not tested yet

---

## Test 4: Verify Images Are Instant On Repeat Views

**Steps:**
1. After Test 3, navigate away from Ballast Coffee
2. Navigate back to Ballast Coffee stamp

**Expected:**
- Image loads instantly (no spinner)
- Console shows: `✅ Image loaded from memory cache: us-ca-sf-ballast_XXXXXXXX.png`

**Status:** ⬜ Not tested yet

---

## Test 5: Verify All Other Stamps Still Work

**Steps:**
1. Scroll through all 40 collected stamps
2. Check that all images load

**Expected:**
- No crashes
- All images eventually load (cached or downloaded)
- Performance is good

**Status:** ⬜ Not tested yet

---

## Test 6: Verify User Photos Unchanged

**Steps:**
1. View stamp with user-uploaded photos
2. Add new user photo to a stamp

**Expected:**
- User photos still work normally
- Upload succeeds
- Photos display correctly

**Status:** ⬜ Not tested yet

---

## Manual Verification Checklist

### Files to Check:
```bash
# 1. Check Documents directory in simulator
# Find simulator path:
xcrun simctl get_app_container booted com.stampbook.app data

# 2. List cached images:
ls -lh ~/Library/Developer/CoreSimulator/.../Documents/

# Expected to see:
# - Old format: us-ca-sf-ballast-coffee.png (orphaned)
# - New format: us-ca-sf-ballast_12345678.png (active)
```

### Console Logs to Watch:
- `✅ Image loaded from memory cache:` (instant)
- `✅ Image loaded from disk cache:` (fast)
- `⬇️ Downloading image from Firebase:` (new download)
- `✅ Image cached locally:` (successful cache)

---

## Success Criteria

✅ All tests pass
✅ No crashes or errors
✅ Images load correctly (old and new)
✅ Cache keys include URL hash
✅ Performance is acceptable
✅ User photos still work

---

## Notes

- Old cached images (filename-based) are harmless orphans
- They'll be cleaned by iOS automatically when storage is low
- No need to manually delete them
- Total disk usage: ~80MB (40MB old + 40MB new) for 2-3 weeks
- Eventually old files age out naturally

---

## Rollback Plan (If Needed)

If something breaks:

1. Revert commits:
```bash
git log --oneline -10  # Find commit hash
git revert <commit-hash>
```

2. Or quick fix: Make `imageUrl` parameter optional and ignored
3. Deploy hotfix to TestFlight

But honestly, this change is low-risk. It's a pure cache layer improvement.

