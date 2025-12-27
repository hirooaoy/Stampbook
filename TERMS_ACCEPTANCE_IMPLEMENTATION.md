# Terms of Service Acceptance Implementation

**Date:** December 16, 2024  
**Priority:** Critical (App Store Requirement)  
**Status:** ✅ COMPLETE

---

## Summary

Implemented Terms of Service acceptance to satisfy Apple App Store Guideline 1.2 - User Generated Content. Users must now accept terms that explicitly state "zero tolerance for objectionable content" before creating an account.

---

## What Was Implemented

### 1. Terms of Service Document
**File:** `/public/terms-of-service.html`  
**URL:** https://stampbook-app.web.app/terms-of-service.html

**Includes:**
- ✅ Zero tolerance policy for objectionable content (Section 2)
- ✅ Clear list of prohibited content (hate speech, harassment, explicit content, violence, illegal activity, spam, impersonation)
- ✅ Clear list of prohibited behavior
- ✅ Content moderation process (automated filtering, 24-hour response)
- ✅ Consequences for violations (content removal, warnings, suspension, permanent ban)
- ✅ Reporting mechanisms (report users, comments, posts)
- ✅ Blocking functionality (described in Section 5)
- ✅ User responsibilities and content ownership
- ✅ Privacy policy reference
- ✅ Contact information

### 2. UserProfile Model Update
**File:** `Stampbook/Models/UserProfile.swift`

**Changes:**
- Added `acceptedTermsAt: Date?` field to track when user accepted terms
- Added to CodingKeys enum
- Updated init() to include parameter
- Updated decoder to handle legacy accounts (defaults to createdAt for backward compatibility)
- Updated encoder to save timestamp

**Backward Compatibility:**
- Existing users without this field automatically get `acceptedTermsAt = createdAt`
- No database migration needed
- Existing users (hiroo, etc.) won't be affected

### 3. InviteCodeSheet UI Update
**File:** `Stampbook/Views/InviteCodeSheet.swift`

**Changes:**
- Added `@State private var acceptedTerms = false`
- Added terms acceptance checkbox on Page 2 (before Sign in with Apple)
- Checkbox includes tappable links to Terms of Service and Privacy Policy
- Sign in button is disabled until terms are accepted
- Button appearance changes when terms are accepted (gray → white)
- Links open in Safari when tapped

**User Flow:**
1. User enters invite code (Page 1)
2. Code validated → proceeds to Page 2
3. Page 2 shows "You're invited!" with checkbox
4. User must check "I agree to Terms of Service and Privacy Policy"
5. Links are tappable and open in browser
6. Sign in button becomes enabled
7. User taps "Sign in with Apple"
8. Account created with `acceptedTermsAt` timestamp

### 4. InviteManager Update
**File:** `Stampbook/Managers/InviteManager.swift`

**Changes:**
- Added `"acceptedTermsAt": FieldValue.serverTimestamp()` to account creation
- Timestamp saved when user profile is created in Firestore
- Uses serverTimestamp() for accuracy

---

## Files Modified

1. ✅ `/public/terms-of-service.html` (NEW)
2. ✅ `Stampbook/Models/UserProfile.swift`
3. ✅ `Stampbook/Views/InviteCodeSheet.swift`
4. ✅ `Stampbook/Managers/InviteManager.swift`

---

## Deployment Status

✅ **Firebase Hosting:** Deployed
- https://stampbook-app.web.app/terms-of-service.html ← Terms of Service
- https://stampbook-app.web.app/privacy-policy.html ← Privacy Policy (already existed)

---

## Testing Checklist

Test the following before resubmitting to App Store:

### New User Flow
- [ ] Open app (not signed in)
- [ ] Tap "Enter invite code"
- [ ] Enter valid code → tap Continue
- [ ] See "You're invited!" page with unchecked checkbox
- [ ] Verify "Sign in with Apple" button is DISABLED (gray)
- [ ] Tap checkbox → verify it checks
- [ ] Verify "Sign in with Apple" button is now ENABLED (white)
- [ ] Tap "Terms of Service" link → verify it opens in Safari
- [ ] Tap "Privacy Policy" link → verify it opens in Safari
- [ ] Tap "Sign in with Apple" → complete auth
- [ ] Account created successfully
- [ ] Check Firestore: verify user document has `acceptedTermsAt` timestamp

