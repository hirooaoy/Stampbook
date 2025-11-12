# Stampbook Launch Action Plan
**Goal:** Get to Closed Beta Launch in 4-6 hours

---

## 🚀 QUICK START: Fix Critical Blockers (2 hours)

### Task 1: Fix App Store Share URLs (10 minutes)

**Option A: Use TestFlight Link (Recommended for Beta)**
```swift
// In StampsView.swift (line 320-323) and FeedView.swift (line 317-320)
// Replace with your TestFlight public link
let testFlightURL = "https://testflight.apple.com/join/YOUR_CODE_HERE"
```

**Option B: Disable Share During Beta**
```swift
// Comment out or remove the share button
// .toolbar { 
//     ToolbarItem(placement: .navigationBarTrailing) {
//         shareButton
//     }
// }
```

**Files to update:**
- `Stampbook/Views/Profile/StampsView.swift` (line 320-323)
- `Stampbook/Views/Feed/FeedView.swift` (line 317-320)

---

### Task 2: Test Stamp Suggestions Feature (15 minutes)

**Test the flow:**
1. Open app on your device/simulator
2. Go to a stamp detail view
3. Tap the menu (three dots)
4. Select "Suggest an edit"
5. Fill out the form and submit
6. Check Firebase Console → Firestore → `stamp_suggestions` collection
7. Verify you can see the suggestion

**If broken:**
```bash
# Redeploy Firestore rules
cd /Users/haoyama/Desktop/Developer/Stampbook
firebase deploy --only firestore:rules
```

**If still broken, check rule at `firestore.rules:154-169`**

---

### Task 3: Generate Launch Invite Codes (5 minutes)

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook

# Generate 50 multi-use codes for beta testers
node generate_invite_codes.js 50

# Generate 10 single-use codes for VIPs/press
node generate_invite_codes.js 10 --single

