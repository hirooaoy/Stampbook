# Invite Code System

## Overview

Stampbook uses an invite-only system to control growth and prevent viral spikes that could overwhelm infrastructure or cause unexpected costs.

## How It Works

### For Users

1. New users see an onboarding screen with "Get Started" button
2. Tapping "Get Started" opens a sheet asking for an invite code
3. After entering a valid code, they proceed to Sign in with Apple
4. Account is created with the invite code tracked in their profile
5. Returning users can bypass the code by tapping "Already have account? Sign in"

### For Admins

You control exactly who can join by generating and sharing invite codes.

## Admin Scripts

### Generate Codes

Create new invite codes:

```bash
# Generate 50 multi-use codes (unlimited uses per code)
node generate_invite_codes.js 50

# Generate 10 single-use codes (one person only)
node generate_invite_codes.js 10 --single
```

### Check Code Usage

View code statistics:

```bash
# List all codes with usage stats
node check_invite_codes.js

# Check a specific code
node check_invite_codes.js SUMMIT24
```

## Growth Strategy

### Launch (Week 1)

1. Generate 50 codes: `node generate_invite_codes.js 50`
2. Share strategically:
   - 10 codes to close friends/testers
   - 5 codes on Twitter: "First 100 people, use SUMMIT24"
   - 10 codes for press/influencers
   - 25 codes in reserve

### Controlled Growth

Multi-use codes allow organic sharing without losing control:
- Post a code on Twitter → 100-500 people use it
- You knew it was coming (you posted it)
- When you want to slow growth, stop sharing new codes
- Existing users keep using the app

### Monitoring

Watch Firebase console for:
- New user signups
- Storage/bandwidth costs
- Firestore read/write usage

If costs or complexity spike, pause code distribution until ready.

## Code Format

- 8 uppercase characters (letters + numbers)
- Excludes confusing characters: 0, O, 1, I, L
- Examples: `SUMMIT24`, `HRX9K2M4`, `QP7N8WR3`
- Randomly generated using crypto module

## Data Model

### Firestore Collection: `invite_codes/{code}`

```javascript
{
  code: "SUMMIT24",
  type: "admin" | "user",
  createdBy: "admin" | userId,
  maxUses: 999999,       // unlimited for admin, 1 for user codes
  usedCount: 47,
  usedBy: ["userId1", "userId2", ...],
  createdAt: timestamp,
  expiresAt: null,
  status: "active" | "used" | "expired"
}
```

### User Profile Fields

New fields added to `users/{userId}`:

```javascript
{
  inviteCodeUsed: "SUMMIT24",
  invitedBy: "admin" | userId,
  invitesRemaining: 0,    // Phase 2: set to 5 for user invites
  accountCreatedAt: timestamp
}
```

## Security

### Firestore Rules

```javascript
match /invite_codes/{code} {
  // Can read ONE specific code (for validation)
  allow get: if true;
  
  // CANNOT list all codes (prevents scraping)
  allow list: if false;
  
  // Only admins can write (via service account)
  allow write: if false;
}
```

### Race Condition Protection

Account creation uses Firestore transactions to prevent two users from using a single-use code simultaneously.

### Orphaned Auth State Recovery

On app launch, AuthManager checks:
1. Is user authenticated with Firebase Auth?
2. Does their Firestore profile exist?
3. If no profile → Sign out → Show onboarding

This prevents users from getting stuck if sign-in succeeds but profile creation fails.

## Phase 2: User Invites (Future)

When ready for organic growth:

1. Each new user gets 5 codes auto-generated
2. Add "Invite Friends" screen in app settings
3. Users can share their codes (single-use)
4. Track social graph (who invited who)
5. Reward top inviters with badges/features

Growth becomes semi-viral but controlled:
- 100 users × 5 invites each = max 500 new users
- Realistically, 20% share codes, 50% redeemed = 100 → 150 users
- Manageable, organic growth

## Cost Protection

What this prevents:
- App goes viral → 10K signups overnight
- Without codes → They can't get in
- You control growth rate and timing

What this doesn't prevent:
- Active users posting lots of photos (limit user count, not activity)
- Malicious users within the app (need other protections)

## Testing

Generate test codes for development:
```bash
node generate_invite_codes.js 5 --single
```

Use these codes to test the full onboarding flow without burning production codes.

## Firebase Console

Monitor in Firebase:
- **Authentication**: See new user signups
- **Firestore > invite_codes**: View code usage
- **Firestore > users**: Check who used which codes

## Troubleshooting

### "Code doesn't exist"
- Code might have typo
- Code might not be generated yet
- Check with: `node check_invite_codes.js SUMMIT24`

### "Code has been fully claimed"
- Single-use code already redeemed
- Generate new codes or use multi-use code

### "No account found" on sign in
- User is new but trying to bypass code entry
- They need a valid invite code
- This is working as intended

### Orphaned auth state
- User authenticated but no profile
- App will auto-sign them out on next launch
- They'll restart onboarding properly

## Quick Reference

```bash
# Generate 20 codes
node generate_invite_codes.js 20

# Check all codes
node check_invite_codes.js

# Check specific code
node check_invite_codes.js SUMMIT24

# Deploy security rules
firebase deploy --only firestore:rules
```

## Launch Checklist

- [ ] Generate launch codes: `node generate_invite_codes.js 50`
- [ ] Deploy Firestore rules: `firebase deploy --only firestore:rules`
- [ ] Test onboarding flow with a test code
- [ ] Post launch tweet with invite code
- [ ] Share codes in TestFlight notes
- [ ] Monitor Firebase console for signups
- [ ] Watch for cost spikes (set up billing alerts)

---

Built to protect against viral chaos while enabling controlled growth. 🚀

