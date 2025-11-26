# Bookmark Feature Implementation

## Overview
Implemented a complete bookmark feature that allows users to save stamps for later. Bookmarks are synced across devices via Firebase and displayed with yellow pins on the map.

## Implementation Date
November 25, 2025

## Components Created

### 1. Data Models
**File:** `Stampbook/Models/UserBookmarkCollection.swift`
- `BookmarkedStamp` struct: Stores `stampId`, `userId`, and `bookmarkedDate`
- `UserBookmarkCollection` class: Manages local + Firebase sync for bookmarks
- Methods: `addBookmark()`, `removeBookmark()`, `isBookmarked()`
- Follows same pattern as `UserStampCollection` for consistency

### 2. Firebase Integration
**File:** `Stampbook/Services/FirebaseService.swift`
- `fetchBookmarkedStamps()`: Loads user's bookmarks from Firestore
- `saveBookmarkedStamp()`: Saves bookmark to Firestore
- `deleteBookmarkedStamp()`: Removes bookmark from Firestore
- Storage path: `/users/{userId}/bookmarkedStamps/{stampId}`

### 3. Manager Updates
**File:** `Stampbook/Managers/StampsManager.swift`
- Added `userBookmarks: UserBookmarkCollection` published property
- New methods:
  - `isBookmarked(_ stampId: String) -> Bool`
  - `bookmarkStamp(_ stampId: String, userId: String)`
  - `unbookmarkStamp(_ stampId: String, userId: String)`
  - `toggleBookmark(_ stampId: String, userId: String)`
- Integrated with existing `setCurrentUser()` to sync bookmarks on sign-in

### 4. UI Components

#### StampPin (Map Pins)
**File:** `Stampbook/Views/Map/StampPin.swift`
- Added `isBookmarked: Bool` parameter
- **Yellow pin** with white bookmark icon for bookmarked stamps
- Priority order: Collected (green) > Bookmarked (yellow) > In-range (blue) > Locked (white)
- Updated MapView to pass bookmark status to all pins

#### StampDetailView (Bookmark Button)
**File:** `Stampbook/Views/Shared/StampDetailView.swift`
- Added bookmark button in toolbar **left of triple dot menu**
- Shows filled bookmark (yellow) when bookmarked
- Shows outline bookmark (gray) when not bookmarked
- Tapping toggles bookmark status instantly

#### StampsView (Bookmarks Card)
**File:** `Stampbook/Views/Profile/StampsView.swift`
- Added Bookmarks card **before Countries card** (leftmost position)
- Yellow bookmark icon with count
- Tappable - navigates to BookmarksView
- Same styling as other stat cards (160px width, 70px height)

#### BookmarksView (Bookmarks Grid)
**File:** `Stampbook/Views/Profile/BookmarksView.swift`
- Grid layout similar to "Your Stamps" view
- Shows all bookmarked stamps sorted by bookmark date (latest first)
- Lazy loading (20 at a time for performance)
- Pull-to-refresh support
- Empty state with helpful message
- Green checkmark badge on collected stamps
- Skeleton loading state

## Firebase Structure

```
users/
  {userId}/
    bookmarkedStamps/          <-- New subcollection
      {stampId}/
        - stampId: String
        - userId: String
        - bookmarkedDate: Timestamp
```

## User Flow

### Bookmarking a Stamp
1. User opens stamp detail
2. Taps bookmark icon (outline → filled yellow)
3. Stamp instantly bookmarked locally
4. Syncs to Firebase in background
5. Pin turns yellow on map

### Unbookmarking
1. Tap filled bookmark icon (filled → outline)
2. Stamp instantly unbookmarked locally
3. Syncs to Firebase in background
4. Pin returns to normal color

### Viewing Bookmarks
1. Navigate to Profile tab
2. Tap Bookmarks card (yellow bookmark icon)
3. See grid of all bookmarked stamps
4. Tap any stamp to view details
5. Can bookmark/unbookmark from detail view

