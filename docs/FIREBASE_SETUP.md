# Firebase Setup Guide

## Overview

Stampbook uses Firebase for backend services:
- **Firestore**: Database (stamps, collections, user data, posts)
- **Firebase Storage**: Image storage (user photos, profile pictures)
- **Firebase Auth**: User authentication

## Initial Setup (Already Complete)

### 1. Firebase Project Created
- Project ID: `stampbook-app`
- Region: `us-central1`
- Plan: Spark (Free tier)

### 2. iOS App Configured
- Bundle ID: `watagumostudio.StampbookApp`
- GoogleService-Info.plist added to project
- Firebase SDK integrated (v11.0.0+)

### 3. Authentication Enabled
- Email/Password provider enabled
- No email verification required (MVP)

### 4. Firestore Security Rules Deployed
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Stamps - public read, admin write only
    match /stamps/{stampId} {
      allow read: if true;
      allow write: if false;  // Only via console/script
    }
    
    // Collections - public read, admin write only
    match /collections/{collectionId} {
      allow read: if true;
      allow write: if false;
    }
    
    // Stamp statistics - authenticated users can update
    match /stamp_statistics/{stampId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // User profiles
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth.uid == userId;
      
      match /collected_stamps/{stampId} {
        allow read: if true;
        allow write: if request.auth.uid == userId;
      }
    }
    
    // Feed posts
    match /feed_posts/{postId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.userId;
    }
  }
}
```

### 5. Storage Rules Deployed
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // User photos - authenticated users only
    match /users/{userId}/photos/{photoId} {
      allow read: if true;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Stamp images - public read, admin write
    match /stamps/{imageId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

## Data Migration

### Initial Data Upload (Already Complete)

```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
node migrate_to_firebase.js
```

This uploaded:
- ✅ All stamps from `stamps.json`
- ✅ All collections from `collections.json`
- ✅ Initialized stamp statistics

### Adding New Stamps

See `/docs/ADDING_STAMPS.md` for detailed workflow.

**Quick version:**
1. Edit `Stampbook/Data/stamps.json`
2. Run `node migrate_to_firebase.js`
3. Restart app

## Firebase Console Access

### Firestore Database
https://console.firebase.google.com/project/stampbook-app/firestore/data

View/edit:
- `stamps` collection (37+ stamps)
- `collections` collection
- `stamp_statistics` collection
- `users` collection
- `feed_posts` collection

### Storage
https://console.firebase.google.com/project/stampbook-app/storage

Folders:
- `stamps/` - Stamp images (6 uploaded so far)
- `users/{userId}/photos/` - User-uploaded photos

### Authentication
https://console.firebase.google.com/project/stampbook-app/authentication

Current users:
- hiroo (developer)
- watagumostudio (test user)

## Cost Monitoring

### Current Usage (Free Tier - Spark Plan)

#### Firestore (Free Limits)
- Stored data: 1 GB
- Document reads: 50K/day
- Document writes: 20K/day
- Document deletes: 20K/day

**Current usage**: Well within limits (<100 users)

#### Storage (Free Limits)
- Stored data: 5 GB
- Downloads: 1 GB/day
- Uploads: 1 GB/day

**Current usage**: Minimal

#### Authentication (Free Limits)
- Phone auth: 10K/month (not using)
- Email auth: Unlimited

### When to Upgrade to Blaze Plan

Consider upgrading when:
- 100+ active daily users
- Storage costs >$5/month
- Need Cloud Functions
- Need scheduled backups

## Troubleshooting

### App shows "Using offline data"
**Cause**: Firebase can't connect or database is empty

**Fix:**
1. Check internet connection
2. Verify `migrate_to_firebase.js` ran successfully
3. Check Firebase Console → Firestore has data

### "Permission denied" errors
**Cause**: Security rules not deployed

**Fix:**
```bash
cd /Users/haoyama/Desktop/Developer/Stampbook
firebase deploy --only firestore:rules
```

### Images not loading
**Cause**: Storage rules or images not uploaded

**Fix:**
1. Check Firebase Console → Storage → `stamps/` folder exists
2. Verify Storage rules deployed
3. Check image URLs in Firestore stamp documents

### Slow first load (14-17s)
**Cause**: Firebase cold start (normal behavior)

**Solution**: This is expected. Post-MVP: implement local caching.

## Backup & Recovery

### Exporting Data

```bash
# Export Firestore data
gcloud firestore export gs://stampbook-app-backups/$(date +%Y%m%d)

# Or use Firebase Console:
# Settings → Backups → Export Data
```

### Restoring Data

```bash
# Re-run migration script
node migrate_to_firebase.js

# This is safe - won't duplicate data
```

## Security Best Practices

### ✅ Current Security Measures
- Email/password auth only (no OAuth yet)
- All writes require authentication
- User data isolated by userId
- Stamp data read-only from app
- Storage URLs are public (stamps are public content)

### 🔒 Future Security Enhancements (Post-MVP)
- Email verification on sign-up
- OAuth providers (Google, Apple)
- Rate limiting on writes
- Admin SDK for stamp management
- Automated backups

## Service Account (For Scripts)

### Setup (Already Done)
1. Firebase Console → Project Settings → Service Accounts
2. Generated `serviceAccountKey.json`
3. Placed in project root (gitignored)

### Used By
- `migrate_to_firebase.js` - Data migration
- `upload_stamps_to_firestore.js` - Legacy script
- Future admin scripts

## Firebase CLI

### Installation
```bash
npm install -g firebase-tools
firebase login
```

### Common Commands
```bash
# Deploy rules
firebase deploy --only firestore:rules
firebase deploy --only storage:rules

# Test locally
firebase emulators:start

# View logs
firebase functions:log
```

## Monitoring

### Real-Time Monitoring
Firebase Console → Analytics (when enabled)

### Usage Dashboard
Firebase Console → Usage and billing

### Current Metrics (MVP)
- Active users: 2 (hiroo, watagumostudio)
- Daily reads: ~100-500
- Daily writes: ~20-50
- Storage: ~50 MB

---

**Last Updated**: November 3, 2025
**Status**: ✅ Configured and Production-Ready

