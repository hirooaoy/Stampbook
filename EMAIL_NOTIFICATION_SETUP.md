# Email Notification Setup for User Blocking

## Overview
When a user blocks another user, the app automatically sends an email notification to you for review within 24 hours (App Store compliance requirement).

## Setup Steps

### 1. Create Gmail App Password
1. Go to your Google Account: https://myaccount.google.com/
2. Navigate to **Security** → **2-Step Verification** (enable if not already)
3. Scroll down to **App passwords**
4. Click **Select app** → Choose **Mail**
5. Click **Select device** → Choose **Other (Custom name)**
6. Enter "Stampbook Cloud Functions"
7. Click **Generate**
8. **Copy the 16-character password** (you won't see it again!)

### 2. Configure Firebase Environment Variables
Run these commands in your terminal (replace with your actual values):

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook

# Set your Gmail address
firebase functions:config:set gmail.email="your-email@gmail.com"

# Set the app password you just created (no spaces)
firebase functions:config:set gmail.password="abcd efgh ijkl mnop"
```

### 3. Deploy the Cloud Function
```bash
firebase deploy --only functions:notifyUserBlocked
```

### 4. Test It (Optional)
You can test by having a test user block someone. You should receive an email within seconds.

## What You'll Receive

When a user blocks someone, you'll get an email with:
- **Subject:** 🚨 [STAMPBOOK] User Blocked - Review Required (24h)
- **Reporter details:** Who blocked someone
- **Blocked user:** Who was blocked
- **Direct links:** To Firebase Console to review both users
- **Message:** The auto-generated report

## Troubleshooting

### Not receiving emails?
1. Check Firebase Functions logs:
   ```bash
   firebase functions:log
   ```
2. Verify your config is set:
   ```bash
   firebase functions:config:get
   ```
3. Check spam folder
4. Verify Gmail App Password is correct

### Security Note
- App passwords are safer than your main password
- They're specific to this app only
- You can revoke them anytime from Google Account settings

## Alternative: Use Your Own Email Service
If you prefer to use SendGrid, Mailgun, or another service, edit the `notifyUserBlocked` function in `functions/index.js` and replace the nodemailer configuration.

