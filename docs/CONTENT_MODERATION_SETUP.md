# Content Moderation Setup Guide

## Overview

This setup moves profanity and reserved word filtering from the iOS client to Firebase Cloud Functions, making it impossible to bypass by reading source code.

## What You Get

1. **Server-side validation** for usernames and display names
2. **Profanity filtering** using the `bad-words` npm package
3. **Reserved words protection** (admin, moderator, stampbook, etc.)
4. **Automatic monitoring** via Firestore triggers
5. **Admin alerts** when profanity is detected post-creation

## Cost Estimate

For your MVP scale (100 users, ~500 profile updates/month):
- Cloud Functions: **FREE** (2M invocations/month free)
- Estimated usage: ~1,500 function calls/month = $0.00

## Setup Instructions

### Step 1: Initialize Firebase Functions

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook

# Initialize Firebase Functions (if not already initialized)
firebase init functions

# Choose these options:
# - Language: JavaScript
# - ESLint: Yes (recommended)
# - Install dependencies: Yes
```

### Step 2: Install Dependencies

```bash
cd functions
npm install
```

This installs:
- `firebase-functions` (Cloud Functions SDK)
- `firebase-admin` (Admin SDK for Firestore access)
- `bad-words` (Profanity filter library)

### Step 3: Deploy Cloud Functions

```bash
# Deploy all functions
firebase deploy --only functions

# Or deploy specific functions
firebase deploy --only functions:validateContent,functions:checkUsernameAvailability,functions:moderateComment
```

### Step 4: Test in Emulator (Optional but Recommended)

```bash
# Start Firebase Emulator
cd functions
npm run serve

# The emulator will run at http://localhost:5001
# Your iOS app will automatically use emulator in debug mode if configured
```

### Step 5: Verify Deployment

After deployment, Firebase CLI will show URLs like:

```
✔  functions[validateContent(us-central1)] Deployed
✔  functions[checkUsernameAvailability(us-central1)] Deployed
✔  functions[moderateComment(us-central1)] Deployed
✔  functions[moderateProfileOnWrite(us-central1)] Deployed
```

Test the functions:

```bash
# Using curl (replace PROJECT_ID with your Firebase project ID)
curl -X POST \
  https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/validateContent \
  -H "Content-Type: application/json" \
  -d '{"username": "test123", "displayName": "Test User"}'
```

### Step 6: Deploy Firestore Security Rules

```bash
# Deploy updated security rules (includes username validation)
firebase deploy --only firestore:rules
```

### Step 7: Test in iOS App

1. Build and run the app in Xcode
2. Try to create an account or edit profile
3. Try these test cases:
   - Valid username: `testuser123` ✅
   - Invalid (too short): `ab` ❌
   - Invalid (profanity): `badword123` ❌
   - Invalid (reserved): `admin` ❌
   - Invalid (special chars): `test@user` ❌

## Monitoring & Maintenance

### View Moderation Alerts

Profanity detected by the Firestore trigger creates alerts in the `moderation_alerts` collection:

```javascript
// In Firebase Console → Firestore → moderation_alerts
{
  userId: "abc123",
  type: "profanity_in_profile",
  fields: ["username"],
  username: "badword",
  displayName: "John Doe",
  detectedAt: timestamp,
  status: "pending"
}
```

### View Function Logs

```bash
# View all function logs
firebase functions:log

# View specific function logs
firebase functions:log --only validateContent

# Follow logs in real-time
firebase functions:log --follow
```

### Update Word Lists

To add/remove words from the filter:

1. Edit `functions/index.js`
2. Update the `reservedWords` array (line 13-17)
3. Redeploy: `firebase deploy --only functions`

No app update needed! Changes take effect immediately.

## Customization Options

### Option 1: Auto-Revert Profanity (Stricter)

Uncomment lines 104-115 in `functions/index.js` to automatically revert profile changes containing profanity.

### Option 2: Filter Comments Instead of Rejecting

Change `moderateComment` function (line 144) to return filtered text instead of rejecting:

```javascript
// Instead of rejecting:
return { clean: false, error: 'Comment contains inappropriate content' };

// Return filtered version:
const filtered = filter.clean(text);
return { clean: true, filtered: filtered, wasFiltered: true };
```

### Option 3: Use Third-Party Service

For more advanced moderation, replace `bad-words` with:

1. **Perspective API** (Google) - ML-based toxicity detection
   ```bash
   npm install @google-cloud/language
   ```

2. **WebPurify** - Professional content moderation
   ```bash
   npm install webpurify
   ```

3. **CleanSpeak** - Enterprise moderation with human review

## Troubleshooting

### "Functions are not deployed"

**Solution**: Run `firebase deploy --only functions`

### "Failed to validate content"

**Check**:
1. Functions are deployed: `firebase functions:list`
2. iOS app has network permissions
3. Firebase project is correct in GoogleService-Info.plist

### "Username validation always fails"

**Check**:
1. Firestore security rules are deployed: `firebase deploy --only firestore:rules`
2. User is authenticated (not anonymous)
3. Function logs: `firebase functions:log --only checkUsernameAvailability`

### "Performance is slow"

Cloud Functions have cold start times (~500ms-2s). After first call, they stay warm for ~15 minutes.

**Solutions**:
1. Accept cold starts (normal for free tier)
2. Upgrade to Cloud Functions Gen 2 (faster cold starts, still free at your scale)
3. Add loading indicators in UI

## Migration from Client-Side

The old client-side validation has been removed from:
- `ProfileEditView.swift` (lines 14-51 deleted)
- Server-side validation now runs before Firestore writes

Users on old app versions (if any) will still have client-side validation, but server-side validation is the final authority.

## Next Steps

1. **Monitor alerts**: Check `moderation_alerts` collection weekly
2. **Adjust word list**: Add words as needed based on alerts
3. **Consider AI moderation**: At 500+ users, evaluate Perspective API
4. **Rate limiting**: At 1000+ users, add rate limits to prevent API abuse

## Security Notes

- ✅ Cloud Functions run with admin privileges (secure)
- ✅ Client cannot bypass validation (server-side enforcement)
- ✅ Word list is hidden from users (not in app binary)
- ✅ Firestore rules validate username format as backup
- ⚠️ No rate limiting yet (add at 500+ users to prevent API spam)

## Cost at Scale

| Users | Profile Updates/Month | Function Calls | Cost |
|-------|----------------------|----------------|------|
| 100   | 500                  | 1,500          | $0   |
| 1,000 | 5,000                | 15,000         | $0   |
| 10,000| 50,000               | 150,000        | $0   |
| 50,000| 250,000              | 750,000        | $0   |

Cloud Functions is free for first 2M invocations/month, then $0.40 per million.
You'd need 2M+ profile updates/month to pay anything.

