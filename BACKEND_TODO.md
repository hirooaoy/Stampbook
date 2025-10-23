# Backend Integration Checklist

## Current State
- ✅ Local JSON for stamp/collection data
- ✅ UserDefaults for user's collected stamps
- ✅ Clean separation: StampsManager & UserStampCollection
- ✅ Stable IDs (perfect for database keys)

## When Ready for Backend

### 1. Authentication (2-3 hours)
- [ ] Choose provider: Firebase Auth, Supabase Auth, or Apple Sign In
- [ ] Create AuthManager.swift
- [ ] Add sign in/sign out UI
- [ ] Gate ContentView behind auth check in StampbookApp.swift
- [ ] Add userId to CollectedStamp model

### 2. Cloud Data Sync (2-4 hours)
- [ ] Set up database (Firestore, Supabase, etc.)
- [ ] Create UserDataService protocol
- [ ] Implement cloud version of UserDataService
- [ ] Replace UserDefaults sync with cloud sync in UserStampCollection
- [ ] Handle merge conflicts (local vs cloud data)

### 3. Global Stamps/Collections (1-2 hours)
- [ ] Move stamps.json & collections.json to database
- [ ] Update StampsManager.loadStamps() to fetch from API
- [ ] Add caching layer for offline support
- [ ] Consider CDN for stamp images

### 4. Optional Enhancements
- [ ] User profile data (name, avatar, preferences)
- [ ] Photo uploads (user photos at stamp locations)
- [ ] Social features (friends, sharing stamps)
- [ ] Leaderboards/achievements
- [ ] Push notifications (new stamps nearby)

## Recommended Stack
**Easy & Fast:** Firebase (Auth + Firestore + Storage)
- Best for vibe coding
- Free tier is generous
- Well documented

**Alternative:** Supabase (similar features, open source)

## Key Files to Modify
1. `StampbookApp.swift` - Add auth wrapper
2. `StampsManager.swift` - Change load methods to API calls
3. `UserStampCollection.swift` - Add cloud sync
4. Create new: `Services/AuthManager.swift`
5. Create new: `Services/UserDataService.swift`

## Notes
- Keep UserDefaults for offline-first behavior
- Sync to cloud in background
- Your current architecture is perfect for this transition

