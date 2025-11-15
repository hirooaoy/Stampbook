# Personal Invite Code System - Implementation Plan

**Created:** November 14, 2024  
**Status:** Ready to implement  
**Goal:** Enable each user to invite 5 people using one personal code

---

## 🎯 Executive Summary

Build a personal invite system where each user gets **one random 8-character code** that can be used **5 times**. The code generates when they first tap an invite icon on their profile screen. This enables controlled viral growth from 2 users → 100 users → 1000 users.

---

## 📋 Design Decisions (LOCKED)

### Code Format
- **Pure random**: `K8X2YZ7M` (8 uppercase characters)
- **No username prefix** (avoids edge cases, cleaner sharing)
- **Immutable** (never changes, even if username changes)
- **Excludes confusing characters**: 0, O, 1, I, L

### Generation Strategy
- **Lazy generation**: Code creates on first tap, not at signup
- **Why**: Saves database writes for users who never invite
- **Only engaged users generate codes**

### UI/UX
- **Location**: Top right of StampView (profile screen)
- **Icon**: SF Symbol `person.badge.plus`
- **No badge count**: Clean icon, no pressure/noise
- **Simple sheet**: Code, copy button, share button, usage counter

### Privacy
- **Show usage count only**: "3 of 5 invites used"
- **Don't show usernames** of people who joined
- **Reduces social pressure and privacy concerns**

### Share Message
```
Join me on Stampbook! 🗺️

Use my code: K8X2YZ7M

TestFlight: https://testflight.apple.com/join/rdfyeZnH
```

---

## 🏗️ Technical Architecture

### Firestore Data Structure

**Collection**: `invite_codes`  
**Document ID**: The code itself (e.g., `K8X2YZ7M`)

```javascript
{
  code: "K8X2YZ7M",              // The invite code
  type: "personal",               // Type of code
  createdBy: "userId_123",        // User who owns this code
  createdByUsername: "hiroo",     // For reference (not used in code)
  maxUses: 5,                     // Fixed at 5 for personal codes
  usedCount: 0,                   // Increments with each redemption
  usedBy: [],                     // Array of userIds who redeemed
  createdAt: Timestamp,           // Server timestamp
  expiresAt: null,                // No expiration for MVP
  status: "active"                // active | exhausted
}
```

### User Profile Addition

Add to existing user profile document:

```javascript
{
  // ... existing fields ...
  personalInviteCode: "K8X2YZ7M",  // Their code (null if not generated yet)
  invitedBy: "userId_456",         // Who invited them (from existing system)
  inviteCodeUsed: "ABCD5678"       // Code they used to join (existing)
}
```

---

## 🛠️ Implementation Steps

### Step 1: Update Firestore Rules

**File**: `firestore.rules`

Add rules to allow users to create their personal codes:

```javascript
match /invite_codes/{code} {
  // Existing read rule (already there)
  allow read: if request.auth != null;
  
  // NEW: Allow users to create their personal code
  allow create: if request.auth != null 
    && request.resource.data.createdBy == request.auth.uid
    && request.resource.data.type == "personal"
    && request.resource.data.maxUses == 5;
  
  // Existing update rule (for incrementing usedCount - already there)
  allow update: if request.auth != null 
    && resource.data.usedCount < resource.data.maxUses;
}
```

**Action**: Deploy rules after updating
```bash
firebase deploy --only firestore:rules
```

---

### Step 2: Extend InviteManager.swift

**File**: `Stampbook/Managers/InviteManager.swift`

Add these functions to the existing `InviteManager` class:

