# Account Deletion Plan - Stampbook iOS App

**Last Updated:** November 3, 2025  
**Status:** Planning Phase  
**Compliance:** GDPR, CCPA, Apple App Store Guidelines

## Overview

This document outlines the complete strategy for implementing account deletion in Stampbook. Account deletion is a critical privacy feature required by:
- **GDPR** (General Data Protection Regulation)
- **CCPA** (California Consumer Privacy Act)
- **Apple App Store Review Guidelines** (Section 5.1.1)

---

## Current Data Structure

### Firestore Collections

1. **`users/{userId}`** (User Profile)
   - `username`, `displayName`, `bio`, `avatarUrl`
   - `totalStamps`, `uniqueCountriesVisited`
   - `followerCount`, `followingCount`
   - `createdAt`, `lastActiveAt`, `usernameLastChanged`

2. **`users/{userId}/collected_stamps/{stampId}`** (User's Posts)
   - `stampId`, `userId`, `collectedDate`
   - `userNotes`, `userImageNames`, `userImagePaths`
   - `likeCount`, `commentCount`

3. **`users/{userId}/following/{followingId}`** (Following Relationships)
   - `id` (userId being followed)
   - `createdAt`

4. **`users/{userId}/followers/{followerId}`** (Follower Relationships)
   - `id` (userId who is following)
   - `createdAt`

5. **`users/{userId}/blocked/{blockedId}`** (Blocked Users)
   - `id` (userId being blocked)
   - `createdAt`

6. **`likes/{likeId}`** (Format: `{userId}_{postId}`)
   - `userId`, `postId`, `stampId`, `postOwnerId`
   - `createdAt`

7. **`comments/{commentId}`**
   - `userId`, `postId`, `stampId`, `postOwnerId`
   - `text`, `userDisplayName`, `userUsername`, `userAvatarUrl`
   - `createdAt`

8. **`feedback/{feedbackId}`**
   - `userId`, `username`, `displayName`
   - `type`, `message`, `deviceInfo`
   - `timestamp`, `status`

9. **`stamp_statistics/{stampId}`** (Stamp Collector Stats)
   - `stampId`, `totalCollectors`
   - `collectorUserIds` (array)
   - `lastUpdated`

### Firebase Storage Paths

1. **Profile Pictures:**
   - `users/{userId}/profile_photo/{photoId}.jpg`

2. **Stamp Photos:**
   - `users/{userId}/stamp_photos/{stampId}_{photoId}.jpg`

### Firebase Authentication

- User authentication record in Firebase Auth
- Sign-in providers (Apple Sign-In)

### Local Storage (On-Device)

- `UserDefaults`:
  - `collectedStamps` (local copy for offline)
  - `pendingDeletions` (failed photo deletions)
- Image Cache (via `ImageManager`)
  - Profile pictures
  - Stamp photos

---

## Deletion Strategy

### Option A: Hard Delete (Recommended for MVP)

**Pros:**
- Complete data removal (GDPR/CCPA compliant)
- Simple to implement
- No ongoing storage costs
- Clean audit trail

**Cons:**
- Comments/likes from deleted users may cause orphaned references
- No recovery option (irreversible)

**Implementation:**
1. Delete ALL user data immediately
2. Handle orphaned data gracefully in UI
3. Show deleted user as "[Deleted User]" in comments

### Option B: Soft Delete (Future Enhancement)

**Pros:**
- Preserve comments/likes for context
- Grace period for recovery (30 days)
- Better UX for accidental deletions

**Cons:**
- More complex to implement
- Requires scheduled cleanup (Cloud Functions)
- Ongoing storage costs during grace period
- Need to hide "soft deleted" users in searches/feeds

---

## Implementation Plan (Hard Delete - MVP)

### Phase 1: Data Deletion Function

**Create new FirebaseService method:**

```swift
func deleteUserAccount(userId: String) async throws {
    // 1. Delete collected stamps subcollection
    // 2. Delete following subcollection
    // 3. Delete followers subcollection
    // 4. Delete blocked subcollection
    // 5. Delete likes where userId matches
    // 6. Delete comments where userId matches
    // 7. Delete feedback where userId matches
    // 8. Update stamp_statistics (remove from collectorUserIds)
    // 9. Delete Firebase Storage images
    // 10. Delete user profile document
    // 11. Delete Firebase Auth account
}
```

### Phase 2: Batch Deletion Logic

**Firestore Batch Operations:**
- Firestore allows max 500 operations per batch
- Need to handle subcollections with pagination
- Use parallel deletion for better performance

**Key Considerations:**
- Subcollections are NOT automatically deleted when parent is deleted
- Must explicitly delete each subcollection document
- Use batch writes for atomicity (all-or-nothing)

### Phase 3: Storage Cleanup

**Profile Picture Deletion:**
```swift
// Delete from: users/{userId}/profile_photo/
let profileRef = storage.reference().child("users/\(userId)/profile_photo")
let allPhotos = try await profileRef.listAll()
for item in allPhotos.items {
    try await item.delete()
}
```

**Stamp Photos Deletion:**
```swift
// Delete from: users/{userId}/stamp_photos/
let stampPhotosRef = storage.reference().child("users/\(userId)/stamp_photos")
let allPhotos = try await stampPhotosRef.listAll()
for item in allPhotos.items {
    try await item.delete()
}
```

### Phase 4: Denormalized Data Cleanup

**Update Follower/Following Counts:**
- When deleting user's followers → decrement each follower's `followingCount`
- When deleting user's following → decrement each followed user's `followerCount`
- Use Firestore transactions for consistency

**Update Post Engagement Counts:**
- When deleting user's likes → decrement `likeCount` on posts
- When deleting user's comments → decrement `commentCount` on posts

**Update Stamp Statistics:**
- Remove userId from `collectorUserIds` array
- Decrement `totalCollectors`

### Phase 5: Firebase Auth Deletion

```swift
// Must be last step (can't access Firestore after auth deletion)
let user = Auth.auth().currentUser
try await user?.delete()
```

**Important:** Auth deletion must happen LAST because:
- Firestore security rules check `request.auth.uid`
- After auth deletion, user can't access Firestore
- Need auth token to delete user's own data

### Phase 6: Orphaned Data Handling

**Comments from Deleted Users:**
- Option A (MVP): Show as "[Deleted User]" with placeholder avatar
- Option B: Delete all comments (harder to implement, less context)

**Implementation:**
```swift
// In CommentRow view:
if let username = comment.userUsername {
    Text("@\(username)")
} else {
    Text("[Deleted User]")
        .foregroundColor(.gray)
}
```

**Likes from Deleted Users:**
- Likes are just counts, no UI impact
- Already handled by decrementing counts during deletion

### Phase 7: Local Data Cleanup

```swift
// Clear UserDefaults
UserDefaults.standard.removeObject(forKey: "collectedStamps")
UserDefaults.standard.removeObject(forKey: "pendingDeletions")

// Clear image cache
ImageManager.shared.clearAllCachedImages()

// Clear AuthManager state
authManager.signOut()

// Clear BlockManager state
blockManager.clearBlockData()
```

---

## Detailed Implementation Steps

### Step 1: Add FirebaseService Method

```swift
/// Delete user account and all associated data
/// This is IRREVERSIBLE and removes:
/// - User profile
/// - All collected stamps
/// - All uploaded images
/// - All likes and comments
/// - All follows and followers
/// - All blocked relationships
/// - Firebase Auth account
func deleteUserAccount(userId: String) async throws {
    print("🗑️ [DELETE ACCOUNT] Starting deletion for user: \(userId)")
    
    // 1. DELETE SUBCOLLECTIONS
    
    // 1a. Delete collected_stamps subcollection
    print("🗑️ Deleting collected stamps...")
    try await deleteSubcollection(userId: userId, subcollection: "collected_stamps")
    
    // 1b. Delete following subcollection (and update followed users' followerCount)
    print("🗑️ Deleting following relationships...")
    let following = try await fetchFollowing(userId: userId, useCache: false)
    for followedUser in following {
        try await unfollowUser(followerId: userId, followeeId: followedUser.id)
    }
    
    // 1c. Delete followers subcollection (and update followers' followingCount)
    print("🗑️ Deleting follower relationships...")
    let followers = try await fetchFollowers(userId: userId)
    for follower in followers {
        try await unfollowUser(followerId: follower.id, followeeId: userId)
    }
    
    // 1d. Delete blocked subcollection
    print("🗑️ Deleting blocked users list...")
    try await deleteSubcollection(userId: userId, subcollection: "blocked")
    
    // 2. DELETE LIKES (top-level collection)
    print("🗑️ Deleting likes...")
    let likesQuery = db.collection("likes").whereField("userId", isEqualTo: userId)
    try await deleteBatchedDocuments(query: likesQuery)
    
    // 3. DELETE COMMENTS (top-level collection)
    print("🗑️ Deleting comments...")
    let commentsQuery = db.collection("comments").whereField("userId", isEqualTo: userId)
    try await deleteBatchedDocuments(query: commentsQuery)
    
    // 4. DELETE FEEDBACK (top-level collection)
    print("🗑️ Deleting feedback...")
    let feedbackQuery = db.collection("feedback").whereField("userId", isEqualTo: userId)
    try await deleteBatchedDocuments(query: feedbackQuery)
    
    // 5. UPDATE STAMP STATISTICS (remove from collectorUserIds)
    print("🗑️ Updating stamp statistics...")
    // Get all stamps user collected
    let userStamps = try await fetchCollectedStamps(for: userId)
    for stamp in userStamps {
        let statsRef = db.collection("stamp_statistics").document(stamp.stampId)
        try await statsRef.updateData([
            "collectorUserIds": FieldValue.arrayRemove([userId]),
            "totalCollectors": FieldValue.increment(Int64(-1))
        ])
    }
    
    // 6. DELETE FIREBASE STORAGE IMAGES
    print("🗑️ Deleting profile photos...")
    try await deleteStorageFolder(path: "users/\(userId)/profile_photo")
    
    print("🗑️ Deleting stamp photos...")
    try await deleteStorageFolder(path: "users/\(userId)/stamp_photos")
    
    // 7. DELETE USER PROFILE DOCUMENT (main document)
    print("🗑️ Deleting user profile...")
    try await db.collection("users").document(userId).delete()
    
    // 8. DELETE FIREBASE AUTH ACCOUNT (must be last!)
    print("🗑️ Deleting Firebase Auth account...")
    if let currentUser = Auth.auth().currentUser, currentUser.uid == userId {
        try await currentUser.delete()
    }
    
    print("✅ [DELETE ACCOUNT] Account deletion complete for user: \(userId)")
}

// Helper: Delete all documents in a subcollection
private func deleteSubcollection(userId: String, subcollection: String) async throws {
    let collectionRef = db.collection("users").document(userId).collection(subcollection)
    let snapshot = try await collectionRef.getDocuments()
    
    // Delete in batches (max 500 per batch)
    let batchSize = 500
    var batch = db.batch()
    var operationCount = 0
    
    for document in snapshot.documents {
        batch.deleteDocument(document.reference)
        operationCount += 1
        
        if operationCount >= batchSize {
            try await batch.commit()
            batch = db.batch()
            operationCount = 0
        }
    }
    
    // Commit remaining operations
    if operationCount > 0 {
        try await batch.commit()
    }
    
    print("✅ Deleted \(snapshot.documents.count) documents from \(subcollection)")
}

// Helper: Delete documents from top-level collection with query
private func deleteBatchedDocuments(query: Query) async throws {
    let snapshot = try await query.getDocuments()
    
    // Delete in batches (max 500 per batch)
    let batchSize = 500
    var batch = db.batch()
    var operationCount = 0
    
    for document in snapshot.documents {
        batch.deleteDocument(document.reference)
        operationCount += 1
        
        if operationCount >= batchSize {
            try await batch.commit()
            batch = db.batch()
            operationCount = 0
        }
    }
    
    // Commit remaining operations
    if operationCount > 0 {
        try await batch.commit()
    }
    
    print("✅ Deleted \(snapshot.documents.count) documents from query")
}

// Helper: Delete all files in a Storage folder
private func deleteStorageFolder(path: String) async throws {
    let folderRef = storage.reference().child(path)
    let result = try await folderRef.listAll()
    
    for item in result.items {
        try await item.delete()
    }
    
    print("✅ Deleted \(result.items.count) files from \(path)")
}
```

### Step 2: Add AuthManager Method

```swift
/// Delete the current user's account permanently
/// This is IRREVERSIBLE and will:
/// - Delete all user data from Firestore
/// - Delete all user images from Storage
/// - Delete Firebase Auth account
/// - Clear local data
/// - Sign out the user
func deleteAccount() async throws {
    guard let userId = userId else {
        throw NSError(domain: "AuthManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
    }
    
    print("⚠️ [DELETE ACCOUNT] Starting account deletion for user: \(userId)")
    
    // 1. Delete all user data from Firebase
    try await firebaseService.deleteUserAccount(userId: userId)
    
    // 2. Clear local data
    UserDefaults.standard.removeObject(forKey: "collectedStamps")
    UserDefaults.standard.removeObject(forKey: "pendingDeletions")
    imageManager.clearAllCachedImages()
    
    // 3. Sign out (this also clears AuthManager state)
    signOut()
    
    print("✅ [DELETE ACCOUNT] Account deletion complete")
}
```

### Step 3: Add Settings UI

Create a new view: `DeleteAccountView.swift`

```swift
import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    
    @State private var confirmationText: String = ""
    @State private var isDeleting: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    private let requiredText = "DELETE"
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("⚠️ Warning: This action cannot be undone!")
                            .font(.headline)
                            .foregroundColor(.red)
                        
                        Text("Deleting your account will permanently remove:")
                            .font(.subheadline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Your profile and username", systemImage: "person.crop.circle.badge.xmark")
                            Label("All your collected stamps", systemImage: "photo.stack")
                            Label("All your uploaded photos", systemImage: "photo.on.rectangle.angled")
                            Label("All your comments and likes", systemImage: "heart.slash")
                            Label("Your followers and following", systemImage: "person.2.slash")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To confirm deletion, type DELETE below:")
                            .font(.subheadline)
                        
                        TextField("Type DELETE", text: $confirmationText)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.allCharacters)
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    Button(role: .destructive) {
                        deleteAccount()
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Delete My Account Permanently")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(confirmationText != requiredText || isDeleting)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isDeleting)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func deleteAccount() {
        isDeleting = true
        
        Task {
            do {
                try await authManager.deleteAccount()
                
                await MainActor.run {
                    // Dismiss view and show success
                    dismiss()
                    // User is now signed out, will see sign-in screen
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
                print("❌ Failed to delete account: \(error.localizedDescription)")
            }
        }
    }
}
```

### Step 4: Add Navigation from Settings

In `SettingsView.swift`:

```swift
Section {
    NavigationLink {
        DeleteAccountView()
    } label: {
        Label("Delete Account", systemImage: "trash.circle")
            .foregroundColor(.red)
    }
} header: {
    Text("Danger Zone")
} footer: {
    Text("Permanently delete your account and all associated data. This action cannot be undone.")
}
```

---

## Error Handling

### Potential Failures

1. **Network Errors:**
   - User loses connection during deletion
   - **Solution:** Retry mechanism + partial deletion tracking

2. **Permission Errors:**
   - Firestore security rules deny deletion
   - **Solution:** Ensure rules allow user to delete own data

3. **Storage Deletion Failures:**
   - Images fail to delete (already deleted, permissions)
   - **Solution:** Continue with deletion, log errors

4. **Auth Re-authentication Required:**
   - Apple requires recent sign-in for account deletion
   - **Solution:** Prompt re-authentication before deletion

### Example: Re-authentication Flow

```swift
func deleteAccount() async throws {
    // Check if re-authentication is needed (Apple requirement)
    guard let user = Auth.auth().currentUser else {
        throw NSError(domain: "AuthManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "No user signed in"])
    }
    
    // Check if user signed in recently (within last 5 minutes)
    if let metadata = user.metadata,
       Date().timeIntervalSince(metadata.lastSignInDate ?? Date.distantPast) > 300 {
        // Need re-authentication
        throw NSError(domain: "AuthManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Please sign in again to delete your account"])
    }
    
    // Proceed with deletion
    try await firebaseService.deleteUserAccount(userId: user.uid)
    // ... rest of deletion
}
```

---

## Testing Plan

### Test Cases

1. **Basic Deletion:**
   - User with no posts, no followers → Should delete cleanly
   
2. **User with Posts:**
   - User with 10 collected stamps → All posts deleted
   
3. **User with Followers:**
   - User with 5 followers → All follow relationships removed
   - Followers' `followingCount` decremented correctly
   
4. **User with Following:**
   - User following 10 people → All follow relationships removed
   - Followed users' `followerCount` decremented correctly
   
5. **User with Likes/Comments:**
   - User has liked 20 posts → All likes deleted
   - User has commented on 15 posts → All comments deleted
   - Post `likeCount` and `commentCount` updated correctly
   
6. **User with Uploaded Images:**
   - User has profile picture + 5 stamp photos → All images deleted from Storage
   
7. **User with Blocked Users:**
   - User has blocked 3 users → All block relationships deleted
   
8. **Orphaned Data:**
   - After deletion, other users' posts with deleted user's comments → Show "[Deleted User]"
   
9. **Network Failure:**
   - User loses connection mid-deletion → Proper error handling
   
10. **Re-authentication:**
    - User tries to delete after 10 minutes → Prompted to re-authenticate

### MVP Test Users

**Current test users (from memory):**
- `hiroo` (developer account)
- `watagumostudio` (test account)

**Testing Strategy:**
1. Create a throwaway test account
2. Add sample data (posts, follows, likes, comments)
3. Delete account
4. Verify all data is removed
5. Check orphaned comments show as "[Deleted User]"

---

## Compliance Checklist

### GDPR Compliance

- [x] User can request account deletion
- [x] All personal data is deleted
- [x] Data deletion is permanent (no recovery)
- [ ] Consider: Export user data before deletion (GDPR "Right to Data Portability")

### CCPA Compliance

- [x] User can delete their account
- [x] All personal data is deleted within 45 days (MVP: immediate)

### Apple App Store Guidelines

- [x] Account deletion available in-app (Section 5.1.1)
- [x] Clear warning about data loss
- [x] Confirmation step required
- [x] No confusing UI or dark patterns

---

## Performance Considerations

### Deletion Time Estimates (for typical user)

| Operation | Estimated Time |
|-----------|----------------|
| Delete 50 collected stamps | ~2 seconds |
| Delete 100 followers/following | ~5 seconds |
| Delete 50 likes + 20 comments | ~2 seconds |
| Delete 10 photos from Storage | ~3 seconds |
| Delete user profile + auth | ~1 second |
| **Total** | **~13 seconds** |

### Optimization Strategies

1. **Parallel Deletion:**
   - Delete subcollections in parallel using `TaskGroup`
   - Delete Storage images in parallel
   
2. **Batch Operations:**
   - Use Firestore batches (max 500 operations)
   - Reduces network round trips
   
3. **Background Deletion (Future):**
   - Mark account for deletion immediately
   - Complete deletion via Cloud Function (async)
   - User sees instant feedback, deletion happens in background

---

## Cost Analysis (Firebase)

### Firestore Costs (typical user deletion)

| Operation | Cost per Operation | Quantity | Total Cost |
|-----------|-------------------|----------|------------|
| Document Deletes | $0.02 per 100K | ~200 docs | $0.00004 |
| Document Reads (for queries) | $0.06 per 100K | ~200 reads | $0.00012 |
| **Total Firestore** | | | **$0.00016** |

### Storage Costs

| Operation | Cost per Operation | Quantity | Total Cost |
|-----------|-------------------|----------|------------|
| Delete Operations | $0.004 per 10K | ~10 files | $0.000004 |
| **Total Storage** | | | **$0.000004** |

### **Total Cost per Account Deletion: ~$0.0002 USD**

For 100 users with MVP scale:
- **Total deletion cost: ~$0.02 USD** (negligible)

---

## Future Enhancements

### Phase 2 (Post-MVP):

1. **Export Data Before Deletion:**
   - GDPR "Right to Data Portability"
   - Generate JSON file with all user data
   - Include photos as ZIP file

2. **Grace Period (Soft Delete):**
   - 30-day recovery window
   - Hide user from searches/feeds
   - Scheduled cleanup via Cloud Function

3. **Admin Dashboard:**
   - View deletion requests
   - Manual review for suspicious activity
   - Analytics on deletion reasons

4. **Deletion Reasons:**
   - Ask user why they're deleting (optional survey)
   - Improve app based on feedback

5. **Partial Deletion:**
   - Delete posts but keep profile
   - Delete photos but keep profile
   - More granular control

---

## Security Considerations

### Firestore Security Rules

Ensure users can delete their own data:

```javascript
// firestore.rules

// Users can delete their own profile
match /users/{userId} {
  allow delete: if request.auth.uid == userId;
  
  // Users can delete their own subcollections
  match /collected_stamps/{stampId} {
    allow delete: if request.auth.uid == userId;
  }
  
  match /following/{followingId} {
    allow delete: if request.auth.uid == userId;
  }
  
  match /followers/{followerId} {
    allow delete: if request.auth.uid == userId;
  }
  
  match /blocked/{blockedId} {
    allow delete: if request.auth.uid == userId;
  }
}

// Users can delete their own likes
match /likes/{likeId} {
  allow delete: if request.auth.uid == resource.data.userId;
}

// Users can delete their own comments
match /comments/{commentId} {
  allow delete: if request.auth.uid == resource.data.userId;
}

// Users can delete their own feedback
match /feedback/{feedbackId} {
  allow delete: if request.auth.uid == resource.data.userId;
}
```

### Storage Security Rules

```javascript
// storage.rules

// Users can delete their own profile photos
match /users/{userId}/profile_photo/{photoId} {
  allow delete: if request.auth.uid == userId;
}

// Users can delete their own stamp photos
match /users/{userId}/stamp_photos/{photoId} {
  allow delete: if request.auth.uid == userId;
}
```

---

## Implementation Timeline

### Week 1: Backend Implementation
- Day 1-2: Add `deleteUserAccount()` to `FirebaseService`
- Day 3: Add helper methods (batched deletion, storage cleanup)
- Day 4: Update security rules
- Day 5: Unit testing

### Week 2: Frontend Implementation
- Day 1: Create `DeleteAccountView`
- Day 2: Add navigation from Settings
- Day 3: Implement confirmation flow
- Day 4: Error handling and loading states
- Day 5: UI polish

### Week 3: Testing & QA
- Day 1-2: Create test accounts with sample data
- Day 3: Test deletion flow end-to-end
- Day 4: Test edge cases (network failures, large datasets)
- Day 5: Fix bugs

### Week 4: Deployment & Monitoring
- Day 1: Submit to App Store for review
- Day 2-3: Monitor production for errors
- Day 4: Collect user feedback
- Day 5: Post-launch improvements

**Total: ~4 weeks (1 developer)**

---

## Open Questions

1. **Should we ask users why they're deleting?** (Optional survey)
   - Pros: Valuable feedback
   - Cons: Friction in deletion flow

2. **Should we offer data export?** (GDPR "Right to Data Portability")
   - Pros: Legal compliance, user control
   - Cons: More complexity

3. **Should we have a grace period?** (30-day soft delete)
   - Pros: Accidental deletion recovery
   - Cons: More complex, ongoing storage costs

4. **Should we anonymize instead of delete?** (Keep data but remove PII)
   - Pros: Preserve comments/likes for context
   - Cons: GDPR compliance concerns

**Recommendation for MVP:** Hard delete without grace period. Simple, compliant, and appropriate for current scale (<100 users).

---

## Summary

### MVP Implementation (Hard Delete)

**What Gets Deleted:**
- ✅ User profile document
- ✅ All collected stamps (posts)
- ✅ All uploaded photos (profile + stamps)
- ✅ All likes and comments by user
- ✅ All follow relationships (following + followers)
- ✅ All blocked user relationships
- ✅ All feedback submissions
- ✅ Firebase Auth account

**What Happens to Related Data:**
- Comments from deleted user → Show as "[Deleted User]"
- Likes from deleted user → Already deleted (count decremented)
- Posts liked/commented by others → Unaffected
- Followers/Following counts → Decremented correctly

**User Experience:**
1. User navigates to Settings → "Delete Account"
2. Warning screen with list of what gets deleted
3. Type "DELETE" to confirm
4. Loading spinner (5-15 seconds)
5. Account deleted, signed out, back to login screen

**Compliance:**
- ✅ GDPR compliant (complete data removal)
- ✅ CCPA compliant (user-initiated deletion)
- ✅ Apple App Store compliant (in-app deletion with confirmation)

---

## Next Steps

1. **Review this plan** with stakeholders
2. **Get approval** for MVP approach (hard delete)
3. **Update Firestore security rules** to allow user self-deletion
4. **Implement backend** (FirebaseService methods)
5. **Implement frontend** (DeleteAccountView)
6. **Test thoroughly** with throwaway accounts
7. **Deploy to production**
8. **Monitor for issues**

---

## References

- [GDPR Article 17 - Right to Erasure](https://gdpr-info.eu/art-17-gdpr/)
- [Apple App Store Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage)
- [Firebase Delete User Data Guide](https://firebase.google.com/docs/firestore/manage-data/delete-data)
- [Firestore Batch Operations](https://firebase.google.com/docs/firestore/manage-data/transactions#batched-writes)

---

**Document End**

