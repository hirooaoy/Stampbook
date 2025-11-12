# Core Flow Accessibility Plan
**Date:** November 11, 2025  
**Focus:** Make critical user journeys accessible  
**Estimated Time:** 45-60 minutes

---

## 🎯 **Strategy: Core Flows Only**

Instead of adding accessibility everywhere, focus on the 3 critical paths:
1. **Creating Account** - Sign in → Enter invite code → Profile created
2. **Editing Profile** - Edit button → Change info → Save
3. **Collecting Stamp** - Map → Stamp detail → Collect → Success

**Why this approach is smart:**
- ✅ 80/20 rule - these flows = 80% of user actions
- ✅ Fast to implement (1 hour vs 3 hours)
- ✅ High impact for beta testers
- ✅ Can expand to other flows after launch

---

## 📋 **Flow 1: Creating Account** (15 min)

### **User Journey:**
```
App Launch → Sign In Sheet → Enter Invite Code → Profile Created → Feed
```

### **Files to Modify:**
1. `Stampbook/Views/Shared/SignInSheet.swift`
2. `Stampbook/Views/InviteCodeSheet.swift`

---

### **1.1 Sign In Sheet**

**File:** `Stampbook/Views/Shared/SignInSheet.swift`

**Current Status:** ✅ Likely already good (native SignInWithAppleButton)

**Check needed:**
- Sign In with Apple button - Should be accessible by default
- Any custom UI around it

**Changes needed (if any):**

```swift
// If there's a custom close button:
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.accessibilityLabel("Close")

// If there's explanatory text, ensure it's readable:
Text("Sign in to collect stamps")
    .accessibilityAddTraits(.isHeader)  // Makes it a heading for VoiceOver navigation
```

**Testing:**
- [ ] VoiceOver reads "Sign In with Apple, button"
- [ ] Close button (if any) is labeled
- [ ] Can navigate with swipe gestures

**Time:** 5 minutes

---

### **1.2 Invite Code Sheet**

**File:** `Stampbook/Views/InviteCodeSheet.swift`

**Current Status:** 🟡 Needs labels for icon-only buttons

**Changes needed:**

```swift
// TextField should be good, but add accessibility hint:
TextField("Enter invite code", text: $code)
    .accessibilityHint("Six to ten character code provided by Stampbook")

// Continue button - likely already good if using Label
Button(action: { validateCode() }) {
    Text("Continue")
}
// ✅ No changes needed - text is visible

// If there's a close/back button:
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.accessibilityLabel("Cancel")

// If there's a help/info button:
Button(action: { showHelp() }) {
    Image(systemName: "questionmark.circle")
}
.accessibilityLabel("Help")
.accessibilityHint("Learn how to get an invite code")
```

**Testing:**
- [ ] Text field announces what to enter
- [ ] Continue button is clear
- [ ] Error messages are read aloud

**Time:** 5-10 minutes

---

### **1.3 Profile Creation (Automatic)**

**File:** N/A (happens in background)

**Status:** ✅ No accessibility work needed - automatic process

---

## 📋 **Flow 2: Editing Profile** (15 min)

### **User Journey:**
```
Stamps Tab → Edit Profile Button → Change Fields → Save → Back to Profile
```

### **Files to Modify:**
1. `Stampbook/Views/Profile/StampsView.swift` (edit button)
2. `Stampbook/Views/Profile/ProfileEditView.swift` (form fields)

---

### **2.1 Edit Profile Button**

**File:** `Stampbook/Views/Profile/StampsView.swift`

**Current Code (lines ~100-109):**
```swift
Button(action: { showEditProfile = true }) {
    Image(systemName: "pencil.circle")
        .font(.system(size: 24))
        .foregroundColor(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
```

**Better Approach - Use Label:**
```swift
Button(action: { showEditProfile = true }) {
    Label("Edit profile", systemImage: "pencil.circle")
        .labelStyle(.iconOnly)  // Shows only icon visually
}
.frame(width: 44, height: 44)
.contentShape(Rectangle())
// ✅ Automatic accessibility - no manual label needed!
```

