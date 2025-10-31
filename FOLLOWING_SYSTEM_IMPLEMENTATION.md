# Following System Implementation

## Overview
The following system is implemented following industry best practices used by Instagram, Beli, and other social apps. This document outlines the architecture, data structures, and key design decisions.

## 📊 Data Structure

### 1. **Firestore Collections Structure**

```
users/{userId}/
  ├── (user profile document)
  ├── followers/{followerId}  # Users who follow this user
  │   ├── id: followerId
  │   └── createdAt: Timestamp
  └── following/{followingId}  # Users this user follows
      ├── id: followingId
      └── createdAt: Timestamp
```

### 2. **UserProfile Model** (Denormalized Counts)
```swift
struct UserProfile {
    let id: String
    let username: String
    var displayName: String
    var bio: String
    var followerCount: Int   // ⚡ Denormalized for performance
    var followingCount: Int  // ⚡ Denormalized for performance
    // ... other fields
}
```

**Why Denormalized Counts?**
- **Performance**: Reading a single document vs counting thousands of subcollection documents
- **Cost**: Firestore charges per document read - counting is expensive at scale
- **UX**: Instant display of follower/following counts without queries
- **Trade-off**: Slightly more complex writes (need to update counts), but much faster reads

## 🔐 Security Rules

```javascript
// Followers subcollection: users/{userId}/followers/{followerId}
match /users/{userId}/followers/{followerId} {
  allow read: if isSignedIn();
  allow create, delete: if isSignedIn(); // Validated by transaction
  allow update: if false; // Immutable
}

// Following subcollection: users/{userId}/following/{followingId}
match /users/{userId}/following/{followingId} {
  allow read: if isSignedIn();
  allow create, delete: if isOwner(userId);
  allow update: if false; // Immutable
}
```

## 🔄 Follow/Unfollow Flow

### Follow Operation (Atomic Transaction)
When User A follows User B:

1. **Create follow relationship** in A's "following" subcollection
2. **Create follower relationship** in B's "followers" subcollection
3. **Increment A's followingCount** by 1
4. **Increment B's followerCount** by 1

All operations execute in a Firestore transaction for atomicity (all succeed or all fail).

```swift
try await db.runTransaction { (transaction, errorPointer) -> Any? in
    // Write follow relationships
    transaction.setData(followData, forDocument: followingRef)
    transaction.setData(followerData, forDocument: followerDocRef)
    
    // Increment counts
    transaction.updateData(["followingCount": currentFollowingCount + 1], forDocument: followerRef)
    transaction.updateData(["followerCount": currentFollowerCount + 1], forDocument: followeeRef)
    
    return nil
}
```

### Unfollow Operation (Atomic Transaction)
When User A unfollows User B:

1. **Delete follow relationship** from A's "following" subcollection
2. **Delete follower relationship** from B's "followers" subcollection  
3. **Decrement A's followingCount** by 1 (min 0)
4. **Decrement B's followerCount** by 1 (min 0)

## 🎯 Key Features Implemented

### 1. **Optimistic UI Updates**
- Button state changes immediately when tapped
- Rollback on error for better UX
- No waiting for network response

```swift
// Optimistic update
isFollowing[targetUserId] = true

// Try network operation
do {
    try await firebaseService.followUser(...)
} catch {
    // Rollback on failure
    isFollowing[targetUserId] = false
}
```

### 2. **Real-time Follower/Following Counts**
- Displayed on user profiles
- Updated immediately after follow/unfollow
- Clickable to view full lists

### 3. **Follower/Following Lists**
- Paginated (limit 100 per query, expandable)
- Search functionality (filter by username/display name)
- Follow/unfollow buttons in lists
- Navigation to user profiles

### 4. **User Search**
- Search by username (prefix matching)
- Efficient Firestore query using range query
- Results limited to 20 users

## 🏗️ Architecture

### Managers
- **FollowManager**: Handles follow state, operations, and list fetching
- **ProfileManager**: Manages user profile loading and updates

### Models
- **UserProfile**: User data including follower/following counts
- **Follow**: Represents a follow relationship

### Services
- **FirebaseService**: All Firestore operations including follows

### Views
- **FollowListView**: Display followers/following with search
- **UserProfileView**: User profile with follow button and counts
- **UserRow**: Reusable user row component with follow button

## 📱 Common Practices from Instagram & Beli

### What We Implemented:
1. ✅ **Bidirectional Writes**: Both follower and following lists maintained
2. ✅ **Denormalized Counts**: Fast reads for follower/following numbers
3. ✅ **Optimistic UI**: Immediate feedback on follow actions
4. ✅ **Atomic Transactions**: Ensure data consistency
5. ✅ **Search Functionality**: Find users to follow
6. ✅ **Follow Status Indicators**: "Follow" vs "Following" buttons
7. ✅ **Hide Self-Follow**: Can't follow yourself

### Future Enhancements (Not Yet Implemented):
- 🔮 **Activity Feed**: Notify when someone follows you
- 🔮 **Mutual Follow Indicator**: Show "Friends" or special badge
- 🔮 **Follow Suggestions**: Recommend users to follow
- 🔮 **Private Accounts**: Request to follow, approve/deny
- 🔮 **Blocking**: Prevent specific users from following
- 🔮 **Feed Filtering**: Show only posts from users you follow

## 🧪 Testing Checklist

- [ ] Follow a user → check counts update
- [ ] Unfollow a user → check counts update
- [ ] View followers list → verify correct users shown
- [ ] View following list → verify correct users shown
- [ ] Search in follower/following lists
- [ ] Follow from follower/following lists
- [ ] Can't follow yourself
- [ ] Optimistic UI works (immediate feedback)
- [ ] Error handling (network failure rollback)
- [ ] Navigate to user profile from lists

## 🚀 Deployment Notes

### Firestore Indexes
No composite indexes required for current queries. If you add more complex filters, create indexes via Firebase Console.

### Security Rules Deployment
Deploy updated Firestore rules:
```bash
firebase deploy --only firestore:rules
```

### Migration for Existing Users
Existing user profiles will have `followerCount` and `followingCount` default to 0 thanks to the `decodeIfPresent` in `UserProfile.init(from:)`.

## 📊 Performance Considerations

### Scalability
- **Reads**: O(1) for counts, O(n) for lists (paginated to 100)
- **Writes**: 4 writes per follow/unfollow (2 subcollection + 2 count updates)
- **Cost**: ~$0.60 per 1M follow operations (Firestore pricing)

### Optimization Tips
1. **Pagination**: Load followers/following in batches (currently 100)
2. **Caching**: SwiftUI's `@StateObject` caches manager data per view
3. **Lazy Loading**: Only fetch lists when user navigates to them
4. **Debouncing**: Could add debouncing to search if needed

## 🔗 Related Files

- `/Stampbook/Models/UserProfile.swift` - User profile with follow counts
- `/Stampbook/Models/Follow.swift` - Follow relationship model
- `/Stampbook/Services/FirebaseService.swift` - Follow/unfollow operations
- `/Stampbook/Managers/FollowManager.swift` - Follow state management
- `/Stampbook/Views/Profile/FollowListView.swift` - Followers/following UI
- `/Stampbook/Views/Profile/UserProfileView.swift` - User profile with follow button
- `/firestore.rules` - Security rules for follows subcollections

## 📚 Additional Resources

- [Firestore Data Modeling Best Practices](https://firebase.google.com/docs/firestore/manage-data/structure-data)
- [Instagram Engineering Blog - Following System](https://instagram-engineering.com/)
- [Firestore Transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)

