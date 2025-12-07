# Push Notifications Setup - Stampbook

**Status**: ✅ Configured and Working (as of Nov 24, 2025)

## Overview

Stampbook uses Firebase Cloud Messaging (FCM) with Apple Push Notification service (APNs) to send real-time notifications to users for:
- Likes on their posts
- New followers
- Comments on their posts
- @mentions in comments

## Configuration

### Apple Developer Portal

**APNs Authentication Key**:
- Key ID: `8UNPWH7396`
- Team ID: `28VYBXMX82`
- File: `AuthKey_8UNPWH7396.p8` (stored in project root, ignored by git)
- Type: Team Scoped (all apps)
- Environment: Production

**Location**: `/Users/haoyama/Desktop/Developer/Stampbook/AuthKey_8UNPWH7396.p8`

### Firebase Console

**Project**: `stampbook-app`

**APNs Keys Configured**:
- Development APNs auth key: `8UNPWH7396` / `28VYBXMX82` ✅
- Production APNs auth key: `8UNPWH7396` / `28VYBXMX82` ✅

**Cloud Functions Deployed**:
- `createLikeNotification` - Triggers on new like
- `createFollowNotification` - Triggers on new follow
- `createCommentNotification` - Triggers on new comment (includes @mention detection)
- `cleanupCommentNotifications` - Cleans up notifications when comments deleted

### Xcode Configuration

**App Target**: Stampbook

**Capabilities Enabled**:
- Push Notifications ✅
- Sign in with Apple ✅
- App Groups ✅

**Entitlements** (`Stampbook.entitlements`):
```xml
<key>aps-environment</key>
<string>production</string>
```

**Bundle ID**: `watagumostudio.StampbookApp`

**Signing**: Automatic (managed by Xcode)

## How It Works

1. **User opens app** → iOS registers device with APNs → Gets device token
2. **Firebase SDK** converts APNs token to FCM token
3. **App saves FCM token** to Firestore (`users/{userId}/fcmToken`)
4. **User triggers action** (like, follow, comment) → Firestore document created
5. **Cloud Function triggers** → Fetches recipient's FCM token
6. **Firebase sends notification** → FCM → APNs → User's device
7. **Push notification appears** on user's iPhone

## Testing

### Production (TestFlight/App Store)
✅ **Working**: Push notifications deliver successfully

### Development (Xcode Debug)
❌ **DOES NOT WORK**: Push notifications are unreliable or fail completely in debug builds from Xcode.

**This is NOT a bug - it's a normal Apple/Firebase limitation!**

**Why Debug Builds Fail:**
- Debug builds use development provisioning profiles
- APNs requires production certificates for reliable delivery
- Firebase may not be able to authenticate with APNs for debug builds
- Error: `messaging/third-party-auth-error`

**How to Test Push Notifications:**
1. ✅ **Use TestFlight builds** (production environment)
2. ✅ **Use Ad Hoc builds** with production provisioning profile
3. ❌ **Do NOT test with Xcode debug builds** - they won't work

**What DOES Work in Debug Builds:**
- ✅ In-app notifications (bell icon)
- ✅ Notification badge counts
- ✅ Notification data saved to Firestore
- ✅ FCM token registration
- ❌ Push notification banners/sounds (unreliable)

## Troubleshooting

### "Push notifications aren't working!"

**FIRST: Are you testing with a Debug build from Xcode?**
- ❌ Debug builds DO NOT support push notifications reliably
- ✅ Use TestFlight or Ad Hoc builds instead

**If using TestFlight and still not working:**

1. **Check if in-app notifications work:**
   - Open app → Tap bell icon → Do you see notifications?
   - If YES → Push notifications are being created, just not delivered
   - If NO → Problem is with notification creation (Cloud Functions)

2. **Check user's notification permissions:**
   - Settings → Stampbook → Notifications → Allow Notifications = ON
   - Check Do Not Disturb / Focus mode is OFF

3. **Check Firebase Console** → Cloud Messaging → Verify APNs keys are still valid

4. **Check Apple Developer** → Keys → Verify `8UNPWH7396` key exists and hasn't been revoked

5. **Check Cloud Functions logs**: 
   ```bash
   firebase functions:log
   ```
   Look for `❌ Failed to send push notification` errors

6. **Verify FCM tokens** are being saved:
   - Check Firestore → `users/{userId}` → Look for `fcmToken` field
   - If missing, user needs to sign out and sign back in

7. **Test with script:**
   ```bash
   node test_push_notification_to_hiroo.js
   ```
   If this fails with `messaging/third-party-auth-error` → Re-upload APNs key

### Re-uploading APNs Key (if needed):

If you ever need to regenerate or re-upload the APNs key:

1. **Apple Developer Portal**:
   - Certificates, Identifiers & Profiles → Keys
   - Create new key with APNs enabled
   - Download `.p8` file (can only download once!)
   - Note Key ID and Team ID

2. **Firebase Console**:
   - Project Settings → Cloud Messaging
   - Upload `.p8` file to both Development and Production slots
   - Enter Key ID and Team ID

## Security

**Sensitive Files** (in `.gitignore`):
- `AuthKey_8UNPWH7396.p8` - APNs authentication key
- `*.p8` - All APNs keys
- `serviceAccountKey.json` - Firebase admin credentials

**Never commit these files to version control!**

## Related Files

- Cloud Functions: `/functions/index.js` (notification triggers)
- App Delegate: `/Stampbook/StampbookApp.swift` (FCM token handling)
- Auth Manager: `/Stampbook/Services/AuthManager.swift` (token updates)
- Firebase Service: `/Stampbook/Services/FirebaseService.swift` (token storage)
- Entitlements: `/Stampbook/Stampbook.entitlements` (APNs environment)

## Cost

Push notifications are **free** on Firebase's Blaze plan. There are no limits on the number of messages you can send.

## References

- [Firebase Cloud Messaging for iOS](https://firebase.google.com/docs/cloud-messaging/ios/client)
- [Apple Push Notification Service](https://developer.apple.com/documentation/usernotifications)
- [Creating APNs Authentication Key](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns)
