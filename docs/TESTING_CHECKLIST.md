# Testing Checklist

## 🎯 Core User Flows

### 1. Authentication Flow
- [ ] **Sign In** - Tap "Sign in with Apple" from feed/welcome screen
  - [ ] Profile created correctly with username generation
  - [ ] User redirected to feed after sign in
  - [ ] Profile stats initialized (0 stamps, 0 countries)
- [ ] **Sign Out** - Menu → Sign out
  - [ ] Confirmation dialog appears
  - [ ] User data cleared from memory
  - [ ] Returns to welcome screen
- [ ] **App Launch (Signed In)** - Close and reopen app
  - [ ] No re-authentication required
  - [ ] Profile loads automatically
  - [ ] Stamp collection syncs from Firestore

### 2. Map View
- [ ] **Initial Load**
  - [ ] Map centers on Golden Gate Bridge (default)
  - [ ] All stamps load and display correctly
  - [ ] Pins render: grey (locked), blue (in range), green (collected)
- [ ] **Location Permission** (Signed In)
  - [ ] "Locate Me" button works
  - [ ] Blue dot appears at user location
  - [ ] Map centers on user
- [ ] **Location Permission** (Signed Out)
  - [ ] "Locate Me" button shows sign-in sheet
  - [ ] No location tracking occurs
- [ ] **Search**
  - [ ] Search button opens search sheet
  - [ ] Autocomplete suggestions appear
  - [ ] Selecting result centers map
- [ ] **Stamp Selection**
  - [ ] Tap stamp pin → detail sheet opens
  - [ ] Close detail sheet returns to map
  - [ ] Clusters expand when tapped (zoom in)
- [ ] **Clustering**
  - [ ] Pins cluster at high zoom levels
  - [ ] Green and grey pins cluster separately
  - [ ] Blue (in-range) pins never cluster
  - [ ] Cluster numbers correct

### 3. Stamp Collection
- [ ] **Welcome Stamp** (First Time)
  - [ ] Visible from anywhere (no location required)
  - [ ] "Collect Stamp" button enabled
  - [ ] Collection triggers welcome animation
  - [ ] Stats update: 1 stamp, 1 country