# Verify codes created
node check_invite_codes.js
```

**Save codes securely** - you'll share these with beta testers.

---

### Task 4: Add Crash Symbolication (10 minutes)

**In Xcode:**
1. Select "Stampbook" project in left sidebar
2. Select "Stampbook" target
3. Go to "Build Phases" tab
4. Click "+" → "New Run Script Phase"
5. Move it AFTER "Compile Sources"
6. Paste this script:
```bash
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```
7. Under "Input Files", add:
```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
```
8. Save and close

---

### Task 5: Test Feedback System (15 minutes)

**Test the flow:**
1. Open app
2. Go to Settings/Menu
3. Find "Send Feedback" (check if this exists in your UI)
4. Submit test feedback
5. Open Firebase Console → Firestore → `feedback` collection
6. Verify you can see and read the feedback

**If you can't read feedback:**
Check `firestore.rules:135-152` - should have `allow read: if isAdmin()`

---

## ⚡ HIGH PRIORITY: Add Monitoring (1 hour)

### Task 6: Add Performance Traces (30 minutes)

**Step 1: Import Performance in key files**
```swift
import FirebasePerformance
```

**Step 2: Add traces to critical screens**

**In FeedView.swift:**
```swift
.onAppear {
    Task {
        let trace = Performance.startTrace(name: "feed_load")
        defer { trace?.stop() }
        
        await feedManager.loadInitialFeed()
    }
}
```

**In MapView.swift:**
```swift
.onAppear {
    let trace = Performance.startTrace(name: "map_load")
    defer { trace?.stop() }
    
    // existing map loading code
}
```

**In StampsView.swift (Profile):**
```swift
.onAppear {
    let trace = Performance.startTrace(name: "profile_load")
    defer { trace?.stop() }
    
    // existing profile loading code
}
```

**Files to update:**
- `Stampbook/Views/Feed/FeedView.swift`
- `Stampbook/Views/Map/MapView.swift`
- `Stampbook/Views/Profile/StampsView.swift`

---

### Task 7: Add Key Analytics Events (30 minutes)

**Import FirebaseAnalytics:**
```swift
import FirebaseAnalytics
```

**Track key events:**

**Stamp Collection (in StampsManager.swift):**
```swift
func collectStamp(_ stamp: Stamp) async throws {
    // existing code...
    
    Analytics.logEvent("stamp_collected", parameters: [
        "stamp_id": stamp.id,
        "stamp_name": stamp.name,
        "distance": distance
    ])
}
```

**Profile Viewed (in UserProfileView.swift):**
```swift
.onAppear {
    Analytics.logEvent("profile_viewed", parameters: [
        "user_id": user.id,
        "is_own_profile": user.id == currentUserId
    ])
}
```

**Post Created (in FeedManager or relevant location):**
```swift
Analytics.logEvent("post_created", parameters: [
    "has_photos": !photoUrls.isEmpty,
    "photo_count": photoUrls.count
])
```

---

## 🧪 TESTING CHECKLIST (1-2 hours)

### Critical User Flows to Test

#### ✅ Onboarding & Auth
- [ ] Enter invite code `STAMPBOOKBETA`
- [ ] Sign in with Apple
- [ ] Profile created with random username
- [ ] Lands on feed or map

#### ✅ Stamp Collection
- [ ] View stamp on map
- [ ] Tap stamp to see details
- [ ] Collect stamp (if in range, or test with Welcome stamp)
- [ ] Add photo to collection
- [ ] Photo appears in collection

#### ✅ Feed & Social
- [ ] View feed (both All and Only Yours tabs)
- [ ] Like a post
- [ ] Comment on a post
- [ ] Delete own comment
- [ ] Search for user
- [ ] Follow another user
- [ ] View another user's profile

#### ✅ Profile
- [ ] Edit profile (display name, bio)
- [ ] Change profile picture
- [ ] View collected stamps
- [ ] View collections progress

#### ✅ Error Handling
- [ ] Turn off WiFi → See connection banner
- [ ] Turn on WiFi → Banner disappears
- [ ] Try invalid username in profile edit
- [ ] Try invalid invite code

#### ✅ Performance
- [ ] App launches in <3 seconds (after first launch)
- [ ] Feed loads smoothly
- [ ] Images load progressively
- [ ] No crashes or freezes

---

## 📱 TESTFLIGHT SETUP (30 minutes)

### Step 1: Create App in App Store Connect
1. Go to https://appstoreconnect.apple.com
2. Click "My Apps" → "+" → "New App"
3. Fill in:
   - **Platform:** iOS
   - **Name:** Stampbook
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** Select your bundle ID from dropdown
   - **SKU:** `stampbook-ios` (or any unique identifier)
4. Click "Create"

### Step 2: Prepare Build for Upload
1. In Xcode, select "Any iOS Device (arm64)"
2. Product → Archive
3. Wait for build to complete
4. When Organizer opens, click "Distribute App"
5. Select "TestFlight & App Store"
6. Click "Next" → "Upload"
7. Wait for upload (5-10 minutes)

### Step 3: Setup Internal Testing
1. Go back to App Store Connect
2. Click your app → TestFlight tab
3. Under "Internal Testing", click "+"
4. Create group: "Closed Beta Testers"
5. Add yourself and other internal testers
6. Enable "Automatic Distribution" for new builds

### Step 4: Get TestFlight Link
1. Wait for build to process (20-30 minutes)
2. Once ready, go to TestFlight tab
3. Copy the public link for your test group
4. Use this link in the share URLs (Task 1)

---

## 👥 RECRUIT BETA TESTERS (Variable time)

### Who to Recruit (10-15 people)

**Technical Users (2-3 people):**
- Developer friends
- Early adopter types
- Will find edge cases and technical issues

**Non-Technical Users (5-7 people):**
- Friends, family, colleagues
- Average iOS users
- Will test if UX is intuitive

**Target Demographic (2-3 people):**
- SF Bay Area residents (or wherever your stamps are)
- People who like exploring/traveling
- Social media users (understand feeds/likes)

### What to Send Them

**Email Template:**
```
Subject: Join Stampbook Closed Beta 🗺️

Hey [Name]!

I'm launching a new app called Stampbook—it's like Pokémon Go meets Instagram for real-world locations. 

I'd love your help testing it before the public launch. 

