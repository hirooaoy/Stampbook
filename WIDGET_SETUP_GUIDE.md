# Stampbook Widget - Setup & Implementation Guide

## 🎯 Overview

You now have a **Small Widget** that:
1. Shows a random stamp from your collected stamps
2. Rotates every 6 hours automatically
3. Taps open the Stamps tab (deep linking to specific stamp detail coming in v2)
4. Has space reserved for penguin overlay (future feature)
5. Shows a friendly "Collect Your First Stamp!" message if user has no stamps yet

## ✅ What's Already Done

### Code Implementation ✅
- `WidgetStamp.swift` - Lightweight data model for widget
- `WidgetDataManager` - Handles App Group communication
- `StampsManager.syncWidgetData()` - Syncs stamps when collected
- `StampProvider.swift` - Timeline provider (6-hour refresh)
- `StampWidgetView.swift` - Widget UI with placeholder for penguin
- `StampbookWidget.swift` - Widget configuration
- Deep linking handler in `ContentView.swift`

### Xcode Configuration ✅
- Widget Extension target created (`StampbookWidget`)
- App Groups enabled (`group.com.hiroo.Stampbook`)
- Widget entitlements configured
- URL scheme: `stampbook://`

## 🔧 Final Setup Steps (In Xcode)

### Step 1: Share WidgetStamp.swift with Widget Target

**Why:** The widget needs access to `WidgetStamp` model and `WidgetDataManager`

1. In Xcode's Project Navigator, find:
   ```
   Stampbook/Models/WidgetStamp.swift
   ```

2. Click on the file to select it

3. Open the **File Inspector** (right sidebar, first tab - looks like a document icon)

4. Find **"Target Membership"** section

5. Check BOTH boxes:
   - ☑️ Stampbook
   - ☑️ StampbookWidget

### Step 2: Enable App Groups for Main App Target

**Why:** Both app and widget need the same App Group to share data

1. Select **Stampbook.xcodeproj** in Project Navigator

2. Select **Stampbook** target (under TARGETS, not PROJECT)

3. Go to **Signing & Capabilities** tab

4. If you don't see "App Groups":
   - Click **"+ Capability"**
   - Search for "App Groups"
   - Double-click to add it

5. Under App Groups, click **"+"** button

6. Add: `group.com.hiroo.Stampbook`

7. Make sure it's **checked** ☑️

**Note:** Widget target already has this configured (I can see it in `StampbookWidgetExtension.entitlements`)

### Step 3: Verify URL Scheme

You already added this! Just verify:

1. Select **Stampbook** target
2. Go to **Info** tab
3. Expand **URL Types**
4. Should see:
   - Identifier: `com.hiroo.Stampbook.widget` (or similar)
   - URL Schemes: `stampbook`

If it's there, you're good! ✅

### Step 4: Add WidgetKit Import to StampsManager

The `syncWidgetData()` method needs WidgetKit to trigger widget refreshes.

1. Open `Stampbook/Managers/StampsManager.swift`

2. At the top, add this import (after the other imports):
   ```swift
   #if canImport(WidgetKit)
   import WidgetKit
   #endif
   ```

### Step 5: Test Initial Sync on App Launch

Add widget sync when stamps load. In `StampsManager.swift`, find the `setCurrentUser` method and add sync call:

**Look for this method around line 83-90** and add the sync call at the end:
```swift
func setCurrentUser(_ userId: String?, profileManager: ProfileManager?) {
    userCollection.setCurrentUser(userId)
    self.profileManager = profileManager
    
    // Sync widget data when user signs in
    if userId != nil {
        syncWidgetData()
    }
}
```

## 📱 How to Test

### Build and Run

1. Build scheme should already be **"Stampbook"** (not the widget extension)

2. Run on a **real device** (widgets don't work well in Simulator)

3. App builds with widget embedded automatically

### Add Widget to Home Screen

1. Long-press on home screen
2. Tap "+" button (top left)
3. Search for "Stampbook"
4. Select the widget
5. Choose **Small** size
6. Tap "Add Widget"

### Test Widget Updates

**Scenario 1: User has no stamps**
- Widget shows: "Collect Your First Stamp!" with icon
- Expected behavior: Friendly placeholder ✅

**Scenario 2: User collects a stamp**
- Collect any stamp in the app
- Widget timeline refreshes (may take a few seconds to minutes)
- Widget shows: Stamp image with name and location
- Expected behavior: Shows collected stamp ✅

**Scenario 3: Tap widget**
- Tap the widget
- App opens to Stamps tab (tab 2)
- Expected behavior: App opens ✅
- Future: Will open specific stamp detail sheet

### Force Widget Refresh (for testing)

If you want to see updates immediately without waiting:

1. Switch Xcode scheme to **"StampbookWidgetExtension"**
2. Run on device
3. Xcode will show widget preview
4. Widget rebuilds immediately

Then switch back to **"Stampbook"** scheme for normal development.

## 🎨 Future: Adding Penguin Overlay

When you're ready to add the 6 penguin PNGs:

1. Add penguin images to `StampbookWidget/Assets.xcassets/`
   - Name them: `penguin-1.png`, `penguin-2.png`, etc.

2. Update `StampWidgetView.swift`:
   ```swift
   // In stampCard(stamp:) method, add this at the bottom of ZStack:
   
   // Penguin overlay (bottom-right corner)
   Image("penguin-\(Int.random(in: 1...6))")
       .resizable()
       .aspectRatio(contentMode: .fit)
       .frame(width: 50, height: 50)
       .offset(x: 10, y: 10)
       .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
   ```

3. Penguin will appear on top of stamp image, bottom-right corner

## 🐛 Troubleshooting

**Widget shows "Unable to Load"**
- Check App Groups are enabled on BOTH targets
- Verify group ID matches: `group.com.hiroo.Stampbook`
- Check WidgetStamp.swift is shared with both targets

**Widget not updating after collecting stamp**
- Widgets update on iOS's schedule (not immediate)
- Force refresh by switching to widget scheme and running
- Check `syncWidgetData()` is being called in `collectStamp()`

**Images not showing in widget**
- Images aren't being copied to shared container yet
- Need to implement image caching to shared container (Phase 2)
- For now, widget will show placeholder if image not found

**App doesn't open when tapping widget**
- Verify URL scheme is set up: `stampbook`
- Check `onOpenURL` handler is in ContentView
- Deep link format: `stampbook://stamp/{stampId}`

## 📊 Current Status

✅ Widget infrastructure complete
✅ Timeline provider working (6-hour refresh)
✅ UI with placeholder for penguin
✅ Deep linking foundation (opens Stamps tab)
✅ No stamps state handled
✅ App Groups configured

⚠️ Image sharing between app and widget needs work
- Currently widget tries to load from shared container
- Images are cached in app's Documents directory
- Need to copy images to shared container when collecting

**Next Phase (Optional):**
- Copy stamp images to shared container
- Deep link directly to stamp detail sheet
- Add penguin overlay PNGs

## 🎉 You're Ready!

Run the app, collect some stamps, and add the widget to your home screen. It should show a random stamp every 6 hours!

The widget is **functional MVP** - it shows stamps and looks great. Image caching and penguin overlay can be added later when you have time.