- [ ] **Location-Based Stamps**
  - [ ] "Too far" message when out of range
  - [ ] "Collect Stamp" button enabled when in range (150m)
  - [ ] Collection works instantly (optimistic update)
  - [ ] Memory section appears after collection
  - [ ] User rank displays correctly (#1, #2, etc.)
  - [ ] Collection date shows correctly
- [ ] **Stamp Detail View**
  - [ ] Name, image, about section visible
  - [ ] Collection count shows real data
  - [ ] Location section (address, map buttons)
  - [ ] Things to do section (if available)
  - [ ] Collections section (if stamp belongs to collections)
  - [ ] "Suggest an edit" menu works
- [ ] **Collections**
  - [ ] Collections display on stamp detail
  - [ ] Tap collection → collection detail view
  - [ ] Progress bars accurate
  - [ ] Completion percentage correct

### 4. Feed View
- [ ] **Signed Out State**
  - [ ] Welcome screen with app logo
  - [ ] "Sign in with Apple" button visible
  - [ ] Menu accessible (About, Share, etc.)
- [ ] **Signed In - "All" Tab**
  - [ ] Shows posts from followed users + self
  - [ ] Chronological order (newest first)
  - [ ] Pull-to-refresh works
  - [ ] Infinite scroll (loads more at bottom)
  - [ ] Empty state if not following anyone
- [ ] **Signed In - "Only Yours" Tab**
  - [ ] Shows only current user's stamps
  - [ ] Chronological order (newest first)
  - [ ] Pull-to-refresh works
  - [ ] Empty state if no stamps collected
- [ ] **Post Interactions**
  - [ ] Like button toggles (heart fills/unfills)
  - [ ] Like count increments/decrements
  - [ ] Comment button opens comment sheet
  - [ ] Tap profile pic → user profile (or Stamps tab for self)
  - [ ] Tap stamp name/image → stamp detail view
- [ ] **Photo Gallery**
  - [ ] Stamp image displays
  - [ ] User photos display (up to 5)
  - [ ] Tap photo → full screen view
  - [ ] Swipe between photos

### 5. Profile & Stamps Tab
- [ ] **Own Profile (Stamps Tab)**
  - [ ] Profile header shows correct stats
  - [ ] Avatar displays correctly
  - [ ] Edit button works
  - [ ] Segmented control (Collections/Stamps/Map)
  - [ ] Collections tab shows progress
  - [ ] Stamps tab shows grid of collected stamps
  - [ ] Map tab shows collected stamps on map
- [ ] **Profile Edit**
  - [ ] Change avatar (photo picker)
  - [ ] Edit display name
  - [ ] Edit username (validation, uniqueness check)
  - [ ] Edit bio
  - [ ] Save button updates profile
  - [ ] Cancel button discards changes
- [ ] **Other User Profile**
  - [ ] Access via feed → tap profile pic
  - [ ] Shows public profile info
  - [ ] Follow/Unfollow button works
  - [ ] Follower/Following counts update
  - [ ] Tap followers/following → lists
  - [ ] Share profile button (copies URL)

### 6. Social Features
- [ ] **Follow System**
  - [ ] Follow button → "Following" state
  - [ ] Unfollow button → "Follow" state
  - [ ] Counts update immediately
  - [ ] Feed updates with new user's posts
- [ ] **Likes**
  - [ ] Like persists across app restarts
  - [ ] Unlike removes like
  - [ ] Like count syncs with Firebase
  - [ ] View likers list (tap like count)
- [ ] **Comments**
  - [ ] Add comment → appears in list
  - [ ] Comment count increments
  - [ ] Delete own comments (swipe to delete)
  - [ ] Delete comments on own posts
  - [ ] Comments display with avatars
- [ ] **User Search**
  - [ ] Search icon opens search sheet
  - [ ] Type username → results appear
  - [ ] Tap result → user profile
  - [ ] Empty state for no results

### 7. Offline/Network Handling
- [ ] **Connection Lost**
  - [ ] "No Internet Connection" banner appears
  - [ ] Cached data still accessible
  - [ ] Map continues to work (cached stamps)
- [ ] **Connection Restored**
  - [ ] "Reconnecting..." banner appears briefly
  - [ ] Data syncs from Firebase
  - [ ] Banner disappears after 3 seconds
- [ ] **Firestore Persistence**
  - [ ] First load caches data
  - [ ] Subsequent loads instant (from cache)
  - [ ] Works fully offline after first load

## 🎨 UI/UX Testing

### Visual Polish
- [ ] **Dark Mode Support**
  - [ ] All screens adapt correctly
  - [ ] Text remains readable
  - [ ] Images/icons display correctly
- [ ] **Animations**
  - [ ] Stamp collection animation smooth
  - [ ] Memory section appears with spring animation
  - [ ] Tab switches smooth
  - [ ] Sheet presentations smooth
- [ ] **Loading States**
  - [ ] Skeleton posts show while loading feed
  - [ ] Progress indicators show during operations
  - [ ] Images load progressively (thumbnail → full res)
- [ ] **Error States**
  - [ ] Error messages display clearly
  - [ ] Retry options available
  - [ ] Graceful degradation (cached data shown)

### Edge Cases
- [ ] **Empty States**
  - [ ] No stamps collected
  - [ ] No followers/following
  - [ ] No search results
  - [ ] No comments/likes
- [ ] **Long Content**
  - [ ] Long stamp names wrap correctly
  - [ ] Long bios scroll/truncate
  - [ ] Long addresses wrap nicely
- [ ] **Special Characters**
  - [ ] Emojis in names/bios
  - [ ] Special characters in usernames
  - [ ] Non-English characters

## 🔐 Privacy & Permissions

- [ ] **Location Permission**
  - [ ] Only requested after sign in
  - [ ] Purpose clear in permission dialog
  - [ ] Can be denied and app still works
  - [ ] Denied → "Too far" for all stamps
- [ ] **Photo Library Permission**
  - [ ] Only requested when adding photos
  - [ ] Can be denied gracefully
  - [ ] "Limited Photos" selection supported
- [ ] **Tracking (App Tracking Transparency)**
  - [ ] No tracking required
  - [ ] App works without ATT permission

## 🚀 Performance

- [ ] **App Launch**
  - [ ] Launches in < 2 seconds
  - [ ] No blocking operations
  - [ ] Splash screen shows during auth check
- [ ] **Memory Usage**
  - [ ] No crashes during extended use
  - [ ] Images cache properly (LRU eviction)
  - [ ] Background memory reasonable (< 100MB)
- [ ] **Network Efficiency**
  - [ ] Firebase cache used effectively
  - [ ] Images cached locally
  - [ ] Pagination prevents over-fetching

## 📱 Device Testing

### Device Types
- [ ] iPhone 14 Pro / 15 Pro (6.1")
- [ ] iPhone 14 Pro Max / 15 Pro Max (6.7")
- [ ] iPhone SE (4.7" - small screen)
- [ ] iPad (if supported)

### iOS Versions
- [ ] iOS 18.2 (latest)
- [ ] iOS 17.0 (minimum supported)

## 🐛 Known Issues to Test

Based on recent changes:
- [ ] MapCoordinator navigation from StampDetail → Map tab
- [ ] Feed pull-to-refresh doesn't clear cached stats
- [ ] Profile stats reconciliation on app launch
- [ ] Follow/unfollow count updates
- [ ] Stamp rank caching and display

## ✅ Regression Testing (After Bug Fixes)

Things that were recently fixed and should be tested:
- [ ] Instagram-style feed pagination (chronological)
- [ ] Connection banner transitions
- [ ] Profile edit username validation
- [ ] Welcome stamp collection (no location)
- [ ] Stamp statistics real-time updates

## 📝 Notes

- **MVP Scale**: App is designed for 100 users, 1000 stamps
- **Firebase**: Uses persistent cache for offline support
- **Test Users**: "hiroo" (developer) and "watagumostudio" (test)
- **Focus Areas**: Core stamp collection flow, social features, offline behavior

---

## 🎯 Priority Testing Order

1. **Critical Path** (P0): Authentication, Stamp Collection, Feed
2. **Core Features** (P1): Profile, Social (Follow/Like/Comment), Search
3. **Polish** (P2): Offline, Animations, Edge Cases
4. **Nice-to-Have** (P3): Performance, Device variations