### Existing User Flow
- [ ] Sign in with existing account (hiroo)
- [ ] Verify app works normally
- [ ] Check Firestore: verify old accounts have `acceptedTermsAt` set to `createdAt`

### Edge Cases
- [ ] Try signing in WITHOUT checking terms → verify button stays disabled
- [ ] Check terms, then uncheck → verify button disables again
- [ ] Navigate back to Page 1 → return to Page 2 → verify checkbox state resets

---

## App Store Compliance

This implementation satisfies Apple's Guideline 1.2 requirement:

> "Require that users agree to terms (EULA) and these terms must make it clear that there is no tolerance for objectionable content or abusive users"

### What Apple Will See

1. **During signup:** User MUST check terms acceptance checkbox
2. **Button is disabled** until terms are checked
3. **Terms document** clearly states "zero tolerance for objectionable content"
4. **Lists prohibited content:** hate speech, harassment, explicit content, violence, illegal activity, spam
5. **Consequences:** content removal, warnings, suspension, permanent ban
6. **24-hour response commitment** to reports

---

## What's Still Needed (Priorities 2-4)

This completes **Priority 1: Terms Acceptance**. Still needed for full compliance:

### Priority 2: User Blocking (4-5 hours)
- Add "Block user" button to UserProfileView
- Create BlockManager
- Filter blocked users from feed/comments
- Notify developer when blocking occurs

### Priority 3: Post Reporting (1 hour)
- Add report menu to feed posts
- Create SimplePostReportView
- Submit to feedback collection

### Priority 4: Documentation (30 mins)
- Document 24-hour review process
- Set up daily report monitoring

---

## Technical Notes

### Why acceptedTermsAt is Optional
- Allows backward compatibility with existing accounts
- Decoder defaults to createdAt for legacy users
- New users always get a timestamp

### Why We Use serverTimestamp()
- Ensures accurate time (not dependent on device clock)
- Consistent with other timestamp fields (createdAt, lastActiveAt)
- Cannot be manipulated by client

### Why Links Open in Safari
- Apple guidelines prefer external browser for legal documents
- Allows users to bookmark/share terms
- Better accessibility (full browser features)

---

## Verification

✅ **Linter:** No errors  
✅ **Build:** Compiles successfully  
✅ **Firebase:** Terms deployed  
✅ **Backward Compatibility:** Existing users unaffected  
✅ **App Store Requirement:** Terms acceptance implemented

---

## Next Steps

1. **Test the implementation** (use checklist above)
2. **Build new TestFlight version**
3. **Test with TestFlight**
4. **Implement Priority 2 (User Blocking)** before resubmission
5. **Implement Priority 3 (Post Reporting)** before resubmission
6. **Document 24-hour policy** (Priority 4)
7. **Resubmit to App Store**

---

## App Review Notes

When resubmitting, include in "Notes for Reviewer":

```
We have implemented the following features to comply with Guideline 1.2:

1. Terms of Service Acceptance:
   - Users must accept terms before creating an account
   - Terms explicitly state "zero tolerance for objectionable content"
   - Terms available at: https://stampbook-app.web.app/terms-of-service.html

2. Content Filtering:
   - Server-side profanity filter using Cloud Functions
   - Automated moderation of usernames, display names, and comments

3. Reporting System:
   - Users can report other users and comments
   - Reports reviewed within 24 hours
   - Violating content removed and users warned/banned

4. Contact Information:
   - Email: watagumo.studio@gmail.com
   - Accessible in app settings and support pages

[Note: User blocking and post reporting features are being implemented next]
```

---

## Questions?

Contact: watagumo.studio@gmail.com

