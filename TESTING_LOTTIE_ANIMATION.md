# Testing Lottie Animation - Quick Reference

## Test Stamp Details
- **Name:** TEST - Lottie Animation
- **ID:** `test-lottie-animation`
- **Location:** 690 Guerrero St, San Francisco, CA
- **Coordinates:** 37.76009401956795, -122.4237230135322
- **Image:** Mauna Kea (placeholder)

---

## Your Database Structure (Actual)

```
/stamps (56)                        ← All stamps
/collections (9)                    ← Stamp collections like "SF Must Visits"
/users (2)                          ← User profiles (hiroo, watagumostudio)
  └── /collected_stamps             ← User's collected stamps (subcollection)
      └── {stampId, collectedDate, userRank, userNotes, etc.}
/stamp_statistics (39)              ← Stamp stats (totalCollectors)
/invite_codes (1)                   ← Invite codes

NO SEPARATE FEED COLLECTION ✅
- Feed is computed from /users/{userId}/collected_stamps
- This is CORRECT for your scale (100 users)
```

---

## Testing Workflow

### 1. Collect the Test Stamp
- Open app
- Go to 690 Guerrero St (or use fake location)
- Tap "Collect Stamp"
- **Watch the animation!** (currently confetti, will be penguin later)

### 2. Check What Was Created
```bash
node check_test_stamp_data.js
```

### 3. Reset Everything
```bash
node reset_test_stamp.js
```

This removes:
- Your collected stamp record
- Your stats (decrements totalStamps)
- Stamp statistics

But KEEPS the stamp itself so you can test again!

### 4. Test Again!
Repeat steps 1-3 as many times as needed.

---

## When Completely Done Testing

### Delete Test Stamp Completely:
```bash
node delete_test_stamp_completely.js
```

Then manually remove from `stamps.json`:
1. Open `Stampbook/Data/stamps.json`
2. Delete the last entry (`test-lottie-animation`)
3. Run: `node upload_stamps_to_firestore.js`

---

## Current Animation Setup

**File:** `StampDetailView.swift`
**Animation:** `confetti.json` (placeholder for testing)

**To swap to custom animation:**
1. Add `penguin_stamp_press.json` to Xcode
2. Change line 542 in StampDetailView:
   ```swift
   LottieView(filename: "penguin_stamp_press", play: playAnimation)
   ```

**Animation Specs for Animator:**
- Canvas: Full screen (393×852pt reference for iPhone 15)
- Entry: From RIGHT edge of screen
- Direction: Swoops down and LEFT to stamp the gray box
- Stamp size: 320×320pt (covers the 300×300 gray box)
- Duration: 1.5 seconds
- Contact moment: 0.5s (haptic fires here)

---

## Best Practices You're Following ✅

1. **Feed computed from source of truth** - No duplicate data
2. **Test stamps clearly marked** - `test-` prefix
3. **Easy reset workflow** - Scripts for quick iteration
4. **Correct for scale** - Optimized for 100 users, can scale later

---

## Future Scaling (When You Hit 1000+ Users)

Consider adding denormalized feed posts:
- `/feed_posts` collection
- Pre-computed feed for faster loading
- Cloud Functions to create feed posts on stamp collection

But DON'T do this now - premature optimization!

