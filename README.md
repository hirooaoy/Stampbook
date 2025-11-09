# Stampbook iOS App 📍

Location-based stamp collecting app for iOS. Discover and collect digital stamps at real-world locations, share your adventures, and connect with other collectors.

## 🎯 Current Status

**Production-ready MVP** for <100 users. All critical issues resolved, code is clean and performant.

### Test Users
- **hiroo** - Developer account
- **watagumostudio** - Test account

## 📱 Features

### Core Features (MVP)
- 🗺️ Interactive map with stamp locations
- 📍 GPS-based stamp collection (100m radius)
- 📸 Photo uploads for collected stamps
- 👤 User profiles with stamp collections
- 📰 Social feed (All / Only You tabs)
- ❤️ Like & comment on posts
- 👥 Following system
- 🔍 User search

### Coming Post-MVP
- 🏆 Rank system
- 💼 Business pages
- 🎨 Creator pages
- ℹ️ About page

## 🏗️ Tech Stack

- **Language**: Swift 5.0
- **Platform**: iOS 26.0+
- **Backend**: Firebase (Firestore, Storage, Auth)
- **Architecture**: SwiftUI with MVVM pattern
- **Concurrency**: Swift Concurrency (async/await, actors)

## 🏛️ Architecture

### Core Managers

**AuthManager** (`Services/AuthManager.swift`)
- Handles Apple Sign In and Firebase Authentication
- Manages auth state only (userId, isSignedIn, isCheckingAuth)
- Coordinates with ProfileManager for profile loading
- **Not** responsible for profile data (that's ProfileManager's job)

**ProfileManager** (`Managers/ProfileManager.swift`)
- Single source of truth for user profiles
- Manages currentUserProfile with follower/following counts
- Handles profile loading, updating, and caching
- Posts notifications when profile updates (invalidates caches)

**StampsManager** (`Managers/StampsManager.swift`)
- Manages all stamp-related state and operations
- Handles stamp collection, validation, and distance calculations
- Updates user stats (totalStamps, totalCountries)
- Collection radius: 150m (configurable in AppConfig)

**FirebaseService** (`Services/FirebaseService.swift`)
- Central hub for all Firebase operations (Firestore + Storage)
- Provides clean API for other managers
- Handles connectivity diagnostics and error handling
- ~1400 lines (consider splitting by domain post-MVP)

**InviteManager** (`Managers/InviteManager.swift`)
- Validates invite codes
- Creates accounts atomically (auth + profile in transaction)
- Prevents race conditions with invite code usage

### Key Flows

**Sign Up Flow:**
1. User enters invite code in InviteCodeSheet
2. InviteManager validates code exists and has available uses
3. User signs in with Apple (AuthManager)
4. InviteManager creates Firestore profile atomically
5. ProfileManager loads the new profile
6. User enters app

**Sign In Flow (Returning User):**
1. App launches → AuthManager checks Firebase Auth state
2. If authenticated, loads profile via ProfileManager
3. Profile data flows to all views via @EnvironmentObject
4. If orphaned auth (no profile), signs user out

**Stamp Collection:**
1. User taps "Collect" within 150m of stamp
2. StampsManager validates distance and checks if already collected
3. Creates collection record in Firestore
4. Uploads optional photo to Firebase Storage
5. Updates user profile counts (totalStamps, totalCountries)
6. Optimistic UI update + background sync

### Configuration

**AppConfig.swift** - All constants in one place:
- `stampCollectionRadius: 150.0` meters
- `usernameRandomNumberRange: 10000...99999`
- `defaultInvitesPerUser: 0` (Phase 1, will be 5 in Phase 2)
- `feedPageSize: 20`
- `targetUserCount: 100` (MVP scale)
- `targetStampCount: 1000`