Here's how to join:
1. Download TestFlight (Apple's beta testing app): [TestFlight Link]
2. Install Stampbook through TestFlight
3. Use invite code: [CODE]
4. Sign in and start collecting stamps!

It's early, so expect some bugs. I'd appreciate any feedback:
- What's confusing?
- What doesn't work?
- What do you love?

Reply to this email or DM me anytime with feedback.

Thanks!
[Your name]
```

---

## 📊 MONITORING SETUP (15 minutes)

### Daily Checklist for Beta Period

**Every Morning:**
1. Open Firebase Console → Crashlytics
   - Check crash-free rate (should be >99%)
   - Review any new crashes

2. Open Firebase Console → Firestore
   - Check `users` collection → count new signups
   - Check `stamp_suggestions` → any new suggestions?
   - Check `feedback` → any new feedback?

3. Open Firebase Console → Performance
   - Check average app start time
   - Check feed load time
   - Identify slow screens

**Every Evening:**
4. Check TestFlight → Analytics
   - How many sessions today?
   - How many testers active?
   - Any crashes reported?

### Set Up Alerts

**Firebase Console:**
1. Go to Firebase Console → Integrations
2. Enable email alerts for:
   - New crashes (immediate)
   - Performance degradation (daily)
   - Budget alerts (daily)

**App Store Connect:**
1. Go to App Store Connect → Users & Access → Notifications
2. Enable TestFlight notifications

---

## 📝 DOCUMENTATION FOR TESTERS

### Create a Quick Start Guide

**"welcome.md" to send to testers:**
```markdown
# Welcome to Stampbook Beta!

## What is Stampbook?
A location-based stamp collecting app. Discover stamps around SF Bay Area, collect them when you visit, share your adventures with friends.

## How to Get Started
1. Allow location permissions (we only use it while app is open)
2. Explore the map to see nearby stamps
3. Tap a stamp to learn more
4. Visit the location and collect your first stamp!

## Known Issues
- First launch takes 15 seconds (loading data)
- Limited stamps (37 in SF Bay Area for now)
- Share feature disabled during beta

## How to Report Issues
- Tap Profile → Menu → Send Feedback
- Or email: watagumo.studio@gmail.com
- Include: what you did, what happened, what you expected

## Privacy
- Your location is only used when app is open
- We don't sell your data
- Full privacy policy: [URL]

Thanks for testing! 🙏
```

---

## ⏱️ TIMELINE SUMMARY

### Today (2 hours)
- [ ] Fix critical blockers (Tasks 1-5)
- [ ] Test core flows manually

### Tomorrow (2 hours)
- [ ] Add monitoring (Tasks 6-7)
- [ ] Set up TestFlight
- [ ] Upload first build

### This Week (Variable)
- [ ] Recruit 10-15 beta testers
- [ ] Send out invites
- [ ] Monitor daily
- [ ] Fix any critical bugs

### Next Week
- [ ] Collect feedback
- [ ] Iterate based on feedback
- [ ] Prepare for wider beta

---

## 🎯 DEFINITION OF DONE

**Closed Beta Ready:**
- [x] All critical blockers fixed (Tasks 1-5)
- [x] Monitoring set up (Tasks 6-7)
- [x] TestFlight build uploaded
- [x] 10+ invite codes generated
- [x] 10-15 testers recruited
- [x] Welcome guide sent to testers
- [x] Daily monitoring routine established

**When you check all boxes above → LAUNCH CLOSED BETA** 🚀

---

## 💬 QUESTIONS?

**If you get stuck:**
1. Check Firebase Console for errors
2. Check Xcode console for crash logs
3. Re-read the relevant docs:
   - `docs/TESTING_CHECKLIST.md`
   - `docs/INVITE_CODE_SYSTEM.md`
   - `docs/CONTENT_MODERATION_SETUP.md`

**Need help?**
- Firebase docs: https://firebase.google.com/docs
- TestFlight guide: https://developer.apple.com/testflight/

---

**Created:** November 10, 2025  
**Est. Time to Complete:** 4-6 hours  
**Next Milestone:** Closed Beta Launch

Good luck! 🚀

