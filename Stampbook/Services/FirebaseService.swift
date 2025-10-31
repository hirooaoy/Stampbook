import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service to handle all Firebase operations (Firestore & Storage)
class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {
        // Enable offline persistence
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
    }
    
    // MARK: - Collected Stamps Sync
    
    /// Fetch collected stamps for a user from Firestore
    /// - Parameter userId: The user ID to fetch stamps for
    /// - Parameter limit: Maximum number of stamps to fetch (default: 50, nil = all)
    /// - Returns: Array of collected stamps, sorted by collection date (most recent first)
    ///
    /// **PERFORMANCE NOTE:** Always use a limit when fetching for feed/social features.
    /// Fetching all stamps is only needed for the user's own stamp collection view.
    func fetchCollectedStamps(for userId: String, limit: Int? = nil) async throws -> [CollectedStamp] {
        var query = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .order(by: "collectedDate", descending: true)
        
        // Apply limit if provided (for feed/social features)
        if let limit = limit {
            query = query.limit(to: limit)
        }
        
        let snapshot = try await query.getDocuments()
        
        let stamps = snapshot.documents.compactMap { doc -> CollectedStamp? in
            try? doc.data(as: CollectedStamp.self)
        }
        
        return stamps
    }
    
    /// Save a single collected stamp to Firestore
    func saveCollectedStamp(_ stamp: CollectedStamp, for userId: String) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stamp.stampId)
        
        try docRef.setData(from: stamp, merge: true)
    }
    
    /// Update notes for a collected stamp
    func updateStampNotes(stampId: String, userId: String, notes: String) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stampId)
        
        try await docRef.updateData([
            "userNotes": notes
        ])
    }
    
    /// Update images for a collected stamp
    func updateStampImages(stampId: String, userId: String, imageNames: [String], imagePaths: [String]) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stampId)
        
        try await docRef.updateData([
            "userImageNames": imageNames,
            "userImagePaths": imagePaths
        ])
    }
    
    /// Delete all collected stamps for a user (used in resetAll)
    func deleteAllCollectedStamps(for userId: String) async throws {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .getDocuments()
        
        // Delete in batches
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
    
    // MARK: - Stamps & Collections (Read-Only for Users)
    
    /// Fetch all stamps from Firestore
    /// ⚠️ WARNING: This loads ALL stamps. For production use, prefer lazy loading methods below.
    func fetchStamps() async throws -> [Stamp] {
        let snapshot = try await db
            .collection("stamps")
            .getDocuments()
        
        let stamps = snapshot.documents.compactMap { doc -> Stamp? in
            try? doc.data(as: Stamp.self)
        }
        
        return stamps
    }
    
    /// Fetch specific stamps by IDs (for feed, profiles)
    /// - Parameter ids: Array of stamp IDs to fetch
    /// - Returns: Array of stamps matching the IDs
    ///
    /// **PERFORMANCE:** Firestore `in` queries support up to 10 items per query.
    /// This method automatically batches larger requests.
    func fetchStampsByIds(_ ids: [String]) async throws -> [Stamp] {
        guard !ids.isEmpty else { return [] }
        
        // Firestore 'in' queries support max 10 items
        // Batch into chunks of 10
        let batchSize = 10
        var allStamps: [Stamp] = []
        
        for i in stride(from: 0, to: ids.count, by: batchSize) {
            let batchIds = Array(ids[i..<min(i + batchSize, ids.count)])
            
            let snapshot = try await db
                .collection("stamps")
                .whereField(FieldPath.documentID(), in: batchIds)
                .getDocuments()
            
            let stamps = snapshot.documents.compactMap { doc -> Stamp? in
                try? doc.data(as: Stamp.self)
            }
            
            allStamps.append(contentsOf: stamps)
        }
        
        return allStamps
    }
    
    /// Fetch stamps in a geographic region (for map view)
    /// - Parameters:
    ///   - minGeohash: Minimum geohash for range query
    ///   - maxGeohash: Maximum geohash for range query
    ///   - limit: Maximum number of stamps to return (default 200)
    /// - Returns: Array of stamps in the region
    ///
    /// **USAGE:**
    /// ```swift
    /// let (min, max) = Geohash.bounds(for: mapRegion, precision: 5)
    /// let stamps = try await fetchStampsInRegion(minGeohash: min, maxGeohash: max)
    /// ```
    func fetchStampsInRegion(minGeohash: String, maxGeohash: String, limit: Int = 200) async throws -> [Stamp] {
        let snapshot = try await db
            .collection("stamps")
            .whereField("geohash", isGreaterThanOrEqualTo: minGeohash)
            .whereField("geohash", isLessThan: maxGeohash)
            .limit(to: limit)
            .getDocuments()
        
        let stamps = snapshot.documents.compactMap { doc -> Stamp? in
            try? doc.data(as: Stamp.self)
        }
        
        return stamps
    }
    
    /// Fetch stamps in a specific collection
    /// - Parameter collectionId: The collection ID
    /// - Returns: Array of stamps in the collection
    func fetchStampsInCollection(collectionId: String) async throws -> [Stamp] {
        let snapshot = try await db
            .collection("stamps")
            .whereField("collectionIds", arrayContains: collectionId)
            .getDocuments()
        
        let stamps = snapshot.documents.compactMap { doc -> Stamp? in
            try? doc.data(as: Stamp.self)
        }
        
        return stamps
    }
    
    /// Fetch all collections from Firestore
    func fetchCollections() async throws -> [Collection] {
        let snapshot = try await db
            .collection("collections")
            .getDocuments()
        
        let collections = snapshot.documents.compactMap { doc -> Collection? in
            try? doc.data(as: Collection.self)
        }
        
        return collections
    }
    
    // MARK: - Stamp Statistics
    
    /// Fetch statistics for a specific stamp (total collectors, etc.)
    func fetchStampStatistics(stampId: String) async throws -> StampStatistics {
        let docRef = db
            .collection("stamp_statistics")
            .document(stampId)
        
        let document = try await docRef.getDocument()
        
        if let stats = try? document.data(as: StampStatistics.self) {
            return stats
        } else {
            // No statistics yet, return default
            return StampStatistics(stampId: stampId, totalCollectors: 0, collectorUserIds: [])
        }
    }
    
    /// Increment collector count when a user collects a stamp
    /// Also tracks the order in which users collected it (for ranking)
    func incrementStampCollectors(stampId: String, userId: String) async throws {
        let docRef = db
            .collection("stamp_statistics")
            .document(stampId)
        
        // Use Firestore transaction to safely increment and add user
        _ = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            let document: DocumentSnapshot
            do {
                document = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            if document.exists {
                // Document exists, update it
                var collectorIds = document.data()?["collectorUserIds"] as? [String] ?? []
                
                // Only add if user hasn't collected yet
                if !collectorIds.contains(userId) {
                    collectorIds.append(userId)
                    transaction.updateData([
                        "totalCollectors": collectorIds.count,
                        "collectorUserIds": collectorIds,
                        "lastUpdated": FieldValue.serverTimestamp()
                    ], forDocument: docRef)
                }
            } else {
                // Create new document
                transaction.setData([
                    "stampId": stampId,
                    "totalCollectors": 1,
                    "collectorUserIds": [userId],
                    "lastUpdated": FieldValue.serverTimestamp()
                ], forDocument: docRef)
            }
            
            return nil
        }
    }
    
    /// Get the user's rank for a specific stamp (what number they were to collect it)
    func getUserRankForStamp(stampId: String, userId: String) async throws -> Int? {
        let stats = try await fetchStampStatistics(stampId: stampId)
        
        if let index = stats.collectorUserIds.firstIndex(of: userId) {
            return index + 1 // Rank is 1-indexed
        }
        
        return nil
    }
    
    // MARK: - User Profile Management
    
    /// Fetch user profile from Firestore
    /// Used when loading a user's profile data
    func fetchUserProfile(userId: String) async throws -> UserProfile {
        let docRef = db.collection("users").document(userId)
        let document = try await docRef.getDocument()
        
        if let profile = try? document.data(as: UserProfile.self) {
            return profile
        } else {
            throw NSError(domain: "FirebaseService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }
    }
    
    /// Create or update user profile in Firestore
    /// Uses merge:true to only update provided fields
    func saveUserProfile(_ profile: UserProfile) async throws {
        let docRef = db.collection("users").document(profile.id)
        try docRef.setData(from: profile, merge: true)
    }
    
    /// Create initial user profile (called on first sign-in)
    /// Generates initial username from display name + random number
    func createUserProfile(userId: String, username: String, displayName: String) async throws {
        let profile = UserProfile(
            id: userId,
            username: username,
            displayName: displayName,
            bio: "",
            avatarUrl: nil,
            totalStamps: 0,
            createdAt: Date(),
            lastActiveAt: Date()
        )
        
        try await saveUserProfile(profile)
        print("✅ Created user profile for \(displayName) (@\(username))")
    }
    
    /// Update user's total stamp count
    /// Called when user collects a new stamp
    func updateUserStampCount(userId: String, count: Int) async throws {
        let docRef = db.collection("users").document(userId)
        try await docRef.updateData([
            "totalStamps": count,
            "lastActiveAt": FieldValue.serverTimestamp()
        ])
    }
    
    /// Update user's stamp statistics (totalStamps and uniqueCountriesVisited)
    /// Called when user collects a new stamp
    func updateUserStampStats(userId: String, totalStamps: Int, uniqueCountriesVisited: Int) async throws {
        let docRef = db.collection("users").document(userId)
        try await docRef.updateData([
            "totalStamps": totalStamps,
            "uniqueCountriesVisited": uniqueCountriesVisited,
            "lastActiveAt": FieldValue.serverTimestamp()
        ])
    }
    
    /// Update specific user profile fields
    /// Only updates fields that are provided (non-nil)
    /// Used by ProfileEditView to save changes
    func updateUserProfile(userId: String, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil, username: String? = nil) async throws {
        let docRef = db.collection("users").document(userId)
        var updates: [String: Any] = ["lastActiveAt": FieldValue.serverTimestamp()]
        
        if let displayName = displayName {
            updates["displayName"] = displayName
        }
        if let bio = bio {
            updates["bio"] = bio
        }
        if let avatarUrl = avatarUrl {
            updates["avatarUrl"] = avatarUrl
        }
        if let username = username {
            updates["username"] = username
            // Set timestamp when username is changed (for 14-day cooldown enforcement)
            updates["usernameLastChanged"] = FieldValue.serverTimestamp()
        }
        
        try await docRef.updateData(updates)
    }
    
    /// Check if a username is available (not taken by another user)
    /// Returns true if available, false if taken
    /// Used during profile editing to validate username uniqueness
    func isUsernameAvailable(_ username: String, excludingUserId: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .whereField("username", isEqualTo: username)
            .getDocuments()
        
        // If no documents found, username is available
        if snapshot.documents.isEmpty {
            return true
        }
        
        // If found, check if it's the current user's own username
        // (user can keep their existing username)
        if snapshot.documents.count == 1,
           let userId = snapshot.documents.first?.documentID,
           userId == excludingUserId {
            return true
        }
        
        return false
    }
    
    // MARK: - User Ranking
    
    // Rank cache to avoid expensive queries
    private var rankCache: [String: (rank: Int, timestamp: Date)] = [:]
    // Extended cache from 5 minutes to 30 minutes to reduce query costs
    // Rank doesn't change frequently, so longer cache is acceptable
    private let rankCacheExpiration: TimeInterval = 1800 // 30 minutes (was 5 minutes)
    
    /// Calculate user's global rank based on total stamps collected (with caching)
    /// Rank = number of users with more stamps + 1
    /// 
    /// OPTIMIZATION NOTE: For large scale (10k+ users), consider:
    /// - Caching rank on profile (update periodically via Cloud Function)
    /// - Using approximate rank with ±10 range
    /// - Limiting leaderboard to top 1000 + user's rank
    func calculateUserRankCached(userId: String, totalStamps: Int) async throws -> Int {
        // Check cache first
        if let cached = rankCache[userId],
           Date().timeIntervalSince(cached.timestamp) < rankCacheExpiration {
            print("✅ Using cached rank for \(userId): #\(cached.rank)")
            return cached.rank
        }
        
        // Fetch from Firestore
        let rank = try await calculateUserRank(userId: userId, totalStamps: totalStamps)
        
        // Cache the result
        await MainActor.run {
            self.rankCache[userId] = (rank: rank, timestamp: Date())
        }
        
        return rank
    }
    
    /// Calculate user's global rank based on total stamps collected
    /// Rank = number of users with more stamps + 1
    /// 
    /// OPTIMIZATION NOTE: For large scale (10k+ users), consider:
    /// - Caching rank on profile (update periodically via Cloud Function)
    /// - Using approximate rank with ±10 range
    /// - Limiting leaderboard to top 1000 + user's rank
    func calculateUserRank(userId: String, totalStamps: Int) async throws -> Int {
        #if DEBUG
        let startTime = Date()
        print("🔍 [Rank] Calculating rank for user \(userId) with \(totalStamps) stamps...")
        #endif
        
        do {
            // Use getDocuments() instead of count aggregation for better reliability
            // Count aggregation can be slow or fail without proper indexes
            let snapshot = try await db.collection("users")
                .whereField("totalStamps", isGreaterThan: totalStamps)
                .getDocuments(source: .server)
            
            let usersAhead = snapshot.documents.count
            let rank = usersAhead + 1
            
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            print("✅ [Rank] Calculated rank #\(rank) (found \(usersAhead) users ahead) in \(String(format: "%.2f", duration))s")
            #endif
            
            return rank
        } catch {
            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            print("❌ [Rank] Failed after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            if let firestoreError = error as NSError? {
                print("❌ [Rank] Error domain: \(firestoreError.domain), code: \(firestoreError.code)")
                print("❌ [Rank] Full error: \(firestoreError)")
            }
            #endif
            throw error
        }
    }
    
    // MARK: - Photo Upload
    // NOTE: Limit to 5 photos per stamp to control Firebase Storage costs
    // Requires Blaze plan (pay-as-you-go) to use Storage
    
    /// Upload a profile photo to Firebase Storage
    /// 
    /// Process:
    /// 1. Resize and compress image using ImageManager (400x400px, max 500KB)
    /// 2. Delete old profile photo (if exists) to save storage
    /// 3. Generate unique filename with UUID
    /// 4. Upload image as JPEG to Storage with cache control headers
    /// 5. Return download URL for Firestore
    ///
    /// - Parameters:
    ///   - userId: The user's ID
    ///   - image: Original UIImage to upload (will be resized)
    ///   - oldAvatarUrl: URL of old photo to delete (optional)
    /// - Returns: Download URL of uploaded photo
    func uploadProfilePhoto(userId: String, image: UIImage, oldAvatarUrl: String? = nil) async throws -> String {
        // Resize and compress image first (400x400px, max 500KB)
        guard let imageData = ImageManager.shared.prepareProfilePictureForUpload(image) else {
            throw NSError(domain: "FirebaseService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare profile picture for upload"])
        }
        
        // Delete old profile photo first (if exists)
        if let oldUrl = oldAvatarUrl, !oldUrl.isEmpty {
            do {
                try await deleteProfilePhoto(url: oldUrl)
                print("✅ Deleted old profile photo before uploading new one")
            } catch {
                // Log but don't fail - old photo might already be deleted or invalid
                print("⚠️ Could not delete old profile photo: \(error.localizedDescription)")
            }
        }
        
        // Generate unique filename and upload path
        let photoId = UUID().uuidString
        let path = "users/\(userId)/profile_photo/\(photoId).jpg"
        let storageRef = storage.reference().child(path)
        
        // Set metadata for proper content type and caching
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        // Cache profile pictures for 7 days to reduce bandwidth costs
        metadata.cacheControl = "public, max-age=604800"
        
        // Upload to Firebase Storage
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        print("✅ Profile photo uploaded: \(Int(Double(imageData.count) / 1024.0))KB")
        
        return downloadURL.absoluteString
    }
    
    /// Delete a profile photo from Firebase Storage
    /// Used when user updates their profile picture
    func deleteProfilePhoto(url: String) async throws {
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
    
    /// Upload a stamp photo to Firebase Storage
    /// Used when user adds photos to their collected stamps
    /// Includes cache control headers for CDN efficiency
    func uploadStampPhoto(userId: String, stampId: String, imageData: Data) async throws -> String {
        let photoId = UUID().uuidString
        let path = "users/\(userId)/stamp_photos/\(stampId)_\(photoId).jpg"
        let storageRef = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        // Cache for 7 days to reduce bandwidth costs
        metadata.cacheControl = "public, max-age=604800"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    /// Delete a stamp photo from Firebase Storage
    /// Used when user removes photos from their stamp collection
    func deleteStampPhoto(url: String) async throws {
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
    
    // MARK: - Following List Cache
    
    // Cache following list to avoid repeated fetches
    private var followingCache: [String: (profiles: [UserProfile], timestamp: Date)] = [:]
    private let followingCacheExpiration: TimeInterval = 1800 // 30 minutes
    
    // MARK: - Follow/Unfollow System
    
    /// Follow a user (bidirectional write: add to follower's following + add to followee's followers)
    /// Uses Firestore transaction to ensure atomicity and idempotency
    /// Returns true if follow was created, false if already following
    @discardableResult
    func followUser(followerId: String, followeeId: String) async throws -> Bool {
        guard followerId != followeeId else {
            throw NSError(domain: "FirebaseService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        // Use transaction to ensure all writes succeed together
        let didFollow = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            // References
            let followerRef = self.db.collection("users").document(followerId)
            let followeeRef = self.db.collection("users").document(followeeId)
            let followingRef = followerRef.collection("following").document(followeeId)
            let followerDocRef = followeeRef.collection("followers").document(followerId)
            
            // Read current state
            let followerDoc: DocumentSnapshot
            let followeeDoc: DocumentSnapshot
            let followingDoc: DocumentSnapshot
            
            do {
                followerDoc = try transaction.getDocument(followerRef)
                followeeDoc = try transaction.getDocument(followeeRef)
                followingDoc = try transaction.getDocument(followingRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            // Check if already following (idempotency)
            if followingDoc.exists {
                print("⚠️ Already following - skipping")
                return false // Already following
            }
            
            // Create follow documents
            let followData: [String: Any] = [
                "id": followeeId,
                "createdAt": FieldValue.serverTimestamp()
            ]
            let followerData: [String: Any] = [
                "id": followerId,
                "createdAt": FieldValue.serverTimestamp()
            ]
            
            // Write follow relationships
            transaction.setData(followData, forDocument: followingRef)
            transaction.setData(followerData, forDocument: followerDocRef)
            
            // Increment counts (denormalized for performance)
            let currentFollowingCount = followerDoc.data()?["followingCount"] as? Int ?? 0
            let currentFollowerCount = followeeDoc.data()?["followerCount"] as? Int ?? 0
            
            transaction.updateData([
                "followingCount": currentFollowingCount + 1,
                "lastActiveAt": FieldValue.serverTimestamp()
            ], forDocument: followerRef)
            
            transaction.updateData([
                "followerCount": currentFollowerCount + 1,
                "lastActiveAt": FieldValue.serverTimestamp()
            ], forDocument: followeeRef)
            
            return true // Successfully followed
        } as? Bool ?? false
        
        if didFollow {
            print("✅ User \(followerId) followed \(followeeId)")
            // Invalidate following cache since list changed
            invalidateFollowingCache(userId: followerId)
        }
        
        return didFollow
    }
    
    /// Unfollow a user (bidirectional delete: remove from following + remove from followers)
    /// Uses Firestore transaction to ensure atomicity and idempotency
    /// Returns true if unfollow was performed, false if wasn't following
    @discardableResult
    func unfollowUser(followerId: String, followeeId: String) async throws -> Bool {
        // Use transaction to ensure all writes succeed together
        let didUnfollow = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            // References
            let followerRef = self.db.collection("users").document(followerId)
            let followeeRef = self.db.collection("users").document(followeeId)
            let followingRef = followerRef.collection("following").document(followeeId)
            let followerDocRef = followeeRef.collection("followers").document(followerId)
            
            // Read current state
            let followerDoc: DocumentSnapshot
            let followeeDoc: DocumentSnapshot
            let followingDoc: DocumentSnapshot
            
            do {
                followerDoc = try transaction.getDocument(followerRef)
                followeeDoc = try transaction.getDocument(followeeRef)
                followingDoc = try transaction.getDocument(followingRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            // Check if actually following (idempotency)
            if !followingDoc.exists {
                print("⚠️ Not following - skipping")
                return false // Not following
            }
            
            // Delete follow relationships
            transaction.deleteDocument(followingRef)
            transaction.deleteDocument(followerDocRef)
            
            // Decrement counts (don't go below 0)
            let currentFollowingCount = max(0, (followerDoc.data()?["followingCount"] as? Int ?? 0) - 1)
            let currentFollowerCount = max(0, (followeeDoc.data()?["followerCount"] as? Int ?? 0) - 1)
            
            transaction.updateData([
                "followingCount": currentFollowingCount,
                "lastActiveAt": FieldValue.serverTimestamp()
            ], forDocument: followerRef)
            
            transaction.updateData([
                "followerCount": currentFollowerCount,
                "lastActiveAt": FieldValue.serverTimestamp()
            ], forDocument: followeeRef)
            
            return true // Successfully unfollowed
        } as? Bool ?? false
        
        if didUnfollow {
            print("✅ User \(followerId) unfollowed \(followeeId)")
            // Invalidate following cache since list changed
            invalidateFollowingCache(userId: followerId)
        }
        
        return didUnfollow
    }
    
    /// Check if a user is following another user
    func isFollowing(followerId: String, followeeId: String) async throws -> Bool {
        let docRef = db
            .collection("users")
            .document(followerId)
            .collection("following")
            .document(followeeId)
        
        let document = try await docRef.getDocument()
        return document.exists
    }
    
    /// Fetch list of followers for a user
    ///
    /// **Current Implementation (Optimized):** Batch fetching with `in` operator
    /// - 100 followers = 10 batched Firestore reads (~0.5s load)
    /// - ✅ 10x cheaper than individual fetches (10 reads vs 100 reads)
    /// - ✅ Still fast with parallel batch execution
    ///
    /// **Future Optimizations:**
    /// - **Option C (Scale):** Denormalize profile data into follower docs (1 read total, instant load)
    ///
    /// See: PERFORMANCE_OPTIMIZATIONS.md for full analysis
    func fetchFollowers(userId: String, limit: Int = 100) async throws -> [UserProfile] {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("followers")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        // Get the follower user IDs
        let followerIds = snapshot.documents.compactMap { $0.documentID }
        
        guard !followerIds.isEmpty else {
            return []
        }
        
        // Batch fetch profiles using `in` operator (max 10 IDs per query)
        // This reduces 100 individual reads → 10 batched reads (90% cost reduction)
        let profiles = try await fetchProfilesBatched(userIds: followerIds)
        
        return profiles
    }
    
    /// Fetch list of users that a user is following
    ///
    /// **Current Implementation (Optimized):** Batch fetching with `in` operator + caching
    /// - 100 following = 10 batched Firestore reads (~0.5s load) OR 0 reads (cache hit)
    /// - ✅ 10x cheaper than individual fetches (10 reads vs 100 reads)
    /// - ✅ Still fast with parallel batch execution
    /// - ✅ Cached for 30 minutes to reduce costs
    ///
    /// **Future Optimizations:**
    /// - **Option C (Scale):** Denormalize profile data into following docs (1 read total, instant load)
    ///
    /// See: PERFORMANCE_OPTIMIZATIONS.md for full analysis
    func fetchFollowing(userId: String, limit: Int = 100, useCache: Bool = true) async throws -> [UserProfile] {
        // Check cache first
        if useCache,
           let cached = followingCache[userId],
           Date().timeIntervalSince(cached.timestamp) < followingCacheExpiration {
            print("✅ Using cached following list for \(userId) (\(cached.profiles.count) users)")
            return cached.profiles
        }
        
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("following")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        // Get the following user IDs
        let followingIds = snapshot.documents.compactMap { $0.documentID }
        
        guard !followingIds.isEmpty else {
            // Cache empty result
            await MainActor.run {
                followingCache[userId] = (profiles: [], timestamp: Date())
            }
            return []
        }
        
        // Batch fetch profiles using `in` operator (max 10 IDs per query)
        // This reduces 100 individual reads → 10 batched reads (90% cost reduction)
        let profiles = try await fetchProfilesBatched(userIds: followingIds)
        
        // Cache the result
        await MainActor.run {
            followingCache[userId] = (profiles: profiles, timestamp: Date())
        }
        print("✅ Fetched and cached following list for \(userId) (\(profiles.count) users)")
        
        return profiles
    }
    
    /// Invalidate following cache for a user (call after follow/unfollow)
    func invalidateFollowingCache(userId: String) {
        followingCache.removeValue(forKey: userId)
    }
    
    /// Batch fetch user profiles using Firestore `in` operator
    /// Splits IDs into chunks of 10 (Firestore limit) and fetches in parallel
    /// - Parameter userIds: Array of user IDs to fetch
    /// - Returns: Array of user profiles (order not guaranteed)
    private func fetchProfilesBatched(userIds: [String]) async throws -> [UserProfile] {
        // Split into batches of 10 (Firestore `in` operator limit)
        let batches = stride(from: 0, to: userIds.count, by: 10).map {
            Array(userIds[$0..<min($0 + 10, userIds.count)])
        }
        
        // Fetch batches in parallel
        let profiles = try await withThrowingTaskGroup(of: [UserProfile].self, returning: [UserProfile].self) { group in
            for batch in batches {
                group.addTask {
                    let snapshot = try await self.db.collection("users")
                        .whereField(FieldPath.documentID(), in: batch)
                        .getDocuments()
                    
                    return await MainActor.run {
                        snapshot.documents.compactMap { doc -> UserProfile? in
                            try? doc.data(as: UserProfile.self)
                        }
                    }
                }
            }
            
            var allProfiles: [UserProfile] = []
            for try await batchProfiles in group {
                allProfiles.append(contentsOf: batchProfiles)
            }
            return allProfiles
        }
        
        return profiles
    }
    
    /// Search for users by username or display name (for finding users to follow)
    ///
    /// MVP: Simple username prefix search
    /// 
    /// POST-MVP ENHANCEMENTS:
    /// - Add displayName search (requires composite index in Firestore)
    /// - Full-text search using Algolia or Elasticsearch
    /// - Search ranking/relevance scoring
    /// - Filter by location, stamp count, etc.
    /// - Suggested users algorithm:
    ///   • Sort by follower count (popular users)
    ///   • Mutual followers (friends of friends)
    ///   • Similar stamps collected (shared interests)
    ///   • Location proximity (nearby users)
    /// - Phone number lookup for contact sync
    /// - Pagination for large result sets
    func searchUsers(query: String, limit: Int = 20) async throws -> [UserProfile] {
        guard !query.isEmpty else { return [] }
        
        let lowercaseQuery = query.lowercased()
        
        // Search by username (starts with)
        // Note: This only searches username field. To also search displayName,
        // we'd need a composite index and multiple queries (or a search service)
        let usernameSnapshot = try await db
            .collection("users")
            .whereField("username", isGreaterThanOrEqualTo: lowercaseQuery)
            .whereField("username", isLessThan: lowercaseQuery + "\u{f8ff}")
            .limit(to: limit)
            .getDocuments()
        
        let profiles = try usernameSnapshot.documents.compactMap { doc -> UserProfile? in
            try doc.data(as: UserProfile.self)
        }
        
        return profiles
    }
    
    // MARK: - Feed System
    
    /// Fetch recent stamps from users that the current user is following
    /// Returns tuples of (userProfile, collectedStamp) for rendering in feed
    /// 
    /// PERFORMANCE NOTES:
    /// - Fetches up to 10 most recent stamps from each followed user (optimized for pagination)
    /// - For large followings (100+ users), uses pagination to load in chunks
    /// - Following list is cached for 30 minutes to reduce costs
    /// - Consider implementing a denormalized feed collection for better performance at scale
    ///
    /// REQUIRES COMPOSITE INDEX:
    /// Collection: users/{userId}/collected_stamps
    /// Fields: userId (Ascending), collectedDate (Descending)
    func fetchFollowingFeed(userId: String, limit: Int = 50, stampsPerUser: Int = 10, initialBatchSize: Int = 15) async throws -> [(profile: UserProfile, stamp: CollectedStamp)] {
        // 1. Get current user's profile (for including in feed)
        let currentUserProfile = try await fetchUserProfile(userId: userId)
        
        // 2. Get list of users being followed (uses cache if available)
        let followingProfiles = try await fetchFollowing(userId: userId, useCache: true)
        
        // 3. Combine current user + followed users for feed
        // This ensures "All" tab shows your posts + followed users' posts
        let allProfiles = [currentUserProfile] + followingProfiles
        
        // 4. Use smaller initial batch for faster first load
        // Fetch from first 15 users only (150 reads) instead of all 50+ (500+ reads)
        // This reduces initial load time from ~5s to ~1-2s
        // Note: Current user is ALWAYS included (not subject to batch limit)
        let batchSize = min(initialBatchSize + 1, allProfiles.count) // +1 for current user
        let profilesToFetch = Array(allProfiles.prefix(batchSize))
        
        print("📱 Fetching feed from \(batchSize) users (\(followingProfiles.count) followed + current user, fast initial load)...")
        
        // 5. Fetch stamps from users in parallel for better performance
        var allFeedItems: [(profile: UserProfile, stamp: CollectedStamp)] = []
        
        // Use TaskGroup for parallel fetching
        await withTaskGroup(of: (UserProfile, [CollectedStamp]).self) { group in
            for profile in profilesToFetch {
                group.addTask {
                    do {
                        // Fetch recent stamps for this user (10 per user for balanced feed)
                        let stamps = try await self.fetchCollectedStamps(for: profile.id, limit: stampsPerUser)
                        return (profile, stamps)
                    } catch {
                        print("⚠️ Failed to fetch stamps for user \(profile.username): \(error.localizedDescription)")
                        return (profile, [])
                    }
                }
            }
            
            // Collect results
            for await (profile, stamps) in group {
                for stamp in stamps {
                    allFeedItems.append((profile: profile, stamp: stamp))
                }
            }
        }
        
        // 6. Sort by collection date (most recent first)
        allFeedItems.sort { $0.stamp.collectedDate > $1.stamp.collectedDate }
        
        // 7. Limit total items returned (pagination support)
        if allFeedItems.count > limit {
            allFeedItems = Array(allFeedItems.prefix(limit))
        }
        
        print("✅ Fetched \(allFeedItems.count) feed items from \(batchSize) users (initial batch)")
        
        return allFeedItems
    }
}

// MARK: - Stamp Statistics Model

struct StampStatistics: Codable {
    let stampId: String
    let totalCollectors: Int
    let collectorUserIds: [String] // Ordered by collection time (first to collect is first in array)
    
    enum CodingKeys: String, CodingKey {
        case stampId
        case totalCollectors
        case collectorUserIds
    }
}