**Alternative - Keep icon, add label:**
```swift
Button(action: { showEditProfile = true }) {
    Image(systemName: "pencil.circle")
        .font(.system(size: 24))
        .foregroundColor(.primary)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
}
.accessibilityLabel("Edit profile")
```

**Time:** 2 minutes

---

### **2.2 Profile Edit Form**

**File:** `Stampbook/Views/Profile/ProfileEditView.swift`

**Current Status:** 🟡 Likely mostly good (native TextFields), but check photo picker

**Changes needed:**

```swift
// Profile photo picker button
Button(action: { showPhotoPicker = true }) {
    // ... current photo or placeholder ...
}
.accessibilityLabel("Profile photo")
.accessibilityHint("Double tap to change your profile photo")
.accessibilityAddTraits(.isImage)

// Text fields - likely already good, but add hints:
TextField("Display name", text: $displayName)
    .accessibilityHint("Your name shown to other users")

TextField("Username", text: $username)
    .accessibilityHint("Unique username with letters, numbers, and underscores")

TextField("Bio", text: $bio)
    .accessibilityHint("Optional description about yourself")

// Save button - likely already good if text is visible
Button("Save") { ... }
// ✅ No changes needed

// Cancel button - check if it's icon-only
Button(action: { dismiss() }) {
    Text("Cancel")  // ✅ If text is visible, no changes
}
```

**Testing:**
- [ ] Photo button announces "Profile photo"
- [ ] Text fields announce their purpose
- [ ] Save/Cancel buttons are clear
- [ ] Username validation errors are announced

**Time:** 10 minutes

---

## 📋 **Flow 3: Collecting Stamp** (25 min)

### **User Journey:**
```
Map → Tap Pin → Stamp Detail → Collect Button → Success Animation → Memory Section
```

### **Files to Modify:**
1. `Stampbook/Views/Map/StampPin.swift` (map pins) ⭐ **HIGHEST IMPACT**
2. `Stampbook/Views/Shared/StampDetailView.swift` (collect button)

---

### **3.1 Map Pins** ⭐ **CRITICAL**

**File:** `Stampbook/Views/Map/StampPin.swift`

**Current Code:**
```swift
struct StampPin: View {
    let stamp: Stamp
    let isWithinRange: Bool
    let isCollected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                    .frame(width: 50, height: 50)
                
                Image(systemName: isCollected ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
            
            Triangle()
                .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                .frame(width: 12, height: 8)
        }
    }
}
```

**Better Code with Accessibility:**
```swift
struct StampPin: View {
    let stamp: Stamp
    let isWithinRange: Bool
    let isCollected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                    .frame(width: 50, height: 50)
                
                Image(systemName: isCollected ? "checkmark.seal.fill" : "lock.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
            
            Triangle()
                .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                .frame(width: 12, height: 8)
        }
        .accessibilityElement(children: .ignore)  // Treat entire pin as one element
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view stamp details")
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Accessibility Helper
    
    private var accessibilityLabel: String {
        let statusDescription: String
        
        if isCollected {
            statusDescription = "collected"
        } else if isWithinRange {
            statusDescription = "unlocked, within range"
        } else {
            statusDescription = "locked, too far away"
        }
        
        return "\(stamp.name), \(statusDescription)"
    }
}
```

**VoiceOver will announce:**
- 🔵 "Golden Gate Bridge, unlocked, within range, button. Double tap to view stamp details."
- 🟢 "Alcatraz Island, collected, button. Double tap to view stamp details."
- ⚪ "Palace of Fine Arts, locked, too far away, button. Double tap to view stamp details."

**Time:** 10 minutes

---

### **3.2 Stamp Detail View - Collect Button**

**File:** `Stampbook/Views/Shared/StampDetailView.swift`

**Current Status:** 🟡 Button likely has text, but check context

**Look for the collect button (probably around line 200-300):**

```swift
// If button shows text:
Button("Collect Stamp") {
    collectStamp()
}
// ✅ Already accessible - no changes needed!

// If button is custom or complex:
Button(action: { collectStamp() }) {
    HStack {
        Image(systemName: "checkmark.circle.fill")
        Text("Collect Stamp")
    }
}
// ✅ Already accessible - text is visible

// Add accessibility value to show distance (optional enhancement):
Button("Collect Stamp") {
    collectStamp()
}
.accessibilityValue(isWithinRange ? "Within range" : "Too far, need to be within \(stamp.collectionRadius) meters")
```

