# Backend Integration Checklist

## Current State
- ✅ Local JSON for stamp/collection data
- ✅ UserDefaults for user's collected stamps
- ✅ Clean separation: StampsManager & UserStampCollection
- ✅ Stable IDs (perfect for database keys)
- ✅ Firebase configured (Auth, Firestore, Storage)
- ✅ Privacy-first location tracking (only for authenticated users)

## ⚠️ CRITICAL PRE-LAUNCH REQUIREMENTS

### 🚨 PRIVACY & LEGAL (BLOCKERS - Required for App Store approval)

#### 1. Privacy Policy & Terms of Service (1-2 hours)
- [ ] Create Privacy Policy webpage (or in-app view)
  - WHAT: Explain data collection (location, Apple ID, collected stamps)
  - WHY: Purpose is stamp collection functionality
  - WHERE: Firebase/Google Cloud servers (may include US data centers)
  - HOW LONG: Until account deletion
  - RIGHTS: Access, delete, export data
  - CONTACT: Email for GDPR requests
- [ ] Create Terms of Service
  - User agreement, acceptable use, liability
- [ ] Add Privacy Policy & ToS links to sign-in screens
  - FeedView.swift (line 80-100)
  - StampsView.swift (line 80-90)
  - StampDetailView.swift (line 404-418)
  - Format: "By signing in, you agree to our [Privacy Policy] and [Terms]"
- [ ] Add Privacy Policy URL to App Store Connect listing

