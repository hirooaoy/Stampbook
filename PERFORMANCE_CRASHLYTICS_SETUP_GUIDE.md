# Firebase Performance & Crashlytics Setup Guide

**Created:** December 22, 2024  
**Status:** Step-by-step guide with troubleshooting

This guide will help you add Firebase Performance monitoring and Crashlytics symbolication to your Stampbook app.

---

## Part 1: Add Firebase Performance Monitoring (20-30 minutes)

### Step 1: Add FirebasePerformance Package in Xcode

1. Open `Stampbook.xcodeproj` in Xcode
2. In the left sidebar, click on the **Stampbook project** (blue icon at top)
3. Select the **Stampbook target** (under TARGETS)
4. Click on **"Frameworks, Libraries, and Embedded Content"** OR the **"General"** tab
5. Scroll down to **"Frameworks, Libraries, and Embedded Content"** section
6. Look for a section that says **"Package Dependencies"** in the Project Navigator
   - OR click on the project (blue icon) → Go to **"Package Dependencies"** tab

7. You should see `firebase-ios-sdk` already listed (you're using Crashlytics)
8. Click the **"+"** button at the bottom or double-click the package
9. In the package products list, find and check **"FirebasePerformance"**
10. Click **"Add"** or **"Update"**

**Troubleshooting:**
- If you don't see a "+" button, the package might be managed differently
- Alternative: Go to File → Add Package Dependencies → Search for existing firebase-ios-sdk
- Make sure you're adding it to the **Stampbook target**, not the test target

---

### Step 2: Import FirebasePerformance in StampbookApp.swift

**File:** `Stampbook/StampbookApp.swift`

Add this import at the top (around line 5):

```swift
import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
import FirebasePerformance  // ← ADD THIS LINE
import UserNotifications
```

**Why?** This makes the Performance API available throughout your app.

---

### Step 3: Add Performance Trace to FeedView

**File:** `Stampbook/Views/Feed/FeedView.swift`

**Step 3.1:** Add import at the top of the file (around line 1-10):

```swift
import FirebasePerformance
```

**Step 3.2:** Find where the feed loads initially. Look for something like:

```swift
.task {
    if authManager.isSignedIn && !hasLoadedInitial {
        await feedManager.loadInitialFeed()
        hasLoadedInitial = true
    }
}
```

**Step 3.3:** Wrap it with performance tracking:

```swift
.task {
    if authManager.isSignedIn && !hasLoadedInitial {
        // Start performance trace
        let trace = Performance.startTrace(name: "feed_load")
        
        await feedManager.loadInitialFeed()
        hasLoadedInitial = true
        
        // Stop trace
        trace?.stop()
    }
}
```

**Troubleshooting:**
- If you can't find `.task`, look for `.onAppear` instead
- If the code looks different, just add the trace around the main feed loading function
- The trace name can be anything (lowercase with underscores is convention)

---

### Step 4: Add Performance Trace to MapView

**File:** `Stampbook/Views/Map/MapView.swift`

**Step 4.1:** Add import at the top:

```swift
import FirebasePerformance
```

**Step 4.2:** Find where stamps are loaded. Look for something like:

```swift
.task {
    await stampsManager.loadStamps()
}
```

OR

```swift
.onAppear {
    Task {
        await stampsManager.loadStamps()
    }
}
```

**Step 4.3:** Wrap with performance tracking:

```swift
.task {
    let trace = Performance.startTrace(name: "map_load")
    defer { trace?.stop() }  // ← This automatically calls stop when function exits
    
    await stampsManager.loadStamps()
}
```

**Why `defer`?** It ensures the trace stops even if there's an error or early return.

---

### Step 5: Add Performance Trace to Profile/StampsView

**File:** `Stampbook/Views/Profile/StampsView.swift`

**Step 5.1:** Add import at the top:

```swift
import FirebasePerformance
```

**Step 5.2:** Find where the profile loads. Look for something like:

```swift
.task {
    await loadUserProfile()
}
```

OR inside a function that loads the profile data.

**Step 5.3:** Wrap with performance tracking:

```swift
.task {
    let trace = Performance.startTrace(name: "profile_load")
    defer { trace?.stop() }
    
    await loadUserProfile()
}
```

---

### Step 6: Build and Test Performance Monitoring

1. **Build the app:** ⌘B (Command + B)
2. **Fix any compiler errors:**
   - Common error: "Cannot find 'Performance' in scope"
     - Solution: Make sure you added FirebasePerformance package AND imported it
   - Common error: "Ambiguous reference to member 'stop'"
     - Solution: Use `trace?.stop()` instead of `trace.stop()`

3. **Run the app** on simulator or device
4. Navigate to each screen (Feed, Map, Profile)
5. Wait 5-10 minutes for data to upload

6. **Check Firebase Console:**
   - Go to: https://console.firebase.google.com/project/stampbook-app/performance
   - Click on "Dashboard" tab
   - Wait 10-20 minutes for first data to appear
   - You should see traces: `feed_load`, `map_load`, `profile_load`

**Troubleshooting:**
- Data takes 10-30 minutes to appear in Firebase Console (be patient!)
- Performance only works on real devices or Debug builds on simulator
- If no data appears after 1 hour, check Firebase Console → DebugView

---

## Part 2: Add Crashlytics Symbolication (10 minutes)

This ensures crash reports show readable file names and line numbers instead of memory addresses.

### Step 1: Add Crashlytics Upload Script to Xcode

1. Open `Stampbook.xcodeproj` in Xcode
2. In the left sidebar, click on the **Stampbook project** (blue icon at top)
3. Select the **Stampbook target** (under TARGETS)
4. Click on the **"Build Phases"** tab
5. Click the **"+"** button in the top-left of the Build Phases section
6. Select **"New Run Script Phase"**

7. A new section appears called "Run Script" at the bottom
8. **IMPORTANT:** Drag this "Run Script" phase to be **AFTER** "Compile Sources"
   - It should be somewhere around position 5-7 in the list
   - Order matters! If it's before compilation, it won't work

9. Expand the "Run Script" section (click the disclosure triangle)
10. In the script text box, paste this:

```bash
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

11. **Optional but recommended:** Check the box that says "Run script only when installing"
    - This makes builds faster during development
    - Symbols will still upload for release builds

12. Expand **"Input Files"** section (click the "+" under Input Files)
13. Click the **"+"** button and add these two lines:

```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}
```

```
${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
```

14. **Save:** Press ⌘S (Command + S)

---

### Step 2: Verify the Script Path

The script path might be different depending on your Xcode setup. Let's check:

**Option A:** Run this command in Terminal to find the correct path:

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
find ~/Library/Developer/Xcode/DerivedData -name "run" -path "*/firebase-ios-sdk/Crashlytics/run" 2>/dev/null | head -1
```

If this finds a path, use that path instead of the one above.

**Option B:** Check if using Swift Package Manager (you are), the path should be:

```bash
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

This is the correct path for Swift Package Manager (which you're using).

---

### Step 3: Test Crashlytics Symbolication

You can't fully test this until you do a TestFlight or App Store build, but you can verify the script runs:

1. **Clean build folder:** Shift + ⌘K (Shift + Command + K)
2. **Archive the app:** Product → Archive
   - Select "Any iOS Device (arm64)" as the destination first
   - Wait for archive to complete (5-10 minutes)

3. **Check the build logs:**
   - While archiving, open the Report Navigator (⌘9 - Command + 9)
   - Click on the latest build
   - Search for "Crashlytics" in the log
   - You should see output like: "Validating and submitting dSYM to Crashlytics"

4. **If you see errors:**
   - "No such file or directory" → Script path is wrong, try Option A above
   - "Permission denied" → Run `chmod +x` on the script path
   - "dSYM not found" → This is okay for Debug builds, only matters for Release

---

### Step 4: Verify in Firebase Console (After TestFlight Upload)

Once you upload to TestFlight and get a crash:

1. Go to: https://console.firebase.google.com/project/stampbook-app/crashlytics
2. Click on a crash report
3. You should see readable stack traces like:

```
StampbookApp.swift line 45
FeedView.swift line 123
```

Instead of:

```
0x00000001a234f890
0x00000001a234f8a4
```

---

## Common Issues & Solutions

### Issue 1: "Cannot find 'Performance' in scope"

**Solution:**
1. Make sure you added the FirebasePerformance package in Xcode
2. Check you imported it: `import FirebasePerformance`
3. Clean build folder (Shift + ⌘K) and rebuild

---

### Issue 2: "No such file or directory" for Crashlytics script

**Solution:**
1. Check the script path is correct for Swift Package Manager
2. Try this alternate path:

```bash
"${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}/FirebaseCrashlytics.framework/run"
```

3. Or use absolute path from your DerivedData folder (use find command above)

---

### Issue 3: Performance data not showing in Firebase Console

**Solution:**
1. Wait 30 minutes (seriously, it's slow)
2. Make sure you're testing on a real device or Debug build
3. Check Firebase Console → Performance → DebugView for real-time data
4. Verify Performance is enabled in Firebase Console → Settings → Integrations

---

### Issue 4: Script slows down builds

**Solution:**
1. Check "Run script only when installing" option
2. This only runs for Archive builds, not regular Debug builds
3. Makes development faster

---

## What Problems Did You Hit Last Time?

Let me know what went wrong before and I can add specific troubleshooting for that issue:

1. Did the FirebasePerformance package not install?
2. Did the Crashlytics script give an error?
3. Did the build fail with a compiler error?
4. Did you not see any data in Firebase Console?

Tell me what happened and I'll help you fix it specifically!

---

## Quick Verification Checklist

Before you start, verify these are working:

- [ ] App builds and runs successfully now
- [ ] You can open Xcode and see the project
- [ ] Firebase SDK is already working (Crashlytics logs crashes)
- [ ] You have internet connection (needed to download package)
- [ ] You're on the latest Xcode version (or at least Xcode 14+)

After completing:

- [ ] FirebasePerformance package added to target
- [ ] Import statements added to 4 files (StampbookApp, FeedView, MapView, StampsView)
- [ ] Performance traces added to 3 views
- [ ] App builds without errors
- [ ] Crashlytics run script added to Build Phases
- [ ] Input files added to run script
- [ ] Archive completes without errors

---

**Questions?** Let me know what step you're stuck on and I'll help debug it with you!





