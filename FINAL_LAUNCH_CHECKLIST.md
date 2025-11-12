# Stampbook - Final Pre-Launch Checklist
**Date:** November 10, 2025  
**Current Status:** Almost launch-ready, need to fix 7 critical items

---

## ✅ What You've Done Well

You've built a solid foundation:

**Testing & Quality**
- Created 5 comprehensive unit test files (50+ tests covering distance calculations, invite codes, visibility, country parsing, likes)
- Zero linter errors across the codebase
- No force unwraps or unsafe code patterns
- Clean MVVM architecture with proper separation

**Firebase & Security**
- Security rules are production-ready
- Content moderation Cloud Functions set up
- Invite-only system configured (controls growth)
- Server-side username validation working

**Performance**
- Multi-layer caching (LRU + disk + Firebase)
- Optimistic UI updates for instant feedback
- Offline support with Firebase persistence
- No memory leaks detected

---

## 🚨 7 Critical Items to Fix (4-6 hours total)

### 1. Disable or Fix Share Feature (10 minutes)

**Problem:** App Store URLs are placeholders and will break when users tap share.

**Solution A (Recommended for Beta):** Hide share buttons until you have real App Store URL

```swift
// In StampsView.swift (line ~660)
// Comment out or remove the share button
/*
private func copyAppStoreUrl() {
    // Disabled for beta
}
*/

// In FeedView.swift (line ~981)
// Comment out or remove the share button
/*
private func copyAppStoreUrl() {
    // Disabled for beta
}
*/
```

**Solution B (For TestFlight):** Use TestFlight public link
- After uploading to TestFlight, get public link from App Store Connect
- Replace placeholder URLs with TestFlight link

**Action:** Choose Solution A for now (5 minutes to comment out), fix properly after App Store approval.

---

### 2. Generate Launch Invite Codes (5 minutes)

**Current Status:** Only 1 code exists (`STAMPBOOKBETA` with 0/15 uses)

**Problem:** If that code gets exhausted or leaked, you have no backups.

**Solution:**

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook

# Generate 50 multi-use codes (10 uses each)
node generate_invite_codes.js 50

# Generate 10 single-use codes for VIPs
node generate_invite_codes.js 10 --single-use

# Verify codes created
node check_invite_codes.js
```

**Action:** Run these commands now. Save codes somewhere secure (Notes app, 1Password, etc).

---

### 3. Add Crash Symbolication to Xcode (10 minutes)

**Problem:** Crashlytics is enabled but won't upload debug symbols. Crash reports will be unreadable.

**Solution:**

1. Open `Stampbook.xcodeproj` in Xcode
2. Select "Stampbook" target in left sidebar
3. Go to "Build Phases" tab
4. Click "+" → "New Run Script Phase"
5. Drag it to be AFTER "Compile Sources"
6. Paste this script:

```bash
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

7. Click "Input Files" (+) and add:

```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
```

8. Save (⌘S)

**Action:** Do this before your first TestFlight upload.

---

### 4. Add Performance Monitoring (30 minutes)

**Problem:** No visibility into app performance in production. Can't identify slow screens.

**Solution:** Add performance traces to key screens

**File: `Stampbook/Views/Feed/FeedView.swift`**

Add at top:
```swift
import FirebasePerformance
```

In `.task {}` block where feed loads:
```swift
.task {
    let trace = Performance.startTrace(name: "feed_load")
    defer { trace?.stop() }
    
    await feedManager.loadInitialFeed()
}
```

**File: `Stampbook/Views/Map/MapView.swift`**

Add at top:
```swift
import FirebasePerformance
```

In `.task {}` where stamps load:
```swift
.task {
    let trace = Performance.startTrace(name: "map_load")
    defer { trace?.stop() }
    
    // existing stamp loading code
}
```

**File: `Stampbook/Views/Profile/StampsView.swift`**

Add at top:
```swift
import FirebasePerformance
```

In `.task {}` where profile loads:
```swift
.task {
    let trace = Performance.startTrace(name: "profile_load")
    defer { trace?.stop() }
    
    // existing profile loading code
}
```