## Pin Color Priority

1. **Green** - Collected (highest priority)
2. **Yellow** - Bookmarked
3. **Blue** - In range (uncollected)
4. **White** - Locked (too far away)

If a stamp is both collected AND bookmarked, it shows green (collected takes priority).

## Features

### ✅ Implemented
- Bookmark/unbookmark stamps instantly
- Yellow pins on map for bookmarked stamps
- Bookmarks card on profile with count
- Dedicated bookmarks grid view
- Firebase sync (works across devices)
- Offline support (local caching)
- Pull-to-refresh
- Lazy loading for performance
- Empty state
- Collected badge on bookmarked stamps

### Technical Details
- **Local Storage:** UserDefaults (instant access)
- **Cloud Storage:** Firestore (cross-device sync)
- **Sync Pattern:** Optimistic updates (instant UX, background sync)
- **Cache:** Bookmarks load on sign-in, cached locally
- **Performance:** Lazy loading (20 stamps at a time)

### Cost Estimate (per 100 users)
- Reads: ~5,000/month = **$0.08/month**
- Writes: ~1,000/month = **$0.11/month**
- **Total: ~$0.19/month**

## Use Cases

1. **Trip Planning** - Bookmark stamps in a city you're visiting
2. **Wish List** - Save stamps you want to collect someday
3. **Discovery** - Bookmark interesting places while browsing
4. **Organization** - Keep track of stamps to visit next

## Benefits

- **Quick Save** - One tap to bookmark for later
- **Visual Distinction** - Yellow pins stand out on map
- **Cross-Device** - Bookmarks follow you everywhere
- **Lightweight** - Minimal Firebase cost
- **Non-Intrusive** - Separate from "collected" status
- **Reversible** - Easy to bookmark/unbookmark

## Files Modified

1. `Stampbook/Models/UserBookmarkCollection.swift` (NEW)
2. `Stampbook/Views/Profile/BookmarksView.swift` (NEW)
3. `Stampbook/Services/FirebaseService.swift` (added bookmark methods)
4. `Stampbook/Managers/StampsManager.swift` (added bookmark management)
5. `Stampbook/Views/Map/StampPin.swift` (added yellow bookmark state)
6. `Stampbook/Views/Map/MapView.swift` (pass bookmark status to pins)
7. `Stampbook/Views/Shared/StampDetailView.swift` (added bookmark button)
8. `Stampbook/Views/Profile/StampsView.swift` (added bookmarks card)

## Testing Checklist

- [ ] Bookmark a stamp from detail view
- [ ] Verify yellow pin appears on map
- [ ] Check bookmark count updates on profile
- [ ] Open BookmarksView and see bookmarked stamp
- [ ] Unbookmark a stamp
- [ ] Verify yellow pin disappears
- [ ] Test with both collected and uncollected stamps
- [ ] Pull-to-refresh in BookmarksView
- [ ] Sign out and sign back in (bookmarks persist)
- [ ] Test empty state (no bookmarks)
- [ ] Test bookmark button on collected vs uncollected stamps

## Notes

- Bookmarks are **independent** of collection status
- You can bookmark before or after collecting
- Collected stamps show green pins (priority over yellow)
- Bookmarks sync automatically on app launch
- Works offline (syncs when online)
- No limit on number of bookmarks (consider adding 100-stamp limit in future)

## Future Enhancements (Post-MVP)

1. **Bulk Actions** - "Clear all bookmarks" button
2. **Smart Lists** - "Bookmarks near you" section
3. **Share Bookmarks** - Share your bookmark list with friends
4. **Collections** - Organize bookmarks into custom lists
5. **Limit** - Add 100-bookmark limit to prevent database bloat
6. **Analytics** - Track most-bookmarked stamps (valuable data!)
7. **Export** - Export bookmarks as map/list for trip planning

