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
⚠️ **Known Issue**: APNs registration sometimes fails in debug builds due to provisioning profile quirks. This doesn't affect production.

**Workaround**: Test push notifications via TestFlight builds instead of debug builds.

## Troubleshooting

### If push notifications stop working:

1. **Check Firebase Console** → Cloud Messaging → Verify APNs keys are still valid
2. **Check Apple Developer** → Keys → Verify `8UNPWH7396` key exists and hasn't been revoked
3. **Check Cloud Functions logs**: 
   ```bash
   firebase functions:log --limit 50
   ```
4. **Verify FCM tokens** are being saved:
   - Check Firestore → `users/{userId}` → Look for `fcmToken` field

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