**Check "Too far" message:**
```swift
// If there's a disabled state with explanation:
Text("You're too far from this stamp")
    .accessibilityAddTraits(.isStaticText)
// ✅ Already accessible - text is visible
```

**Time:** 5 minutes

---

### **3.3 Collection Success**

**File:** `Stampbook/Views/Shared/StampDetailView.swift`

**Current Status:** 🟡 Check if success animation/message is announced

**After successful collection:**

```swift
// If there's a success message/animation:
Text("Stamp collected!")
    .onAppear {
        // Announce to VoiceOver immediately
        UIAccessibility.post(
            notification: .announcement,
            argument: "Stamp collected! You collected \(stamp.name)"
        )
    }

// If there's a checkmark or confetti animation:
// Make sure it doesn't interfere with the announcement
```

**Memory section that appears:**
```swift
// Photo upload button
Button(action: { showPhotoPicker = true }) {
    Image(systemName: "photo")
}
.accessibilityLabel("Add photo")
.accessibilityHint("Add a photo memory for this stamp")

// Notes button
Button(action: { showNotesEditor = true }) {
    Image(systemName: "note.text")
}
.accessibilityLabel("Add notes")
.accessibilityHint("Write personal notes about this location")
```

**Time:** 10 minutes

---

## 📊 **Implementation Summary**

### **Files to Edit (6 total):**

| File | Changes | Time | Priority |
|------|---------|------|----------|
| `SignInSheet.swift` | Check close button | 5 min | Medium |
| `InviteCodeSheet.swift` | Add labels to icon buttons | 5 min | Medium |
| `StampsView.swift` | Edit profile button | 2 min | High |
| `ProfileEditView.swift` | Photo picker, field hints | 10 min | High |
| `StampPin.swift` | ⭐ Map pin labels | 10 min | **CRITICAL** |
| `StampDetailView.swift` | Collect button, success | 15 min | High |

**Total Time:** 45-60 minutes

---

## ✅ **Implementation Order**

### **Phase 1: Highest Impact (20 min)**
1. ✅ `StampPin.swift` - Map pins (10 min)
   - Most used feature
   - Currently completely inaccessible
   - Easy win

2. ✅ `StampsView.swift` - Edit button (2 min)
   - One-line change
   - Gateway to profile editing

3. ✅ `ProfileEditView.swift` - Photo picker (5 min)
   - Critical for profile customization
   - Currently just an icon

### **Phase 2: Core Functionality (20 min)**
4. ✅ `StampDetailView.swift` - Collect flow (15 min)
   - Main app action
   - Success announcements

5. ✅ `InviteCodeSheet.swift` - Onboarding (5 min)
   - First impression for new users

### **Phase 3: Polish (5 min)**
6. ✅ `SignInSheet.swift` - Check and verify (5 min)
   - Likely already good
   - Quick verification

---

## 🧪 **Testing Plan** (15 min)

### **After Each Phase:**

**Quick Test (5 min per phase):**
1. ✅ Build successful
2. ✅ Navigate to screen
3. ✅ Enable VoiceOver
4. ✅ Tap through flow
5. ✅ Disable VoiceOver

### **Full Test After All Changes (15 min):**

**Flow 1: Account Creation**
- [ ] Open app
- [ ] Enable VoiceOver
- [ ] Tap "Sign In with Apple"
- [ ] Hear "Sign In with Apple, button"
- [ ] Enter invite code
- [ ] Hear field description
- [ ] Tap Continue
- [ ] Profile created

**Flow 2: Edit Profile**
- [ ] Tap Edit Profile button
- [ ] Hear "Edit profile, button"
- [ ] Navigate to photo picker
- [ ] Hear "Profile photo, image, button"
- [ ] Navigate to text fields
- [ ] Hear field hints
- [ ] Save changes