```swift
// MARK: - Personal Invite Codes

/// Generate a random 8-character code (no confusing characters)
private func generateRandomCode() -> String {
    let chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    return String((0..<8).map { _ in chars.randomElement()! })
}

/// Check if user already has a personal code
func getUserPersonalCode(userId: String) async -> String? {
    Logger.debug("Checking if user \(userId) has personal code")
    
    // Check user profile first (cached)
    let userRef = db.collection("users").document(userId)
    guard let userData = try? await userRef.getDocument().data(),
          let code = userData["personalInviteCode"] as? String else {
        return nil
    }
    
    Logger.success("User has existing code: \(code)")
    return code
}

/// Generate personal invite code for user
func generatePersonalCode(userId: String, username: String) async throws -> String {
    Logger.info("Generating personal code for \(username) (\(userId))")
    
    // Check if user already has a code
    if let existingCode = await getUserPersonalCode(userId: userId) {
        Logger.warning("User already has code: \(existingCode)")
        return existingCode
    }
    
    // Generate unique code (check for collisions)
    var code = generateRandomCode()
    var attempts = 0
    
    while attempts < 10 {
        let codeRef = db.collection("invite_codes").document(code)
        let codeDoc = try await codeRef.getDocument()
        
        if !codeDoc.exists {
            // Code is unique, use it
            break
        }
        
        // Collision detected, regenerate
        Logger.warning("Code collision detected: \(code), regenerating...")
        code = generateRandomCode()
        attempts += 1
    }
    
    if attempts >= 10 {
        throw InviteError.codeGenerationFailed
    }
    
    Logger.debug("Generated unique code: \(code)")
    
    // Create the invite code document
    let codeRef = db.collection("invite_codes").document(code)
    try await codeRef.setData([
        "code": code,
        "type": "personal",
        "createdBy": userId,
        "createdByUsername": username,
        "maxUses": 5,
        "usedCount": 0,
        "usedBy": [],
        "createdAt": FieldValue.serverTimestamp(),
        "expiresAt": NSNull(),
        "status": "active"
    ])
    
    Logger.debug("Created invite code document")
    
    // Update user profile with their code
    let userRef = db.collection("users").document(userId)
    try await userRef.updateData([
        "personalInviteCode": code
    ])
    
    Logger.success("Personal code \(code) generated and saved for \(username)")
    return code
}

/// Get usage stats for a personal code
func getCodeUsageStats(code: String) async throws -> (used: Int, max: Int, status: String) {
    Logger.debug("Fetching usage stats for code: \(code)")
    
    let codeRef = db.collection("invite_codes").document(code)
    let codeDoc = try await codeRef.getDocument()
    
    guard codeDoc.exists,
          let data = codeDoc.data(),
          let usedCount = data["usedCount"] as? Int,
          let maxUses = data["maxUses"] as? Int,
          let status = data["status"] as? String else {
        throw InviteError.codeNotFound
    }
    
    return (used: usedCount, max: maxUses, status: status)
}
```

**Add to InviteError enum** (if not already there):
```swift
enum InviteError: LocalizedError {
    // ... existing cases ...
    case codeGenerationFailed
    
    var errorDescription: String? {
        switch self {
        // ... existing cases ...
        case .codeGenerationFailed:
            return "Failed to generate invite code. Please try again."
        }
    }
}
```

---

### Step 3: Create PersonalInviteSheet.swift

**New File**: `Stampbook/Views/PersonalInviteSheet.swift`

