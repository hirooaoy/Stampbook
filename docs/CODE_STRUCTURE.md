# Stampbook iOS - Code Structure

## Project Architecture

### Core Managers (`/Stampbook/Managers/`)

#### AuthManager
- User authentication & session management
- Firebase Auth integration
- Handles sign-in, sign-up, sign-out
- Publishes `isSignedIn`, `userId`, `isCheckingAuth`

#### StampsManager
- Stamp data loading from Firestore
- Collections management
- Stamp statistics (collectors count, rank)
- Caching & offline support
- Auto-refresh every 24 hours

#### FeedManager
- Feed post loading (All / Only You tabs)
- Disk cache for instant load
- Pagination support
- Post creation & deletion

#### ImageManager
- Multi-layer caching (LRU + disk + Firebase)
- Parallel uploads with TaskGroup
- Profile picture deduplication
- Instagram-pattern loading (disk → memory → network)
- Size variants (thumbnail, medium, full)

#### CommentManager
- Comment CRUD operations
- Real-time comment counts
- Manual document ID assignment (Firebase workaround)
- Optimistic UI updates

#### LikeManager
- Like/unlike operations
- Optimistic UI updates
- Request deduplication
- Cache management

### Services (`/Stampbook/Services/`)

#### FirebaseService
- Low-level Firestore operations
- User profile management
- Feed post queries
- Comment fetching
- Like operations
- Follow system

### Models (`/Stampbook/Models/`)

#### Core Models
- `Stamp` - Stamp locations, images, metadata
- `Collection` - Stamp collections (groupings)
- `StampStatistics` - Collector counts, rankings
- `CollectedStamp` - User-specific stamp data
- `FeedPost` - Social feed posts
- `Comment` - Post comments
- `Like` - Post likes
- `UserProfile` - User profile data

### Views (`/Stampbook/Views/`)

#### Main Tabs
- `MapView.swift` - Map with stamp pins
- `StampsView.swift` - User's collected stamps grid
- `FeedView.swift` - Social feed (910 lines)
- `SearchView.swift` - User search
- `ProfileView.swift` - Current user's profile

#### Detail Views
- `StampDetailView.swift` - Stamp details & collection
- `CollectionDetailView.swift` - Collection browser
- `UserProfileView.swift` - Other users' profiles
- `PostDetailView.swift` - Single post with comments

#### Shared Components
- `CachedImageView.swift` - Multi-mode cached images
- `ProfileImageView.swift` - User profile pictures
- `PhotoGalleryView.swift` - Photo viewer
- `CommentView.swift` - Comment display & actions

## Data Flow

### Stamp Collection Flow
1. User opens app → `MapView` loads
2. `StampsManager.loadStamps()` fetches from Firestore
3. Map displays stamp pins
4. User taps "Collect" → `StampsManager.collectStamp()`
5. Photo upload → `ImageManager.uploadImages()`
6. Updates Firestore: `users/{userId}/collected_stamps/{stampId}`
7. Updates `StampStatistics` (increment collectors)

### Feed Loading Flow
1. User opens Feed tab → `FeedView` appears
2. `FeedManager.loadDiskCache()` → instant display
3. `FeedManager.loadFeed()` → fetch fresh data
4. Parallel image loading via `ImageManager`
5. Disk cache updated for next launch

### Image Caching Flow
1. Request image via `CachedImageView`
2. Check LRU memory cache → instant return if hit
3. Check disk cache → ~50ms if hit
4. Download from Firebase Storage → save to caches
5. Prefetch related images in background

## Key Design Patterns

### Optimistic UI Updates
Used in: `LikeManager`, `CommentManager`, `FeedManager`
- Update UI immediately
- Send network request
- Rollback on failure

### Request Deduplication
Used in: `ProfileImageView`, `LikeManager`
- Track in-flight requests
- Prevent duplicate concurrent requests
- Share results across callers

### Instagram-Pattern Caching
Used in: `FeedManager`, `ImageManager`
- Disk cache for instant perceived load
- Fresh data loads in background
- Seamless cache swap

### Parallel Task Groups
Used in: `ImageManager` photo uploads
- Upload 4+ images simultaneously
- 4x speedup vs sequential
- Error handling per task

## Performance Optimizations

### Caching Layers
1. **Memory (LRU)**: 150 images, instant access
2. **Disk**: Unlimited, ~50ms access
3. **Network**: Firebase CDN, ~500ms

### Lazy Loading
- Feed images load on demand
- Profile pictures load on scroll
- Stamp images load on tab switch

### Prefetching
- Next 3 profile pictures while scrolling
- Related stamps when viewing details
- Feed images below fold

## Firebase Schema

```
firestore/
├── stamps/                          # Public read
│   └── {stampId}/
│       ├── id, name, lat, lon
│       ├── address, imageName
│       ├── collectionIds[]
│       └── about, notes[], thingsToDo[]
│
├── collections/                      # Public read
│   └── {collectionId}/
│       ├── id, name
│       └── description, region
│
├── stamp_statistics/                 # Authenticated write
│   └── {stampId}/
│       ├── totalCollectors
│       ├── collectorUserIds[]
│       └── lastUpdated
│
├── users/{userId}/
│   ├── profile                       # User's public profile
│   ├── collected_stamps/             # User's stamps
│   │   └── {stampId}/
│   ├── posts/                        # User's feed posts
│   │   └── {postId}/
│   └── following/                    # Who user follows
│
└── feed_posts/                       # Global feed
    └── {postId}/
        ├── userId, stampId
        ├── photoUrls[]
        ├── caption, timestamp
        ├── likeCount, commentCount
        └── isCollection
```

## Build Configuration

### Xcode Settings
- iOS Deployment Target: 26.0
- Swift Version: 5.0
- Actor Isolation: MainActor by default
- Concurrency: Approachable

### Dependencies
- Firebase Auth (11.0.0+)
- Firebase Firestore (11.0.0+)
- Firebase Storage (11.0.0+)

### Entitlements
- Push Notifications: No
- iCloud: No
- App Groups: No

## Testing

### Test Users
- **hiroo**: Developer/primary test account
- **watagumostudio**: True test account

### Manual Testing Flow
1. Sign in → Check auth state
2. View map → Check stamps load
3. Collect stamp → Check photo upload
4. View feed → Check posts load
5. Like/comment → Check interactions
6. View profile → Check stats

## Code Quality

### Current Metrics
- Total Swift files: ~40
- Total lines: ~15,000
- Linter errors: 0
- Force unwraps: 0
- Print statements: ~424 (appropriate for MVP)

### Best Practices
- ✅ All UI updates on MainActor
- ✅ Proper error handling
- ✅ Memory leak prevention
- ✅ Safe optional unwrapping
- ✅ DRY (no code duplication)

## Known Limitations (MVP)

### Performance
- First launch: 14-17s (Firebase cold start)
- Solution: Local profile caching (post-MVP)

### Scalability
- Current: <100 users
- Firebase Spark plan sufficient
- Ready for Blaze plan when needed

### Features Disabled
- Rank system (ready, but disabled)
- Business/Creator pages (marked POST-MVP)
- Share functionality (marked POST-MVP)

## Future Architecture Improvements

### When >100 Users
1. Implement local caching (CoreData/UserDefaults)
2. Add CDN (Cloudflare R2) for images
3. Implement OSLog for production logging
4. Extract large views into sub-components

### When Adding Features
1. Split `FeedView.swift` (910 lines)
2. Enable rank system with proper scaling
3. Add real-time Firestore listeners
4. Implement geohash queries (for 1000+ stamps)

---

**Last Updated**: November 3, 2025