**Flow 3: Collect Stamp**
- [ ] Open Map
- [ ] Swipe to find stamps
- [ ] Tap a stamp pin
- [ ] Hear "Golden Gate Bridge, unlocked, within range, button"
- [ ] Tap to open details
- [ ] Tap Collect Stamp
- [ ] Hear success announcement
- [ ] Verify memory section buttons

---

## 📝 **Code Snippets Ready to Use**

### **1. StampPin.swift - Complete Solution**

```swift
struct StampPin: View {
    let stamp: Stamp
    let isWithinRange: Bool
    let isCollected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Stamp icon
            ZStack {
                Circle()
                    .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                if isCollected {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                } else if isWithinRange {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                }
            }
            
            // Pointer triangle
            Triangle()
                .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                .frame(width: 12, height: 8)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        // MARK: - Accessibility
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view stamp details")
        .accessibilityAddTraits(.isButton)
    }
    
    // MARK: - Accessibility Helper
    
    private var accessibilityLabel: String {
        let status: String
        if isCollected {
            status = "collected"
        } else if isWithinRange {
            status = "unlocked, within range"
        } else {
            status = "locked, too far away"
        }
        return "\(stamp.name), \(status)"
    }
}
```

### **2. StampsView.swift - Edit Button (Option A: Label)**

```swift
// Around line 100-109, replace with:
Button(action: { showEditProfile = true }) {
    Label("Edit profile", systemImage: "pencil.circle")
        .labelStyle(.iconOnly)
}
.frame(width: 44, height: 44)
.contentShape(Rectangle())
.disabled(profileManager.currentUserProfile == nil)
```

### **3. ProfileEditView.swift - Photo Picker**

```swift
// Find the photo picker button and add:
Button(action: { showPhotoPicker = true }) {
    // ... existing photo display ...
}
.accessibilityLabel("Profile photo")
.accessibilityHint("Double tap to change your photo")
.accessibilityAddTraits(.isImage)
```

### **4. StampDetailView.swift - Success Announcement**

```swift
// After stamp collection succeeds:
.onChange(of: isCollected) { wasCollected, nowCollected in
    if nowCollected && !wasCollected {
        // Announce success to VoiceOver
        UIAccessibility.post(
            notification: .announcement,
            argument: "Stamp collected! You collected \(stamp.name)"
        )
    }
}
```

---

## 🎯 **Success Criteria**

### **Core Flows are Accessible When:**

✅ **Account Creation:**
- VoiceOver user can sign in
- VoiceOver user can enter invite code
- All buttons and fields are labeled

✅ **Profile Editing:**
- Edit button clearly labeled
- Photo picker button accessible
- Text fields have helpful descriptions
- Can save changes

✅ **Stamp Collection:**
- Map pins announce stamp name and status ⭐
- Collect button is clear
- Success is announced audibly
- Memory section buttons are labeled

---

## 🚀 **Next Steps**

### **Option A: Do It All Now (45-60 min)**
I implement all 6 files in priority order, you test after

### **Option B: Phase by Phase (30 min + 15 min + 5 min)**
1. Phase 1 (20 min) → you test (5 min)
2. Phase 2 (20 min) → you test (5 min)
3. Phase 3 (5 min) → final test (15 min)

### **Option C: Just Phase 1 (20 min)**
Only do the highest impact changes:
- Map pins ⭐
- Edit button
- Photo picker

Then decide if you want to continue.

---

## 💡 **Recommendation**

**Do Option B - Phase by Phase**

**Why:**
- ✅ You can test and give feedback along the way
- ✅ If we run into issues, we catch them early
- ✅ You understand what's changing
- ✅ Only 10 minutes longer than "all at once"

**After Phase 1, you'll have:**
- ✅ Accessible map pins (biggest win)
- ✅ Edit profile button working
- ✅ Photo picker accessible

That's already 70% of the accessibility value in 20 minutes!

---

## ❓ **What do you think?**

Want to:
1. **Go phase by phase** (recommended)
2. **Do it all at once** (faster but riskier)
3. **Just do Phase 1** (quick win, decide later)
4. **Something else?**

Let me know and I'll start implementing! 🚀