```swift
import SwiftUI

/// Sheet that displays user's personal invite code and sharing options
struct PersonalInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inviteManager = InviteManager()
    
    let userId: String
    let username: String
    
    // State
    @State private var code: String?
    @State private var usedCount: Int = 0
    @State private var maxUses: Int = 5
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showCopiedFeedback: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isLoading {
                    loadingView
                } else if let code = code {
                    codeView(code: code)
                } else {
                    errorView
                }
            }
            .padding()
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("Try Again") {
                    Task {
                        await loadOrGenerateCode()
                    }
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
        .task {
            await loadOrGenerateCode()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Generating your code...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Code View
    
    private func codeView(code: String) -> some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Share Stampbook with up to 5 friends")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            // Code Display
            VStack(spacing: 12) {
                Text("Your Code")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                    
                    Text(code)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.primary)
                }
                .frame(height: 80)
                .overlay {
                    if showCopiedFeedback {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                            .overlay {
                                Text("Copied!")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .transition(.opacity)
                    }
                }
                .onTapGesture {
                    copyCode(code)
                }
                
                Text("Tap to copy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Usage Stats
            HStack(spacing: 16) {
                Label("\(usedCount)/\(maxUses)", systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(usageText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Spacer()
            
            // Action Buttons
            VStack(spacing: 12) {
                Button(action: {
                    copyCode(code)
                }) {
                    Label("Copy Code", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .font(.headline)
                }
                
                Button(action: {
                    shareCode(code)
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        .font(.headline)
                }
            }
        }
        .padding(.vertical)
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Couldn't generate code")
                .font(.headline)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                Task {
                    await loadOrGenerateCode()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var usageText: String {
        let remaining = maxUses - usedCount
        if remaining == 0 {
            return "All invites used"
        } else if remaining == 1 {
            return "1 invite remaining"
        } else {
            return "\(remaining) invites remaining"
        }
    }
    
    // MARK: - Actions
    
    private func loadOrGenerateCode() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Check if user already has a code
            if let existingCode = await inviteManager.getUserPersonalCode(userId: userId) {
                Logger.info("Found existing code: \(existingCode)")
                code = existingCode
                
                // Fetch usage stats
                let stats = try await inviteManager.getCodeUsageStats(code: existingCode)
                usedCount = stats.used
                maxUses = stats.max
            } else {
                // Generate new code
                Logger.info("No existing code, generating new one")
                let newCode = try await inviteManager.generatePersonalCode(userId: userId, username: username)
                code = newCode
                usedCount = 0
                maxUses = 5
            }
            
            isLoading = false
        } catch {
            Logger.error("Failed to load/generate code", error: error)
            errorMessage = error.localizedDescription
            isLoading = false
            showError = true
        }
    }
    
    private func copyCode(_ code: String) {
        UIPasteboard.general.string = code
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show feedback
        withAnimation(.easeInOut(duration: 0.3)) {
            showCopiedFeedback = true
        }
        
        // Hide after 1.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopiedFeedback = false
            }
        }
        
        Logger.info("Code copied to clipboard")
    }
    
    private func shareCode(_ code: String) {
        let message = """
        Join me on Stampbook! 🗺️
        
        Use my code: \(code)
        
        TestFlight: https://testflight.apple.com/join/rdfyeZnH
        """
        
        let activityController = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        
        // Present share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            // iPad support
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityController, animated: true)
        }
        
        Logger.info("Opened share sheet")
    }
}

// MARK: - Preview

#Preview {
    PersonalInviteSheet(userId: "test123", username: "hiroo")
}
```

---

### Step 4: Add Invite Icon to StampView

**File to Modify**: `Stampbook/Views/StampView.swift` (or wherever profile screen is)

Find the existing toolbar or navigation bar and add:

```swift
.toolbar {
    // ... existing toolbar items ...
    
    ToolbarItem(placement: .navigationBarTrailing) {
        Button {
            showInviteSheet = true
        } label: {
            Image(systemName: "person.badge.plus")
                .foregroundColor(.blue)
        }
        .accessibilityLabel("Invite friends")
    }
}
.sheet(isPresented: $showInviteSheet) {
    if let userId = authManager.userId,
       let username = profileManager?.profile?.username {
        PersonalInviteSheet(userId: userId, username: username)
    }
}
```

**Add state variable** at top of view:
```swift
@State private var showInviteSheet = false
```

---

### Step 5: Update User Profile Schema

**Note**: No code changes needed. When `generatePersonalCode()` is called, it automatically adds `personalInviteCode` field to the user's profile document.

Existing fields (already there):
- `invitedBy` - userId of who invited them
- `inviteCodeUsed` - code they used to join

New field (auto-added):
- `personalInviteCode` - their personal code to share

---

## 🧪 Testing Checklist

### Functional Tests

- [ ] **First time user taps icon**
  - Sheet opens with loading state
  - Code generates within 1-2 seconds
  - Code displays correctly (8 chars, uppercase)
  - Usage shows "0/5 invites used"

- [ ] **Second time user taps icon**
  - Sheet opens instantly (no loading)
  - Shows same code as before
  - Usage count persists

