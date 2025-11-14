# User Connection Issue Investigation Report
**User ID:** `iJWtHIxd3YNxOWTOUs18gBkQK5D2`
**Date:** November 13, 2025
**Status:** ⚠️ UNKNOWN - Email Missing but Not the Cause

---

## Problem Summary

User "Law" is experiencing errors when trying to use the app after signing up with Apple Sign-In.

## Investigation Results

**INITIAL HYPOTHESIS (INCORRECT):** The user's Firestore document is missing the `email` field`.

**ACTUAL FINDINGS:** The email field IS missing, but it's NOT causing the issue because:
1. ❌ Email is missing from ALL 3 users (hiroo, rosemary, Law)
2. ✅ Email is NOT used anywhere in the Swift code, Cloud Functions, or Firestore rules
3. ✅ All users have complete, valid Firestore documents with all required fields
4. ✅ rosemary's account is identical to Law's and should work fine

**CONCLUSION:** The connection error is NOT from the Firestore data. Something else is causing Law's issue.

### Current User State:

**Firebase Auth (Authentication):**
- ✅ Email: `kvtp87hqhv@privaterelay.appleid.com` (Apple Private Relay)
- ✅ Email Verified: true
- ✅ Provider: Apple Sign-In
- ✅ Created: November 13, 2025, 1:54:26 PM
- ✅ Last Sign In: November 13, 2025, 1:54:26 PM

**Firestore Database:**
- ✅ Username: `user_iJWtHIxd` (auto-generated)
- ✅ Display Name: `user_iJWtHIxd`
- ❌ **Email: MISSING** ← This is the problem!
- ✅ Created At: November 13, 2025
- ✅ Has Seen Onboarding: true
- ✅ Total Stamps: 0
- ✅ Followers: 0
- ✅ Following: 0

---

## Technical Analysis

### What Happened:

1. User signed up with Apple Sign-In successfully
2. Firebase Auth account was created with email
3. When the Firestore user document was created, the email was NOT copied from Firebase Auth
4. App is likely trying to access the email field from Firestore and failing

### Why This Happened:

The `UserProfile` Swift model does **not include an `email` field**:

```swift
struct UserProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let username: String
    var displayName: String
    var bio: String
    var avatarUrl: String?
    var totalStamps: Int
    // ... other fields ...
    // ❌ NO EMAIL FIELD
}
```

When `createUserProfile()` is called in `FirebaseService.swift`, it only sets these fields:
- id
- username
- displayName
- bio
- avatarUrl
- totalStamps
- createdAt
- lastActiveAt

The email is never transferred from Firebase Auth to the Firestore document.

### Historical Context:

Looking at other users in Firestore, some older accounts DO have the email field (like "hiroo" and "watagumostudio"), which suggests:

1. The email field was part of the original design
2. It was removed from the UserProfile model at some point
3. Old accounts still have it, but new accounts don't get it

---

## Why This Causes Connection Issues

The app is likely:
1. Trying to read `user.email` from Firestore (where it doesn't exist)
2. Expecting the email field for some backend operations
3. Failing to properly initialize the user session without the email

---

## Comparison with Working Accounts

### User "hiroo" (Working):
```json
{
  "email": "haoyama@princeton.edu",
  "username": "hiroo",
  "displayName": "Hiro",
  ...
}
```

### User "watagumostudio" (Working):
```json
{
  "email": "hiroyama03@gmail.com",
  "username": "watagumostudio",
  "displayName": "watagumostudio",
  ...
}
```

### User "Law" (Broken):
```json
{
  // ❌ email: MISSING
  "username": "user_iJWtHIxd",
  "displayName": "user_iJWtHIxd",
  ...
}
```

---

## Questions to Consider

1. **Is the email field actually needed?**
   - If yes, it needs to be added back to the UserProfile model and set during account creation
   - If no, then something in the app is incorrectly trying to access it

2. **What changed between old accounts (that have email) and new accounts (that don't)?**
   - Was the email field intentionally removed from the model?
   - Are there any backend services (Cloud Functions, Firestore Rules) that expect the email field?

3. **Is the app code trying to access email from Firestore?**
   - Need to check if any views/services are reading `profile.email`
   - May need to update code to read from Firebase Auth instead if email is needed

---

## Recommended Next Steps (Do NOT Implement Yet)

**Option A: Add Email Back to UserProfile Model**
1. Add `email` field to `UserProfile.swift` model
2. Update `createUserProfile()` to accept and save email
3. Pass email from Firebase Auth when creating the profile
4. Backfill email for this user manually

**Option B: Remove All Email Dependencies**
1. Find all places in code that try to access user email from Firestore
2. Update them to read from Firebase Auth instead (or remove if not needed)
3. User would work without needing email in Firestore

**Option C: Quick Fix for This User**
1. Manually add email field to this user's Firestore document
2. Test if connection issue resolves
3. Then implement proper fix for future users

---

## Investigation Files Created

- `investigate_user_issue.js` - Full user data inspection
- `check_auth_email.js` - Firebase Auth vs Firestore comparison

These can be deleted after the issue is resolved.