**Action:** Add these 3 traces to monitor your critical screens.

---

### 5. Test Stamp Suggestions Feature (15 minutes)

**Problem:** Your review document flags this as potentially broken.

**Test Flow:**

1. Run app on simulator/device
2. Sign in as test user
3. Go to any stamp detail view
4. Tap the three-dot menu
5. Tap "Suggest an edit"
6. Fill out form with test data
7. Submit suggestion
8. Open Firebase Console → Firestore
9. Check `stamp_suggestions` collection
10. Verify you can see the suggestion

**If broken:**

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
firebase deploy --only firestore:rules
```

**Action:** Test this flow today. Your Firestore rules look correct, but verify it works.

---

### 6. Test Feedback System (15 minutes)

**Problem:** Need to verify you can read user feedback.

**Test Flow:**

1. Check if feedback UI exists in your app (Settings → Send Feedback or similar)
2. If not implemented, add a simple feedback submission
3. Test submitting feedback
4. Open Firebase Console → Firestore → `feedback` collection
5. Verify you can see and read the feedback

**Your Firestore rule looks correct:**
```javascript
allow read: if isAdmin();
```

**Action:** Verify feedback collection and reading works. If no feedback UI exists, add basic implementation or document this as post-beta feature.

---

### 7. Run Complete Manual Testing (1-2 hours)

**Use your TESTING_CHECKLIST.md** (`docs/TESTING_CHECKLIST.md`)

**Priority P0 (Must Test):**

1. **Authentication**
   - Sign in with Apple works
   - Profile created correctly
   - Username generated properly
   - Lands on feed after sign-in

2. **Core Stamp Collection**
   - Welcome stamp collects instantly (no location required)
   - Location-based stamps show "too far" when out of range
   - Stamps collect when in range (150m radius)
   - Photos can be added to collection
   - Stats update correctly (stamp count, country count)

3. **Feed Functionality**
   - Feed loads and displays posts
   - Like button works (toggles, count updates)
   - Comments can be added and deleted
   - Pull-to-refresh works
   - "All" vs "Only Yours" tabs work

4. **Profile & Social**
   - Own profile displays correctly
   - Edit profile works (display name, username, bio, avatar)
   - Follow/unfollow works
   - Other user profiles accessible

5. **Offline Behavior**
   - Disconnect WiFi → connection banner appears
   - App still works with cached data
   - Reconnect → banner disappears, data syncs

**Action:** Block out 1-2 hours for thorough testing using both test accounts (hiroo and watagumostudio).

---

## 🟡 Medium Priority (Before External Beta)

### 8. Create App Store Connect Listing (1-2 hours)

You'll need this for TestFlight External Beta:

1. Go to https://appstoreconnect.apple.com
2. Click "My Apps" → "+" → "New App"
3. Fill in:
   - Platform: iOS
   - Name: Stampbook
   - Primary Language: English (U.S.)
   - Bundle ID: (select from dropdown)
   - SKU: `stampbook-ios`
4. Create app

**Assets Needed:**
- App Icon (1024x1024)
- Screenshots (6.7" iPhone 15 Pro Max + 6.5" iPhone 14 Plus)
- App Description
- Keywords
- Privacy Policy URL (need to host your `docs/privacy-policy.html`)
- Support URL or email

**Action:** Do this when ready for TestFlight upload (not blocking for internal testing).

---

### 9. Host Privacy Policy (30 minutes)

**Current:** You have `docs/privacy-policy.html`

**Need:** Public URL for App Store submission

**Quick Solutions:**

**Option A: Firebase Hosting (Recommended)**
```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
firebase init hosting  # Select existing project
# Point to 'docs' directory
cp docs/privacy-policy.html docs/index.html
firebase deploy --only hosting
```

**Option B: GitHub Pages**
1. Create new repo `stampbook-privacy`
2. Upload `privacy-policy.html`
3. Enable GitHub Pages
4. URL: `https://yourusername.github.io/stampbook-privacy/`

