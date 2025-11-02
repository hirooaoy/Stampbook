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
        
        // Run connectivity diagnostics in background (non-blocking)
        // NOTE: This should NOT block app initialization
        Task.detached(priority: .background) {
            // Add delay to not block startup
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await self.runConnectivityDiagnostics()
        }
    }
    
    // MARK: - Connectivity Diagnostics
    
    /// Run comprehensive connectivity diagnostics for Firebase
    func runConnectivityDiagnostics() async {
        print("\n🔍 [Firebase Diagnostics] Starting connectivity tests...\n")
        
        // Test 1: Basic network connectivity
        print("1️⃣ Testing basic network connectivity...")
        await testNetworkConnectivity()
        
        // Test 2: Firestore connection
        print("\n2️⃣ Testing Firestore connection...")
        await testFirestoreConnection()
        
        // Test 3: Firebase Storage connection
        print("\n3️⃣ Testing Firebase Storage connection...")
        await testStorageConnection()
        
        print("\n✅ [Firebase Diagnostics] Tests complete\n")
    }
    
    private func testNetworkConnectivity() async {
        // Try to reach Google's DNS server
        guard let url = URL(string: "https://www.google.com") else {
            print("❌ Failed to create URL")
            return
        }
        
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let (_, response) = try await URLSession.shared.data(from: url)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("✅ Internet connection OK (\(String(format: "%.3f", duration))s)")
                } else {
                    print("⚠️ Internet reachable but returned status code \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ No internet connection: \(error.localizedDescription)")
        }
    }
    
    private func testFirestoreConnection() async {
        // Try to fetch a single stamp (lightweight query)
        // NOTE: Use default source (cache first, then server if needed)
        // This allows offline usage and doesn't block on slow connections
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Try with timeout using withThrowingTaskGroup
            let snapshot = try await withThrowingTaskGroup(of: QuerySnapshot?.self) { group in
                // Add fetch task
                group.addTask {
                    return try await self.db.collection("stamps")
                        .limit(to: 1)
                        .getDocuments() // Default source: cache + server (non-blocking)
                }
                
                // Add timeout task
                group.addTask {
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                    return nil // Timeout indicator
                }
                
                // Wait for first result
                if let result = try await group.next() {
                    group.cancelAll()
                    return result
                }
                throw NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No result"])
            }
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            if let snapshot = snapshot {
                // Success
                print("✅ Firestore connection OK (\(String(format: "%.3f", duration))s, \(snapshot.documents.count) doc)")
                print("   Project: stampbook-app")
            } else {
                // Timeout occurred
                print("⏱️ Firestore connection slow/timed out after \(String(format: "%.3f", duration))s")
                print("   → Using offline cache if available")
            }
        } catch let error as NSError {
            print("❌ Firestore connection FAILED (\(error.domain), code: \(error.code))")
            print("   Message: \(error.localizedDescription)")
            
            // Common error codes
            if error.domain == "FIRFirestoreErrorDomain" {
                switch error.code {
                case 14: // UNAVAILABLE
                    print("   → Backend unavailable. Using offline cache.")
                case 7: // PERMISSION_DENIED
                    print("   → Permission denied. Check Firestore security rules.")
                case 16: // UNAUTHENTICATED
                    print("   → Not authenticated. Check Firebase Auth setup.")
                default:
                    print("   → Error code \(error.code)")
                }
            }
        }
    }
    
    private func testStorageConnection() async {
        // Try to get a storage reference
        let storageRef = storage.reference()
        let bucket = storageRef.bucket
        print("✅ Firebase Storage connected")
        print("   Bucket: \(bucket)")
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
    /// This method automatically batches larger requests and executes batches in parallel.
    func fetchStampsByIds(_ ids: [String]) async throws -> [Stamp] {
        guard !ids.isEmpty else { return [] }
        
        let overallStart = CFAbsoluteTimeGetCurrent()
        
        // Firestore 'in' queries support max 10 items
        // Batch into chunks of 10
        let batchSize = 10
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }
        
        print("🔄 [FirebaseService] Fetching \(ids.count) stamps in \(batches.count) parallel batches...")
        
        // Execute all batches in PARALLEL for better performance
        let allStamps = try await withThrowingTaskGroup(of: [Stamp].self, returning: [Stamp].self) { group in
            for (index, batchIds) in batches.enumerated() {
                group.addTask {
                    let batchStart = CFAbsoluteTimeGetCurrent()
                    print("📦 [FirebaseService] Batch \(index + 1)/\(batches.count): Fetching \(batchIds.count) stamps...")
                    
                    let snapshot = try await self.db
                        .collection("stamps")
                        .whereField(FieldPath.documentID(), in: batchIds)
                        .getDocuments()
                    
                    let stamps = await MainActor.run {
                        snapshot.documents.compactMap { doc -> Stamp? in
                            try? doc.data(as: Stamp.self)
                        }
                    }
                    
                    let batchTime = CFAbsoluteTimeGetCurrent() - batchStart
                    print("✅ [FirebaseService] Batch \(index + 1)/\(batches.count): Completed in \(String(format: "%.3f", batchTime))s (\(stamps.count) stamps)")
                    
                    return stamps
                }
            }
            
            var allStamps: [Stamp] = []
            for try await stamps in group {
                allStamps.append(contentsOf: stamps)
            }
            return allStamps
        }
        
        let overallTime = CFAbsoluteTimeGetCurrent() - overallStart
        print("⏱️ [FirebaseService] Total fetchStampsByIds: \(String(format: "%.3f", overallTime))s (\(allStamps.count)/\(ids.count) stamps)")
        
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
    
    // TODO: POST-MVP - Per-Stamp Ranking System
    // This function is disabled for MVP as it requires expensive queries
    // Consider implementing post-MVP with:
    // - Caching collector order in stamp statistics
    // - Limiting rank display to first N collectors
    // - Using Cloud Functions to maintain rank data
    /*
    func getUserRankForStamp(stampId: String, userId: String) async throws -> Int? {
        let stats = try await fetchStampStatistics(stampId: stampId)
        
        if let index = stats.collectorUserIds.firstIndex(of: userId) {
            return index + 1 // Rank is 1-indexed
        }
        
        return nil
    }
    */
    
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
    
    // MARK: - User Ranking (POST-MVP)
    
    // TODO: POST-MVP - Global User Ranking System
    // Rank calculation is disabled for MVP due to:
    // - Expensive Firestore queries comparing all users
    // - Complex caching requirements (30-minute cache per user)
    // - Performance concerns as user base scales
    // - Need for Firestore indexes on totalStamps field
    //
    // Consider implementing post-MVP with:
    // - Periodic Cloud Function to calculate and cache ranks
    // - Store rank on user profile (updated daily/hourly)
    // - Leaderboard limited to top 1000 users
    // - Approximate ranking (±10 range) for better performance
    // - Consider Redis/Firestore cache for real-time updates
    
    /*
    // Rank cache to avoid expensive queries
    private var rankCache: [String: (rank: Int, timestamp: Date)] = [:]
    private let rankCacheExpiration: TimeInterval = 1800 // 30 minutes
    
    func calculateUserRankCached(userId: String, totalStamps: Int) async throws -> Int {
        let startTime = Date()
        print("🔍 [FirebaseService] calculateUserRankCached called for userId: \(userId), totalStamps: \(totalStamps)")
        
        // Check cache first
        if let cached = rankCache[userId],
           Date().timeIntervalSince(cached.timestamp) < rankCacheExpiration {
            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ [FirebaseService] Using cached rank for \(userId): #\(cached.rank) (cache age: \(String(format: "%.0f", Date().timeIntervalSince(cached.timestamp)))s, took \(String(format: "%.3f", elapsed))s)")
            return cached.rank
        }
        
        print("🔄 [FirebaseService] Cache miss - fetching from Firestore...")
        
        // Fetch from Firestore
        let rank = try await calculateUserRank(userId: userId, totalStamps: totalStamps)
        
        // Cache the result
        await MainActor.run {
            self.rankCache[userId] = (rank: rank, timestamp: Date())
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [FirebaseService] Rank cached: #\(rank) (total time: \(String(format: "%.3f", elapsed))s)")
        
        return rank
    }
    
    func calculateUserRank(userId: String, totalStamps: Int) async throws -> Int {
        let startTime = Date()
        print("🔍 [FirebaseService] Starting calculateUserRank for userId: \(userId) with \(totalStamps) stamps...")
        
        do {
            print("📡 [FirebaseService] Querying Firestore: users collection where totalStamps > \(totalStamps)...")
            
            // Use getDocuments() instead of count aggregation for better reliability
            // Count aggregation can be slow or fail without proper indexes
            let snapshot = try await db.collection("users")
                .whereField("totalStamps", isGreaterThan: totalStamps)
                .getDocuments() // Default source (cache + server) for offline support
            
            let queryTime = Date().timeIntervalSince(startTime)
            let usersAhead = snapshot.documents.count
            let rank = usersAhead + 1
            
            print("✅ [FirebaseService] Query completed in \(String(format: "%.3f", queryTime))s - Found \(usersAhead) users ahead")
            print("✅ [FirebaseService] Calculated rank: #\(rank) (total time: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s)")
            
            return rank
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("❌ [FirebaseService] Rank calculation failed after \(String(format: "%.3f", elapsed))s")
            print("❌ [FirebaseService] Error: \(error.localizedDescription)")
            
            if let firestoreError = error as NSError? {
                print("❌ [FirebaseService] Error domain: \(firestoreError.domain), code: \(firestoreError.code)")
                print("❌ [FirebaseService] Full error info: \(firestoreError)")
                
                // Check for specific error types
                if firestoreError.domain == "FIRFirestoreErrorDomain" {
                    switch firestoreError.code {
                    case 9: // FAILED_PRECONDITION
                        print("💡 [FirebaseService] Index may be missing - check Firestore console")
                    case 14: // UNAVAILABLE
                        print("💡 [FirebaseService] Network/server unavailable")
                    case 4: // DEADLINE_EXCEEDED
                        print("💡 [FirebaseService] Query timeout - too many users or slow connection")
                    default:
                        break
                    }
                }
            }
            
            throw error
        }
    }
    */
    
    // MARK: - Photo Upload
    // NOTE: Limit to 5 photos per stamp to control Firebase Storage costs
    // Requires Blaze plan (pay-as-you-go) to use Storage
    // 
    // 💰 SCALE CONSIDERATION: For high-traffic apps, consider blob storage + CDN:
    // • Cloudflare R2: $0.015/GB storage, FREE egress (vs Firebase $0.026/GB + $0.12/GB egress)
    // • AWS S3 + CloudFront: Industry standard, more expensive but very reliable
    // • Cloudinary: All-in-one with image transformations (resize on-the-fly, auto-format)
    // Migration path: Store CDN URLs in Firestore, phase out Firebase Storage gradually
    
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
        // 🌐 NOTE: CDN (Cloudflare/CloudFront) would cache at edge servers worldwide for faster access
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
    
    /// Public version of fetchProfilesBatched for use in views
    /// Used by BlockedUsersView to fetch blocked user profiles
    func fetchProfilesBatch(userIds: [String]) async throws -> [UserProfile] {
        guard !userIds.isEmpty else { return [] }
        return try await fetchProfilesBatched(userIds: userIds)
    }
    
    // MARK: - Blocking System
    
    /// Block a user
    /// - Automatically unfollows both ways if following
    /// - Removes from followers/following lists
    /// - Returns true if block was created, false if already blocked
    @discardableResult
    func blockUser(blockerId: String, blockedId: String) async throws -> Bool {
        guard blockerId != blockedId else {
            throw NSError(domain: "FirebaseService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot block yourself"])
        }
        
        // Use transaction to ensure all writes succeed together
        let didBlock = try await db.runTransaction { (transaction, errorPointer) -> Any? in
            // References
            let blockerRef = self.db.collection("users").document(blockerId)
            let blockedRef = self.db.collection("users").document(blockedId)
            let blockRef = blockerRef.collection("blocked").document(blockedId)
            
            // Also need to handle follow relationships (if they exist)
            let blockerFollowingRef = blockerRef.collection("following").document(blockedId)
            let blockedFollowingRef = blockedRef.collection("following").document(blockerId)
            let blockerFollowerRef = blockedRef.collection("followers").document(blockerId)
            let blockedFollowerRef = blockerRef.collection("followers").document(blockedId)
            
            // Read current state
            let blockDoc: DocumentSnapshot
            let blockerDoc: DocumentSnapshot
            let blockedDoc: DocumentSnapshot
            let blockerFollowingDoc: DocumentSnapshot
            let blockedFollowingDoc: DocumentSnapshot
            
            do {
                blockDoc = try transaction.getDocument(blockRef)
                blockerDoc = try transaction.getDocument(blockerRef)
                blockedDoc = try transaction.getDocument(blockedRef)
                blockerFollowingDoc = try transaction.getDocument(blockerFollowingRef)
                blockedFollowingDoc = try transaction.getDocument(blockedFollowingRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            
            // Check if already blocked (idempotency)
            if blockDoc.exists {
                print("⚠️ Already blocked - skipping")
                return false // Already blocked
            }
            
            // Create block document
            let blockData: [String: Any] = [
                "id": blockedId,
                "createdAt": FieldValue.serverTimestamp()
            ]
            transaction.setData(blockData, forDocument: blockRef)
            
            // Handle existing follow relationships
            var blockerFollowingDecrement = 0
            var blockerFollowerDecrement = 0
            var blockedFollowingDecrement = 0
            var blockedFollowerDecrement = 0
            
            // If blocker is following blocked user, unfollow
            if blockerFollowingDoc.exists {
                transaction.deleteDocument(blockerFollowingRef)
                transaction.deleteDocument(blockerFollowerRef)
                blockerFollowingDecrement = 1
                blockedFollowerDecrement = 1
            }
            
            // If blocked user is following blocker, remove that too
            if blockedFollowingDoc.exists {
                transaction.deleteDocument(blockedFollowingRef)
                transaction.deleteDocument(blockedFollowerRef)
                blockedFollowingDecrement = 1
                blockerFollowerDecrement = 1
            }
            
            // Update counts if needed
            if blockerFollowingDecrement > 0 || blockerFollowerDecrement > 0 {
                let currentFollowingCount = max(0, (blockerDoc.data()?["followingCount"] as? Int ?? 0) - blockerFollowingDecrement)
                let currentFollowerCount = max(0, (blockerDoc.data()?["followerCount"] as? Int ?? 0) - blockerFollowerDecrement)
                
                transaction.updateData([
                    "followingCount": currentFollowingCount,
                    "followerCount": currentFollowerCount,
                    "lastActiveAt": FieldValue.serverTimestamp()
                ], forDocument: blockerRef)
            }
            
            if blockedFollowingDecrement > 0 || blockedFollowerDecrement > 0 {
                let currentFollowingCount = max(0, (blockedDoc.data()?["followingCount"] as? Int ?? 0) - blockedFollowingDecrement)
                let currentFollowerCount = max(0, (blockedDoc.data()?["followerCount"] as? Int ?? 0) - blockedFollowerDecrement)
                
                transaction.updateData([
                    "followingCount": currentFollowingCount,
                    "followerCount": currentFollowerCount,
                    "lastActiveAt": FieldValue.serverTimestamp()
                ], forDocument: blockedRef)
            }
            
            return true // Successfully blocked
        } as? Bool ?? false
        
        if didBlock {
            print("✅ User \(blockerId) blocked \(blockedId)")
            // Invalidate caches since relationships changed
            invalidateFollowingCache(userId: blockerId)
            invalidateFollowingCache(userId: blockedId)
        }
        
        return didBlock
    }
    
    /// Unblock a user
    /// Returns true if unblock was performed, false if wasn't blocked
    @discardableResult
    func unblockUser(blockerId: String, blockedId: String) async throws -> Bool {
        let blockRef = db
            .collection("users")
            .document(blockerId)
            .collection("blocked")
            .document(blockedId)
        
        let document = try await blockRef.getDocument()
        
        // Check if actually blocked (idempotency)
        if !document.exists {
            print("⚠️ Not blocked - skipping")
            return false
        }
        
        // Delete block relationship
        try await blockRef.delete()
        
        print("✅ User \(blockerId) unblocked \(blockedId)")
        return true
    }
    
    /// Check if a user has blocked another user
    func isBlocking(blockerId: String, blockedId: String) async throws -> Bool {
        let docRef = db
            .collection("users")
            .document(blockerId)
            .collection("blocked")
            .document(blockedId)
        
        let document = try await docRef.getDocument()
        return document.exists
    }
    
    /// Fetch list of blocked user IDs for a user
    func fetchBlockedUserIds(userId: String, limit: Int = 1000) async throws -> [String] {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("blocked")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.map { $0.documentID }
    }
    
    // MARK: - User Search
    
    /// Search for users by username or display name (for finding users to follow)
    /// Filters out users that current user has blocked or is blocked by
    ///
    /// MVP: Simple username prefix search with blocking support
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
    func searchUsers(query: String, currentUserId: String? = nil, limit: Int = 20) async throws -> [UserProfile] {
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
        
        var profiles = try usernameSnapshot.documents.compactMap { doc -> UserProfile? in
            try doc.data(as: UserProfile.self)
        }
        
        // Filter out blocked users if currentUserId is provided
        if let userId = currentUserId {
            // Fetch blocked user IDs (users that current user has blocked)
            let blockedIds = try await fetchBlockedUserIds(userId: userId)
            let blockedSet = Set(blockedIds)
            
            // Filter out users that current user has blocked
            // Note: We don't check if other users have blocked the current user because:
            // 1. It's a privacy violation to let users discover who blocked them
            // 2. Firestore security rules correctly prevent reading other users' blocked lists
            profiles = profiles.filter { profile in
                !blockedSet.contains(profile.id)
            }
        }
        
        return profiles
    }
    
    // MARK: - Feed System
    
    /// Fetch recent stamps from users that the current user is following
    /// Returns tuples of (userProfile, collectedStamp) for rendering in feed
    /// Filters out blocked users automatically
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
        let overallStart = CFAbsoluteTimeGetCurrent()
        
        // 1. Get current user's profile (for including in feed)
        let profileStart = CFAbsoluteTimeGetCurrent()
        let currentUserProfile = try await fetchUserProfile(userId: userId)
        let profileTime = CFAbsoluteTimeGetCurrent() - profileStart
        print("⏱️ [FirebaseService] User profile fetch: \(String(format: "%.3f", profileTime))s")
        
        // 2. Get blocked user IDs to filter them out
        let blockedStart = CFAbsoluteTimeGetCurrent()
        let blockedIds = try await fetchBlockedUserIds(userId: userId)
        let blockedSet = Set(blockedIds)
        let blockedTime = CFAbsoluteTimeGetCurrent() - blockedStart
        print("⏱️ [FirebaseService] Blocked users fetch: \(String(format: "%.3f", blockedTime))s (\(blockedIds.count) blocked)")
        
        // 3. Get list of users being followed (uses cache if available)
        let followingStart = CFAbsoluteTimeGetCurrent()
        var followingProfiles = try await fetchFollowing(userId: userId, useCache: true)
        
        // Filter out blocked users from following list
        followingProfiles = followingProfiles.filter { !blockedSet.contains($0.id) }
        
        let followingTime = CFAbsoluteTimeGetCurrent() - followingStart
        print("⏱️ [FirebaseService] Following list fetch: \(String(format: "%.3f", followingTime))s (\(followingProfiles.count) users after blocking filter)")
        
        // 4. Combine current user + followed users for feed
        // This ensures "All" tab shows your posts + followed users' posts
        let allProfiles = [currentUserProfile] + followingProfiles
        
        // 5. Use smaller initial batch for faster first load
        // Fetch from first 15 users only (150 reads) instead of all 50+ (500+ reads)
        // This reduces initial load time from ~5s to ~1-2s
        // Note: Current user is ALWAYS included (not subject to batch limit)
        let batchSize = min(initialBatchSize + 1, allProfiles.count) // +1 for current user
        let profilesToFetch = Array(allProfiles.prefix(batchSize))
        
        print("📱 Fetching feed from \(batchSize) users (\(followingProfiles.count) followed + current user, fast initial load)...")
        
        // 6. Fetch stamps from users in parallel for better performance
        var allFeedItems: [(profile: UserProfile, stamp: CollectedStamp)] = []
        
        let stampsStart = CFAbsoluteTimeGetCurrent()
        print("🔄 [FirebaseService] Fetching collected stamps from \(profilesToFetch.count) users in parallel...")
        
        // Use TaskGroup for parallel fetching
        await withTaskGroup(of: (UserProfile, [CollectedStamp]).self) { group in
            for (index, profile) in profilesToFetch.enumerated() {
                group.addTask {
                    let userStart = CFAbsoluteTimeGetCurrent()
                    do {
                        // Fetch recent stamps for this user (10 per user for balanced feed)
                        let stamps = try await self.fetchCollectedStamps(for: profile.id, limit: stampsPerUser)
                        let userTime = CFAbsoluteTimeGetCurrent() - userStart
                        print("✅ [FirebaseService] User \(index + 1)/\(profilesToFetch.count) (@\(profile.username)): \(stamps.count) stamps in \(String(format: "%.3f", userTime))s")
                        return (profile, stamps)
                    } catch {
                        let userTime = CFAbsoluteTimeGetCurrent() - userStart
                        print("⚠️ [FirebaseService] User \(index + 1)/\(profilesToFetch.count) (@\(profile.username)): Failed after \(String(format: "%.3f", userTime))s - \(error.localizedDescription)")
                        return (profile, [])
                    }
                }
            }
            
            // Collect results
            var completed = 0
            for await (profile, stamps) in group {
                completed += 1
                for stamp in stamps {
                    allFeedItems.append((profile: profile, stamp: stamp))
                }
                print("📊 [FirebaseService] Progress: \(completed)/\(profilesToFetch.count) users completed")
            }
        }
        
        let stampsTime = CFAbsoluteTimeGetCurrent() - stampsStart
        print("⏱️ [FirebaseService] All user stamps fetched in \(String(format: "%.3f", stampsTime))s")
        
        // 7. Sort by collection date (most recent first)
        let sortStart = CFAbsoluteTimeGetCurrent()
        allFeedItems.sort { $0.stamp.collectedDate > $1.stamp.collectedDate }
        let sortTime = CFAbsoluteTimeGetCurrent() - sortStart
        
        // 8. Limit total items returned (pagination support)
        if allFeedItems.count > limit {
            allFeedItems = Array(allFeedItems.prefix(limit))
        }
        
        let overallTime = CFAbsoluteTimeGetCurrent() - overallStart
        print("✅ Fetched \(allFeedItems.count) feed items from \(batchSize) users in \(String(format: "%.3f", overallTime))s (sort: \(String(format: "%.3f", sortTime))s)")
        
        return allFeedItems
    }
    
    // MARK: - Likes & Comments System
    
    /// Like a post (create or toggle like)
    /// Returns true if liked, false if unliked
    @discardableResult
    func toggleLike(postId: String, stampId: String, userId: String, postOwnerId: String) async throws -> Bool {
        let likeRef = db.collection("likes").document("\(userId)_\(postId)")
        let postRef = db.collection("users").document(postOwnerId).collection("collected_stamps").document(stampId)
        
        // Use transaction to make it atomic - both operations succeed or both fail
        let result = try await db.runTransaction({ (transaction, errorPointer) -> Bool in
            let likeDoc: DocumentSnapshot
            do {
                likeDoc = try transaction.getDocument(likeRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return false
            }
            
            if likeDoc.exists {
                // Unlike: delete the like document and decrement count
                transaction.deleteDocument(likeRef)
                transaction.updateData([
                    "likeCount": FieldValue.increment(Int64(-1))
                ], forDocument: postRef)
                return false
            } else {
                // Like: create the like document and increment count
                let like = Like(
                    userId: userId,
                    postId: postId,
                    stampId: stampId,
                    postOwnerId: postOwnerId,
                    createdAt: Date()
                )
                
                do {
                    try transaction.setData(from: like, forDocument: likeRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return false
                }
                
                transaction.updateData([
                    "likeCount": FieldValue.increment(Int64(1))
                ], forDocument: postRef)
                return true
            }
        })
        
        let isLiked = (result as? Bool) ?? false
        print(isLiked ? "✅ Liked post: \(postId)" : "✅ Unliked post: \(postId)")
        return isLiked
    }
    
    /// Check if current user has liked a post
    func hasLiked(postId: String, userId: String) async throws -> Bool {
        let likeRef = db.collection("likes").document("\(userId)_\(postId)")
        let document = try await likeRef.getDocument()
        return document.exists
    }
    
    /// Fetch like count for a post
    func fetchLikeCount(postId: String) async throws -> Int {
        let snapshot = try await db.collection("likes")
            .whereField("postId", isEqualTo: postId)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    /// Fetch users who liked a post
    func fetchPostLikes(postId: String, limit: Int = 50) async throws -> [UserProfile] {
        let snapshot = try await db.collection("likes")
            .whereField("postId", isEqualTo: postId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        let userIds = snapshot.documents.compactMap { doc -> String? in
            try? doc.data(as: Like.self).userId
        }
        
        guard !userIds.isEmpty else { return [] }
        
        // Batch fetch user profiles
        return try await fetchProfilesBatched(userIds: userIds)
    }
    
    /// Add a comment to a post
    @discardableResult
    func addComment(postId: String, stampId: String, postOwnerId: String, userId: String, text: String, userProfile: UserProfile) async throws -> Comment {
        let commentRef = db.collection("comments").document()
        
        let comment = Comment(
            userId: userId,
            postId: postId,
            stampId: stampId,
            postOwnerId: postOwnerId,
            text: text,
            userDisplayName: userProfile.displayName,
            userUsername: userProfile.username,
            userAvatarUrl: userProfile.avatarUrl,
            createdAt: Date()
        )
        
        try commentRef.setData(from: comment)
        
        // Increment comment count on post
        let postRef = db.collection("users").document(postOwnerId).collection("collected_stamps").document(stampId)
        try await postRef.updateData([
            "commentCount": FieldValue.increment(Int64(1))
        ])
        
        print("✅ Added comment to post: \(postId)")
        return comment
    }
    
    /// Fetch comments for a post
    func fetchComments(postId: String, limit: Int = 50) async throws -> [Comment] {
        let snapshot = try await db.collection("comments")
            .whereField("postId", isEqualTo: postId)
            .order(by: "createdAt", descending: false) // Oldest first (chronological)
            .limit(to: limit)
            .getDocuments()
        
        let comments = snapshot.documents.compactMap { doc -> Comment? in
            try? doc.data(as: Comment.self)
        }
        
        return comments
    }
    
    /// Delete a comment (only by comment author or post owner)
    func deleteComment(commentId: String, postOwnerId: String, stampId: String) async throws {
        print("🗑️ Attempting to delete comment: \(commentId) from post: \(postOwnerId)-\(stampId)")
        
        let commentRef = db.collection("comments").document(commentId)
        
        // First, delete the comment document
        do {
            try await commentRef.delete()
            print("✅ Successfully deleted comment document: \(commentId)")
        } catch {
            print("❌ Failed to delete comment document: \(error.localizedDescription)")
            throw error
        }
        
        // Then, decrement comment count on post
        let postRef = db.collection("users").document(postOwnerId).collection("collected_stamps").document(stampId)
        do {
            try await postRef.updateData([
                "commentCount": FieldValue.increment(Int64(-1))
            ])
            print("✅ Successfully decremented comment count on post")
        } catch {
            print("⚠️ Failed to decrement comment count (comment was deleted but count may be off): \(error.localizedDescription)")
            // Don't throw here - comment deletion succeeded, count decrement is less critical
        }
        
        print("✅ Completed comment deletion: \(commentId)")
    }
    
    /// Fetch comment count for a post
    func fetchCommentCount(postId: String) async throws -> Int {
        let snapshot = try await db.collection("comments")
            .whereField("postId", isEqualTo: postId)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Feedback System
    
    /// Submit user feedback or bug report to Firestore
    /// Admins can view feedback in Firebase Console under "feedback" collection
    ///
    /// - Parameters:
    ///   - userId: ID of user submitting feedback
    ///   - type: Type of feedback (Bug Report, General Feedback, Feature Request)
    ///   - message: The feedback message
    func submitFeedback(userId: String, type: String, message: String) async throws {
        // Fetch user profile for additional context
        let userProfile = try await fetchUserProfile(userId: userId)
        
        // Get device and app info
        let deviceInfo = [
            "device": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        
        // Create feedback document
        let feedbackRef = db.collection("feedback").document()
        
        let feedbackData: [String: Any] = [
            "userId": userId,
            "userEmail": userProfile.username + "@stampbook.app", // Placeholder - you might want real email
            "username": userProfile.username,
            "displayName": userProfile.displayName,
            "type": type,
            "message": message,
            "deviceInfo": deviceInfo,
            "timestamp": FieldValue.serverTimestamp(),
            "status": "new" // Admin can mark as "reviewed", "in-progress", "resolved"
        ]
        
        try await feedbackRef.setData(feedbackData)
        
        print("✅ Feedback submitted: \(feedbackRef.documentID)")
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