- [ ] **Copy code button**
  - Code copies to clipboard
  - "Copied!" feedback shows
  - Haptic feedback triggers
  - Can paste into Messages, Notes, etc.

- [ ] **Share button**
  - iOS share sheet opens
  - Pre-filled message includes code and TestFlight link
  - Can share to Messages, WhatsApp, Twitter, etc.
  - Works on iPad (popover positioning)

- [ ] **Usage counter updates**
  - Someone redeems code
  - Counter increments: 1/5, 2/5, etc.
  - Sheet refreshes to show new count

- [ ] **All invites used (5/5)**
  - Shows "All invites used"
  - Shows "0 invites remaining"
  - Can still copy/share code (but won't work)

### Edge Case Tests

- [ ] **No internet on first tap**
  - Shows error message
  - "Try Again" button works
  - Doesn't create malformed data

- [ ] **Firestore write fails**
  - Error alert shows
  - Can retry
  - Doesn't crash app

- [ ] **User changes username**
  - Code stays the same (doesn't regenerate)
  - Works correctly

- [ ] **Very long username**
  - Code still generates (8 random chars)
  - No issues since username not in code

- [ ] **Username with special characters**
  - Code still generates
  - No issues

- [ ] **User signs out and back in**
  - Code persists
  - Same code shows
  - Usage count preserved

- [ ] **Multiple devices**
  - Generate on iPhone
  - Open on iPad
  - Same code appears (Firestore-synced)

### Security Tests

- [ ] **Firestore rules work**
  - User can create their own code (userId matches)
  - User cannot create code for another user
  - User cannot modify maxUses to 999
  - User cannot modify usedCount manually

- [ ] **Code collisions handled**
  - Extremely rare, but code checks for existing
  - Regenerates if collision occurs
  - Doesn't overwrite existing code

### Performance Tests

- [ ] **First code generation**
  - Takes < 2 seconds
  - UI responsive during generation
  - Loading spinner shows

- [ ] **Subsequent opens**
  - Instant (cached in profile)
  - No unnecessary Firestore reads

---

## 🚨 Error Handling

### Errors to Handle

1. **No Internet Connection**
   - Show: "Check your connection and try again"
   - Button: "Try Again" + "Cancel"

2. **Firestore Permission Denied**
   - Show: "Permission error. Please contact support."
   - Log: Check Firestore rules

3. **Code Generation Failed (10 collisions)**
   - Show: "Failed to generate code. Please try again."
   - This is extremely rare (0.0003% chance)

4. **User Not Authenticated**
   - Should never happen (icon only shows when signed in)
   - Fail gracefully with error message

5. **Timeout**
   - After 10 seconds, show timeout error
   - Offer retry

### Logging Strategy

Use existing Logger categories:
```swift
Logger.info("Message", category: "PersonalInvite")
Logger.debug("Debug info", category: "PersonalInvite")
Logger.error("Error occurred", error: error, category: "PersonalInvite")
Logger.success("Success!", category: "PersonalInvite")
```

---

## 📊 Analytics (Future - Don't Build Yet)

Things you might track later:
- How many users generate codes
- How many share (tap share button)
- Average redemption rate (codes used / codes generated)
- Time to first invite (signup → generate code → first redemption)
- Power users (who invites the most)

**Don't build this now.** Get to 100 users first.

---

## 🔄 Migration Path

### Existing Users

Users who signed up before this feature:
- Have no `personalInviteCode` field in profile
- First time they tap icon → code generates
- No special migration needed

### Existing Invite Codes

Your existing admin-generated codes:
- Have `type: "admin"` or `type: "multi-use"`
- Personal codes have `type: "personal"`
- Both work with existing validation
- No conflicts

---

## 🚀 Deployment Steps

### 1. Code Changes
```bash
# Create branch
git checkout -b feature/personal-invite-codes

# Make changes (InviteManager, PersonalInviteSheet, StampView)
# Test locally

# Commit
git add .
git commit -m "Add personal invite code system"
git push origin feature/personal-invite-codes
```

### 2. Deploy Firestore Rules
```bash
# Update firestore.rules (allow code creation)
firebase deploy --only firestore:rules

# Verify in Firebase Console
# Go to Firestore → Rules → Check it deployed
```

### 3. TestFlight Build
```bash
# Archive in Xcode
# Upload to TestFlight
# Add to build notes:
# "New feature: Personal invite codes! Tap the invite icon on your profile to share Stampbook with friends."
```

### 4. Test on TestFlight
- Install build on device
- Test entire flow
- Verify Firestore writes work
- Check share message formatting

### 5. Monitor
- Check Firebase Console for new `invite_codes` documents with `type: "personal"`
- Check Firestore usage (should be negligible)
- Watch for error logs

---

## 📝 Update TestFlight Notes

Add to your TestFlight beta description:

```
NEW: Personal Invite Codes
- Tap the invite icon on your profile
- Get your personal code to share
- Invite up to 5 friends to join Stampbook
```

---

## 🔮 Future Enhancements (Phase 2 - Don't Build Now)

These are ideas for later, once you have 100+ users:

### Gamification
- Unlock 5 more invites after collecting 10 stamps
- Leaderboard of top inviters
- Badges: "Recruited 5 friends"

### Analytics
- "3 of your invites joined! View their profiles"
- "Your friend Sarah just collected their first stamp!"
- Push notifications for invites used

### Social Features
- See who you invited (if they allow)
- Invite tree visualization
- Referral rewards

### Admin Features
- Web dashboard to view all personal codes
- See which users are best at inviting
- Grant bonus invites to power users

**DO NOT BUILD THESE NOW.** Ship the MVP first. Learn from usage. Then add what users actually request.

---

## ✅ Definition of Done

This feature is complete when:

- [ ] InviteManager has personal code generation functions
- [ ] PersonalInviteSheet displays code and share options
- [ ] Invite icon appears on StampView (profile screen)
- [ ] Firestore rules allow code creation
- [ ] All functional tests pass
- [ ] TestFlight build deployed
- [ ] Tested on real device
- [ ] No errors in Firebase logs
- [ ] Share message works correctly
- [ ] Code persists across app restarts

---

## 🆘 Troubleshooting

### "Permission denied" when generating code
**Cause**: Firestore rules not deployed  
**Fix**: Run `firebase deploy --only firestore:rules`

### Code generates but doesn't persist
**Cause**: User profile update failing  
**Fix**: Check user document exists and is writable

### Share sheet doesn't open
**Cause**: iPad popover positioning  
**Fix**: See PersonalInviteSheet code for iPad support

### "Code not found" after generation
**Cause**: Race condition or write failure  
**Fix**: Add retry logic, check Firestore console

### Icon doesn't appear
**Cause**: StampView file name might be different  
**Fix**: Search for profile view file, add icon there

---

## 📞 Support

### Firebase Console
https://console.firebase.google.com

Check:
- Firestore → invite_codes collection
- Firestore → users/{userId}/personalInviteCode field
- Firestore → Rules

### Test Codes

Generate test codes manually if needed:
```bash
node generate_invite_codes.js 5
```

### Check User's Code

Find a user's personal code:
```bash
node check_invite_codes.js
# Look for type: "personal"
```

---

## 📚 Related Documentation

- `INVITE_SYSTEM_COMPLETE.md` - Existing invite system docs
- `docs/INVITE_CODE_SYSTEM.md` - Original invite code design
- `firestore.rules` - Security rules
- `generate_invite_codes.js` - Admin code generation

---

## 🎬 Ready to Build

**Tomorrow's checklist:**

1. Update `firestore.rules` → deploy
2. Add functions to `InviteManager.swift`
3. Create `PersonalInviteSheet.swift`
4. Add icon to StampView (find correct file first)
5. Test locally with 2 test accounts
6. Build for TestFlight
7. Test on real device
8. Ship it! 🚀

**Estimated time:** 2-3 hours for implementation + testing

**Current status:** 2 users (hiroo + watagumostudio)  
**Target:** 100 users via controlled invite growth  
**This feature enables:** Viral growth while maintaining quality control

---

*Let's ship this and get to 100 users!*