#### 2. PrivacyInfo.xcprivacy Manifest (30 min)
- [ ] Create PrivacyInfo.xcprivacy file in Xcode
  - Required by Apple as of May 2024
  - Declare location data collection
  - Declare network usage
  - Declare tracking (set to false - we don't track)
  - See: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files

#### 3. Account Deletion Feature (1 hour)
- [ ] Add "Delete Account" button in profile settings
- [ ] Implement full deletion flow:
  1. Delete all collected stamps from Firestore
  2. Delete user document from Firestore
  3. Delete user from Firebase Auth
  4. Clear local UserDefaults
  5. Show confirmation & sign out
- [ ] Apple requires this for Apple Sign In apps (Review Guideline 5.1.1)
- [ ] Add to: StampsView.swift (profile menu)

#### 4. Data Export Feature (45 min)
- [ ] Add "Download My Data" button
- [ ] Export user's data as JSON:
  - All collected stamps
  - Collection dates
  - User notes
  - User metadata
- [ ] GDPR Right to Access requirement
- [ ] Use Share Sheet to let user save/email file

### 🔥 TECHNICAL BLOCKERS (Pre-Launch)

#### 5. Move Stamps to Firestore (2-3 hours)
**WHY CRITICAL:** Can't add new stamps without app updates
- [ ] Create Firestore collection: `stamps` (read-only for users)
- [ ] Create admin script to upload stamps.json to Firestore
- [ ] Update StampsManager.loadStamps() to fetch from Firestore
- [ ] Keep local stamps.json as fallback for offline
- [ ] Add timestamp field for "new stamp" badge
- [ ] Consider Firestore region (US vs EU for GDPR)

#### 6. Move Collections to Firestore (1 hour)
**WHY CRITICAL:** Same reason as stamps - need dynamic updates
- [ ] Create Firestore collection: `collections` (read-only)
- [ ] Upload collections.json to Firestore
- [ ] Update StampsManager.loadCollections() to fetch from Firestore
- [ ] Keep local fallback

#### 7. Move Stamp Images to Remote Storage (3-4 hours)
**WHY CRITICAL:** App will be 500MB+ with 100 stamps in Assets
- [ ] Options:
  - Firebase Storage (requires Blaze plan - paid)
  - CDN (Cloudflare R2, AWS S3 + CloudFront, Vercel Blob)
  - ImgIx or similar image optimization service
- [ ] Recommended: Cloudflare R2 ($0/month for 10GB) + CDN
- [ ] Add imageUrl field to Stamp model
- [ ] Implement AsyncImage with caching:
  - Use URLCache or third-party (Kingfisher, Nuke)
  - Cache images locally after first download
- [ ] Keep placeholder image in Assets for loading/error states
- [ ] Update all stamp image references in views

### ⚠️ IMPORTANT (Should Fix Before Launch)

#### 8. Error Handling & User Feedback (1 hour)
- [ ] Add @Published var syncError: String? to UserStampCollection
- [ ] Show alerts/banners when Firestore sync fails
- [ ] Add retry mechanism with exponential backoff
- [ ] Show sync status indicator ("Syncing...", "Synced", "Offline")
- [ ] Handle permission denied gracefully

#### 9. Loading States (30 min)
- [ ] Add @Published var isLoading: Bool to StampsManager
- [ ] Show loading spinner on first app launch while fetching stamps
- [ ] Show "Syncing..." when fetching collected stamps from Firestore
- [ ] Skeleton screens for stamp lists

#### 10. Network Monitor Integration (20 min)
- [ ] Already created NetworkMonitor.swift ✅
- [ ] Integrate into UserStampCollection
- [ ] Queue sync operations when offline
- [ ] Auto-retry when connection returns
- [ ] Show "Offline" banner (already in MapView ✅)

#### 11. User Profile Data in Firestore (1-2 hours)
- [ ] Create `/users/{userId}` document on first sign-in
- [ ] Fields:
  - displayName (from Apple Sign In)
  - bio (optional, user-editable)
  - avatarUrl (optional, from photo upload)
  - totalStamps (calculated)
  - createdAt timestamp
  - lastActiveAt timestamp
- [ ] Update UserProfileView to load from Firestore
- [ ] Add profile editing screen
- [ ] Rules already allow read/write ✅

#### 12. Firestore Security Rules Validation (30 min)
- [ ] Current rules are good ✅
- [ ] Add validation rules:
  - collectedDate must not be in future
  - userNotes max length (1000 chars to prevent spam)
  - stampId must exist in stamps collection
  - Prevent spam (rate limiting via client-side checks)
- [ ] Deploy rules: `firebase deploy --only firestore:rules`

## ✅ COMPLETED

### Authentication
- ✅ Apple Sign In implemented (AuthManager.swift)
- ✅ Firebase Auth integrated
- ✅ Sign-in UI in Feed, Stamps, StampDetail views
- ✅ Soft auth gate (users can browse, must sign in to collect)

### Cloud Data Sync  
- ✅ FirebaseService.swift created
- ✅ UserStampCollection syncs to Firestore
- ✅ Offline-first architecture (UserDefaults + Firestore)
- ✅ Optimistic updates (instant UI, background sync)
- ✅ Merge strategy for local vs cloud data

### Privacy & Location
- ✅ Privacy-first location tracking (only for authenticated users)
- ✅ LocationManager.swift updated with privacy controls
- ✅ MapView.swift only requests location after sign-in
- ✅ Location data cleared on sign-out
- ✅ GDPR Article 5 compliant (data minimization)

## 🔮 POST-LAUNCH (Nice to Have)

### Photo Uploads
- [ ] UI for photo upload in StampDetailView
- [ ] Compress images before upload (reduce size)
- [ ] Limit to 5 photos per stamp (cost control)
- [ ] Note: Requires Firebase Blaze plan (pay-as-you-go)
- [ ] Backend code already exists in FirebaseService.swift ✅

### Social Features
- [ ] Following/followers system
  - Firestore collections: `/users/{userId}/following`, `/followers`
- [ ] Feed showing friends' recent stamp collections
  - Real-time updates with Firestore listeners
- [ ] Like/comment on stamps
- [ ] Leaderboards (most stamps, most countries)
- [ ] Achievements/badges

### Advanced Features
- [ ] Push notifications
  - "New stamp nearby!" (location-based)
  - "Your friend collected a stamp"
  - Firebase Cloud Messaging
- [ ] Stamp categories/tags
- [ ] Custom user collections
- [ ] Stamp trading/gifting
- [ ] AR view for stamps (point camera at location)

### Analytics & Monitoring
- [ ] Firebase Analytics integration
- [ ] Track events:
  - Stamps collected
  - Sign-ups
  - Retention rate
  - Popular stamps/locations
- [ ] Crashlytics for error tracking
- [ ] Performance monitoring

## 📊 ESTIMATED TIME TO LAUNCH

**Critical (Must Have):**
- Privacy & Legal: 3-4 hours
- Technical Blockers: 6-8 hours
- **Total: 9-12 hours**

**Important (Should Have):**
- Error handling, loading states, network: 2.5 hours

**TOTAL ESTIMATE: 11-15 hours of focused work**

---

## 🚀 RECOMMENDED LAUNCH ORDER

1. **Week 1: Privacy & Legal** (4 hours)
   - Privacy Policy & Terms
   - PrivacyInfo.xcprivacy
   - Account deletion
   - Data export

2. **Week 2: Backend Migration** (8 hours)
   - Move stamps to Firestore
   - Move collections to Firestore
   - Move images to CDN/Storage
   - Test thoroughly

3. **Week 3: Polish & Launch** (3 hours)
   - Error handling
   - Loading states
   - Final testing
   - Submit to App Store

---

## 🎯 MINIMUM VIABLE LAUNCH

If you need to launch ASAP, bare minimum:

1. ✅ Privacy-first location (DONE)
2. ⚠️ Privacy Policy + Terms (1 hour)
3. ⚠️ PrivacyInfo.xcprivacy (30 min)
4. ⚠️ Account deletion (1 hour)

**Can defer:**
- Moving stamps/images to backend (use local for v1.0)
- Just add them via app updates for now
- Social features
- Analytics

**Minimum Time to Launch: 2.5 hours**

---

## 📝 NOTES

### Firestore Costs (Spark Plan - FREE)
- 1GB storage
- 10GB/month network egress
- 50K document reads/day
- 20K document writes/day
- **Estimate:** Free tier should support ~100 users easily

### When to Upgrade (Blaze Plan)
- Firebase Storage (not on free tier)
- More than 100 active users
- Photo uploads
- Push notifications
- Pay-as-you-go, but very cheap for small apps

### CDN Options for Images
1. **Cloudflare R2** - $0/month for 10GB, no egress fees ⭐ RECOMMENDED
2. **AWS S3 + CloudFront** - ~$5/month
3. **Vercel Blob** - Free tier available
4. **Firebase Storage** - Requires Blaze plan

---

## 🔗 USEFUL LINKS

- [Firebase Pricing](https://firebase.google.com/pricing)
- [Apple Privacy Guidelines](https://developer.apple.com/app-store/review/guidelines/#privacy)
- [GDPR Compliance Checklist](https://gdpr.eu/checklist/)
- [PrivacyInfo.xcprivacy Docs](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)

---

## ✅ CURRENT STATUS: 60% COMPLETE

**What's Done:**
- ✅ Auth & user management
- ✅ Cloud sync architecture
- ✅ Privacy-compliant location tracking
- ✅ Firestore rules
- ✅ Offline-first data model

**What's Blocking Launch:**
- ⚠️ Privacy policy & legal docs
- ⚠️ Account deletion
- ⚠️ PrivacyInfo.xcprivacy

**What Can Wait:**
- 🔮 Moving stamps/images to backend (can use local for v1.0)
- 🔮 Social features
- 🔮 Analytics

---

**NEXT STEP:** Create Privacy Policy & Terms → ~1 hour to unblock launch!