**Logger.swift** - Centralized logging:
- `Logger.debug()` - Development only (#if DEBUG)
- `Logger.info()` - State changes and flow tracking
- `Logger.warning()` - Recoverable issues
- `Logger.error()` - Failures with error context
- `Logger.success()` - Key milestones
- Use categories: `Logger.info("message", category: "ProfileManager")`

**AppErrors.swift** - Typed error enums:
- `StampError` - Collection issues (distance, permissions, already collected)
- `ProfileError` - Profile operations (update failed, username taken)
- `AuthError` - Authentication issues (sign in failed, network error)
- `SocialError` - Following, liking, commenting
- `NetworkError` - Connection issues, timeouts, rate limiting

### Data Flow

```
User Action → View → Manager → FirebaseService → Firestore/Storage
                ↓
          @Published vars → SwiftUI automatic refresh
```

**Example: Collecting a Stamp**
```
MapView → StampsManager.collectStamp()
          ↓
       Validates distance (150m)
          ↓
       FirebaseService.createStampCollection()
          ↓
       Updates @Published collectedStamps
          ↓
       UI automatically refreshes
```

### Performance Optimizations

- **Multi-layer caching**: Memory → Disk → Network (Instagram pattern)
- **Optimistic UI updates**: Instant feedback, sync in background
- **Request deduplication**: Prevents duplicate network calls
- **Parallel uploads**: 4x faster photo uploads
- **Offline persistence**: Firebase Firestore cache for offline usage

### MVP Scale (100 users, 1000 stamps)

Design decisions optimized for small scale:
- Fetch follower/following counts on-demand (not denormalized)
- No pagination for user's stamp collection
- Simple feed loading (can optimize post-MVP)
- Manual admin scripts (no admin panel yet)

Post-MVP scaling improvements documented but not implemented.

## 📚 Documentation

- **[Current Status](docs/CURRENT_STATUS.md)** - App state, features, and metrics
- **[Adding Stamps](docs/ADDING_STAMPS.md)** - How to add new stamp locations
- **[Firebase Setup](docs/FIREBASE_SETUP.md)** - Backend configuration guide
- **[Code Structure](docs/CODE_STRUCTURE.md)** - Architecture and code organization
- **[Security Policy](SECURITY.md)** - Security guidelines and reporting

## 🚀 Quick Start

### Prerequisites
- Xcode 26.0+
- Node.js (for migration scripts)
- Firebase CLI
- iOS device or simulator

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd Stampbook
   ```

2. **Install dependencies**
   ```bash
   npm install firebase-admin
   ```

3. **Configure Firebase**
   - Add `GoogleService-Info.plist` to Xcode project
   - Add `serviceAccountKey.json` to project root (for migration scripts)

4. **Upload initial data**
   ```bash
   node migrate_to_firebase.js
   ```

5. **Open in Xcode**
   ```bash
   open Stampbook.xcodeproj
   ```

6. **Build and run** (⌘R)

## 📍 Adding New Stamps

Quick workflow:

```bash
# 1. Edit stamps.json with new stamp data
code Stampbook/Data/stamps.json

# 2. Run migration script
node migrate_to_firebase.js

# 3. Restart app → new stamps appear!
```

**Important**: Always use exact GPS coordinates from Google Maps pin drops with 8+ decimal places. The app has a 100-meter collection radius, so precision is critical.

See [Adding Stamps Guide](docs/ADDING_STAMPS.md) for detailed instructions.

## 🗂️ Project Structure

```
Stampbook/
├── Managers/          # Business logic & state management
├── Services/          # Firebase and external services
├── Models/            # Data models
├── Views/             # SwiftUI views
├── Data/              # JSON data files (stamps, collections)
└── Assets.xcassets    # Images and colors

docs/                  # Documentation
├── CURRENT_STATUS.md  # Current app state
├── ADDING_STAMPS.md   # Stamp addition guide
├── FIREBASE_SETUP.md  # Backend setup
├── CODE_STRUCTURE.md  # Architecture docs
└── archive/           # Historical implementation notes

Scripts:
├── migrate_to_firebase.js       # Data migration script
└── fix_comment_counts.js        # Utility script
```

## 🔥 Firebase Services

### Firestore Collections
- `stamps` - Stamp locations and metadata
- `collections` - Stamp groupings
- `stamp_statistics` - Collector counts
- `users` - User profiles and collected stamps
- `feed_posts` - Social feed posts

### Storage
- `stamps/` - Stamp images
- `users/{userId}/photos/` - User-uploaded photos

### Current Plan
- **Spark (Free tier)** - Supports 100+ users
- Well within all limits

## 📊 Code Quality

- **Total Lines**: ~15,000 Swift
- **Linter Errors**: 0
- **Force Unwraps**: 0
- **Memory Leaks**: 0
- **Test Coverage**: Manual testing (2 test users)

## 🎨 Design Patterns

- **Optimistic UI Updates** - Instant feedback
- **Multi-Layer Caching** - Memory + Disk + Network
- **Request Deduplication** - Prevent duplicate fetches
- **Parallel Uploads** - 4x faster photo uploads
- **Instagram-Pattern Loading** - Disk cache → instant perceived speed

## 🐛 Known Issues

None! All critical bugs resolved as of November 3, 2025.

### Performance Notes
- First launch: 14-17 seconds (Firebase cold start - normal)
- Subsequent launches: <3 seconds
- Post-MVP: Will add local caching for faster cold starts

## 🤝 Contributing

This is currently a private MVP project with 2 test users.

## 📄 License

All rights reserved.

## 🔐 Security

See [SECURITY.md](SECURITY.md) for security policy and vulnerability reporting.

---

**Built with ❤️ by hiroo**  
**Last Updated**: November 3, 2025  
**Version**: 1.0 (MVP)