**Action:** Do this before App Store submission (not blocking for closed beta).

---

### 10. Add Basic Analytics Events (30 minutes)

Add Firebase Analytics to track key actions:

**In StampsManager.swift (stamp collection):**
```swift
import FirebaseAnalytics

func collectStamp(_ stamp: Stamp) async throws {
    // existing code...
    
    Analytics.logEvent("stamp_collected", parameters: [
        "stamp_id": stamp.id,
        "stamp_name": stamp.name,
        "collection_radius": stamp.collectionRadius
    ])
}
```

**In UserProfileView.swift:**
```swift
import FirebaseAnalytics

.onAppear {
    Analytics.logEvent("profile_viewed", parameters: [
        "user_id": user.id,
        "is_own_profile": user.id == authManager.currentUserId
    ])
}
```

**In FeedManager.swift (post created):**
```swift
Analytics.logEvent("post_created", parameters: [
    "has_photos": !photoUrls.isEmpty,
    "photo_count": photoUrls.count
])
```

**Action:** Nice to have for beta, but not critical. Can add after first beta release.

---

## 🎯 Launch Decision Matrix

### ✅ Ready for CLOSED BETA (10 trusted users)
Check all of these:

- [ ] Fixed/disabled share feature (#1)
- [ ] Generated 50+ invite codes (#2)
- [ ] Added crash symbolication (#3)
- [ ] Added performance traces to 3 key screens (#4)
- [ ] Tested stamp suggestions feature (#5)
- [ ] Tested feedback system (#6)
- [ ] Completed manual testing checklist (#7)
- [ ] App runs without crashes on test device
- [ ] Both test accounts (hiroo, watagumostudio) work properly

**If all checked → READY FOR CLOSED BETA**

Upload to TestFlight Internal Testing and invite 10 friends/family.

---

### ✅ Ready for EXTERNAL BETA (20-50 users)
After 1 week of closed beta with no critical issues:

- [ ] Closed beta completed (1 week, 10 users)
- [ ] Crash-free rate >99% in Firebase Crashlytics
- [ ] No critical bugs reported
- [ ] App Store Connect listing created (#8)
- [ ] Privacy policy hosted publicly (#9)
- [ ] 100+ invite codes available
- [ ] TestFlight External Testing approved by Apple

**If all checked → READY FOR EXTERNAL BETA**

Share TestFlight public link + invite codes with early adopters.

---

### ✅ Ready for PUBLIC LAUNCH (App Store)
After 2-3 weeks of external beta:

- [ ] External beta completed (50+ users)
- [ ] Crash-free rate >99.5%
- [ ] All P0 bugs fixed
- [ ] Positive feedback from beta testers
- [ ] 100+ stamps in database (current: 37)
- [ ] App Store screenshots and description ready
- [ ] Support email/website set up
- [ ] Analytics tracking working
- [ ] Cost monitoring set up (Firebase billing alerts)

**If all checked → READY FOR PUBLIC LAUNCH**

Submit to App Store for review.

---

## ⏱️ Time Breakdown

### Today (2-3 hours)
- Fix share feature (10 min)
- Generate invite codes (5 min)
- Add crash symbolication (10 min)
- Add performance traces (30 min)
- Test stamp suggestions (15 min)
- Test feedback system (15 min)
- Manual testing (1-2 hours)

### This Week
- Create App Store Connect listing (1-2 hours)
- Host privacy policy (30 min)
- Upload first TestFlight build (30 min)
- Recruit 10 closed beta testers

### Next 1-2 Weeks
- Monitor closed beta daily
- Fix any critical bugs
- Collect feedback
- Prepare for external beta

---

## 📱 TestFlight Upload Steps

When you're ready to upload:

1. **In Xcode:**
   - Select "Any iOS Device (arm64)" as destination
   - Product → Archive
   - Wait for archive to complete (5-10 min)
   - Organizer opens automatically

2. **Distribute:**
   - Click "Distribute App"
   - Select "TestFlight & App Store"
   - Click "Next" → "Upload"
   - Wait for upload (5-10 min)

3. **In App Store Connect:**
   - Wait for build to process (20-30 min)
   - Go to TestFlight tab
   - Add build to "Internal Testing" group
   - Add testers (email addresses)
   - Enable "Automatic Distribution"

4. **Testers receive email:**
   - Install TestFlight app from App Store
   - Click link in email
   - Install Stampbook beta

---

## 🔥 Firebase Monitoring Setup

### Daily Checklist During Beta

**Every Morning:**

1. **Firebase Console → Crashlytics**
   - Check crash-free rate (goal: >99%)
   - Review any new crashes
   - Prioritize fixes

2. **Firebase Console → Firestore**
   - Check `users` collection → count new signups
   - Check `stamp_suggestions` → any new suggestions?
   - Check `feedback` → any user feedback?

3. **Firebase Console → Performance**
   - Average app start time (goal: <3s)
   - Feed load time (goal: <2s)
   - Identify slow screens

4. **App Store Connect → TestFlight**
   - How many sessions today?
   - How many active testers?
   - Any crashes reported?

### Set Up Alerts

**Firebase:**
1. Console → Project Settings → Integrations
2. Enable email alerts for crashes (immediate)
3. Enable budget alerts (daily, set to $1/day)

**App Store Connect:**
1. Users & Access → Notifications
2. Enable TestFlight notifications

---

## 🐛 Known Issues to Document for Beta Testers

These are non-critical but good to communicate:

1. **First launch is slow (14-17 seconds)**
   - This is normal Firebase cold start
   - Subsequent launches are <3 seconds

2. **Share app feature disabled**
   - Will be enabled after App Store approval

3. **Limited stamp coverage**
   - Currently 37 stamps in SF Bay Area
   - Goal: 100+ stamps for public launch

4. **No rank system yet**
   - Marked as POST-MVP feature
   - Coming after reaching 100 users

---

## ✅ What You DON'T Need to Fix

These are fine for MVP scale (<100 users):

✅ **Comment privacy** - Current rules are appropriate for small scale
✅ **Rate limiting on Cloud Functions** - Not needed until 500+ users
✅ **Local profile caching** - App is fast enough for MVP
✅ **Widget** - Nice to have, but not critical
✅ **Rank system** - Intentionally disabled for MVP
✅ **About/Business/Creator pages** - Post-MVP features

---

## 🎯 Your Action Plan for Today

**Step 1: Fix Critical Blockers (1 hour)**

1. Comment out share buttons in `StampsView.swift` and `FeedView.swift` (10 min)
2. Run `node generate_invite_codes.js 50` (5 min)
3. Add Crashlytics run script to Xcode Build Phases (10 min)
4. Add 3 performance traces (FeedView, MapView, StampsView) (30 min)
5. Test stamp suggestions feature (15 min)

**Step 2: Complete Testing (1-2 hours)**

6. Run through P0 testing checklist in `docs/TESTING_CHECKLIST.md`
7. Test with both accounts (hiroo and watagumostudio)
8. Document any bugs found

**Step 3: Decision**

**If no critical bugs found:**
- You're ready for closed beta TestFlight upload!
- Create App Store Connect listing tomorrow
- Upload TestFlight build
- Invite 10 trusted testers

**If critical bugs found:**
- Fix blocking bugs first
- Re-test
- Then proceed to closed beta

---

## 📞 Final Thoughts

You've built something solid. Your architecture is clean, your security is tight, and your core features work well. The 7 items above are polish, not fundamental issues.

**My recommendation:**
- Spend 2-3 hours today fixing items #1-7
- Upload to TestFlight Internal Testing tomorrow
- Get 10 trusted users testing this week
- Monitor daily for critical issues
- External beta in 1-2 weeks if all goes well

You're closer than you think. Good luck! 🚀

---

**Created:** November 10, 2025  
**Status:** Ready to execute  
**Time to Closed Beta:** 2-3 hours of focused work

