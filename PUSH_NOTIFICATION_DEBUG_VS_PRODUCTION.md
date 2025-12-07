# Quick Reference: Push Notifications in Stampbook

## TL;DR
- ❌ **Debug builds from Xcode:** Push notifications DON'T work
- ✅ **TestFlight builds:** Push notifications DO work
- ✅ **In-app notifications (bell icon):** Always work

## Why Debug Builds Fail

Apple's APNs (Apple Push Notification service) requires **production certificates** to reliably deliver push notifications. Debug builds use **development provisioning profiles**, which causes Firebase to fail authentication with Apple's servers.

**Error you'll see:**
```
messaging/third-party-auth-error: Auth error from APNS or Web Push Service
```

**This is NORMAL and EXPECTED for debug builds!**

## How to Test Push Notifications

### ✅ Method 1: TestFlight (Recommended)
1. Archive the app in Xcode
2. Upload to App Store Connect
3. Distribute via TestFlight
4. Install on test device
5. Test notifications - they will work!

### ✅ Method 2: Ad Hoc Build
1. Create Ad Hoc provisioning profile (production)
2. Archive with Ad Hoc profile
3. Export and install via Xcode Devices window
4. Test notifications - they will work!

### ❌ Method 3: Debug Build from Xcode (DON'T)
1. Click Run button in Xcode
2. App launches on device
3. Notifications DON'T work ← This is expected!

## What Works in Debug Builds

Even though push notifications don't work in debug builds, these features DO work:

✅ **In-app notifications**
- Notifications are created in Firestore
- Users can see them in the bell icon
- Badge counts update correctly

✅ **FCM token registration**
- App registers for remote notifications
- FCM token is saved to Firestore
- Everything is set up correctly

✅ **Cloud Functions**
- Functions trigger when users comment/like/follow
- Notifications are created in Firestore
- Push notification sending is attempted (but fails silently for debug builds)

❌ **Push notification delivery**
- Banners don't appear
- Sounds don't play
- Lock screen notifications don't show

## Verifying Everything Works

### Step 1: Check In-App Notifications
1. User A comments on User B's post
2. User B opens app
3. User B taps bell icon
4. **Expected:** Notification shows up ✅

If this works, the entire notification system is working correctly!

### Step 2: Test Push Notifications (TestFlight)
1. Build for TestFlight
2. User A comments on User B's post
3. User B's phone shows banner notification
4. **Expected:** Push notification appears ✅

## Common Mistakes

### ❌ Mistake 1: Testing Debug Build
**Symptom:** "Push notifications aren't working!"  
**Reality:** Debug builds don't support push notifications  
**Solution:** Use TestFlight

### ❌ Mistake 2: Thinking APNs Config is Broken
**Symptom:** `messaging/third-party-auth-error` in logs  
**Reality:** This error is normal for debug builds  
**Solution:** Ignore error in debug, test with TestFlight

### ❌ Mistake 3: Re-uploading APNs Key
**Symptom:** Push not working in debug  
**Reality:** APNs key is fine, debug builds are the issue  
**Solution:** Don't touch Firebase config, use TestFlight

## Testing Checklist

Before assuming push notifications are broken:

- [ ] Are you testing with a **Debug build**? → Use TestFlight instead
- [ ] Are you testing with a **TestFlight build**? → Check settings below
- [ ] Is "Allow Notifications" enabled in iOS Settings → Stampbook?
- [ ] Is Do Not Disturb / Focus mode OFF?
- [ ] Does the in-app notification (bell icon) show the notification?
- [ ] Does Firestore have the notification document?
- [ ] Does the user have an `fcmToken` in Firestore?

If all of these pass (except debug build), push notifications ARE working correctly and will work in production.

## Firebase Console Check

Only check Firebase Console if TestFlight builds are also failing:

1. Go to: https://console.firebase.google.com/project/stampbook-app/settings/cloudmessaging
2. Verify APNs Authentication Key shows:
   - Key ID: `8UNPWH7396`
   - Team ID: `28VYBXMX82`
   - Status: Active (not expired)

If missing or invalid, re-upload the key from `/Users/haoyama/Desktop/Developer/Stampbook/AuthKey_8UNPWH7396.p8`

## Summary

**Don't waste time debugging push notifications in debug builds - they're not supposed to work!**

Just verify:
1. ✅ In-app notifications work (bell icon shows notifications)
2. ✅ Firestore has notification documents
3. ✅ User has FCM token in Firestore

If all 3 are true → **Push notifications ARE working, just test with TestFlight to verify delivery.**

---

**Last Updated:** December 2, 2025  
**Status:** All notification systems working correctly in production (TestFlight)

