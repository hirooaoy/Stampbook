import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service to handle all Firebase operations (Firestore & Storage)
class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    // MARK: - Request Deduplication & Caching
    
    /// Track in-flight profile fetches to prevent duplicate requests
    /// When multiple views request the same profile simultaneously, only one Firebase read occurs
    private var inFlightProfileFetches: [String: Task<UserProfile, Error>] = [:]
    private let profileFetchQueue = DispatchQueue(label: "com.stampbook.profileFetchQueue")
    
    /// Time-based profile cache to prevent redundant fetches
    /// Profiles fetched within the last 5 minutes are returned from cache
    /// Cache invalidation happens automatically on profile updates
    private var profileCache: [String: (profile: UserProfile, timestamp: Date)] = [:]
    private let profileCacheExpiration: TimeInterval = 300 // 5 minutes (optimized from 60s)
    
    private init() {
        // Configure offline persistence
        // NOTE: For fresh installs with no cache, offline persistence can cause
        // 10+ second delays while Firestore waits for backend. This is acceptable
        // because once cache is populated, subsequent launches are instant.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
        
        Logger.info("Offline persistence enabled (cache will populate on first sync)", category: "FirebaseService")
    }
    
    // MARK: - Collected Stamps Sync
    
    /// Fetch collected stamps for a user from Firestore
    /// - Parameter userId: The user ID to fetch stamps for
    /// - Parameter limit: Maximum number of stamps to fetch (default: 50, nil = all)
    /// - Parameter afterDate: Optional cursor for pagination (fetch stamps before this date)
    /// - Returns: Array of collected stamps, sorted by collection date (most recent first)
    ///
    /// **PERFORMANCE NOTE:** Always use a limit when fetching for feed/social features.
    /// Fetching all stamps is only needed for the user's own stamp collection view.
    func fetchCollectedStamps(for userId: String, limit: Int? = nil, afterDate: Date? = nil) async throws -> [CollectedStamp] {
        var query = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .order(by: "collectedDate", descending: true)
        
        // Apply pagination cursor if provided
        if let afterDate = afterDate {
            query = query.whereField("collectedDate", isLessThan: afterDate)
        }
        
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
    
    /// Fetch a single collected stamp by stampId (for notifications/deep links)
    /// - Parameter userId: The user ID who collected the stamp
    /// - Parameter stampId: The stamp ID to fetch
    /// - Returns: The collected stamp, or nil if not found
    ///
    /// **PERFORMANCE:** Direct document read (1 read) instead of collection query
    func fetchCollectedStamp(userId: String, stampId: String) async throws -> CollectedStamp? {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stampId)
        
        let document = try await docRef.getDocument()
        
        guard document.exists else {
            return nil
        }
        
        return try? document.data(as: CollectedStamp.self)
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
    /// Fetch all stamps from Firestore
    /// - Parameter forceRefresh: If true, bypass cache and fetch from server
    /// - Returns: Array of all stamps (no filtering - StampsManager handles that)
    func fetchStamps(forceRefresh: Bool = false) async throws -> [Stamp] {
        let source: FirestoreSource = forceRefresh ? .server : .default
        
        let snapshot = try await db
            .collection("stamps")
            .getDocuments(source: source)
        
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
        
        #if DEBUG
        let overallStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Firestore 'in' queries support max 10 items
        // Batch into chunks of 10
        let batchSize = 10
        let batches = stride(from: 0, to: ids.count, by: batchSize).map {
            Array(ids[$0..<min($0 + batchSize, ids.count)])
        }
        
        #if DEBUG
        print("🔄 [FirebaseService] Fetching \(ids.count) stamps in \(batches.count) parallel batches...")
        #endif
        
        // Execute all batches in PARALLEL for better performance
        let allStamps = try await withThrowingTaskGroup(of: [Stamp].self, returning: [Stamp].self) { group in
            for (index, batchIds) in batches.enumerated() {
                group.addTask {
                    #if DEBUG
                    let batchStart = CFAbsoluteTimeGetCurrent()
                    print("📦 [FirebaseService] Batch \(index + 1)/\(batches.count): Fetching \(batchIds.count) stamps...")
                    #endif
                    
                    let snapshot = try await self.db
                        .collection("stamps")
                        .whereField(FieldPath.documentID(), in: batchIds)
                        .getDocuments()
                    
                    let stamps = await MainActor.run {
                        snapshot.documents.compactMap { doc -> Stamp? in
                            try? doc.data(as: Stamp.self)
                        }
                    }
                    
                    #if DEBUG
                    let batchTime = CFAbsoluteTimeGetCurrent() - batchStart
                    print("✅ [FirebaseService] Batch \(index + 1)/\(batches.count): Completed in \(String(format: "%.3f", batchTime))s (\(stamps.count) stamps)")
                    #endif
                    
                    return stamps
                }
            }
            
            var allStamps: [Stamp] = []
            for try await stamps in group {
                allStamps.append(contentsOf: stamps)
            }
            return allStamps
        }
        
        #if DEBUG
        let overallTime = CFAbsoluteTimeGetCurrent() - overallStart
        print("⏱️ [FirebaseService] Total fetchStampsByIds: \(String(format: "%.3f", overallTime))s (\(allStamps.count)/\(ids.count) stamps)")
        #endif
        
        return allStamps
    }
    
    // ==================== FUTURE OPTIMIZATION ====================
    // Region-based stamp fetching removed for MVP
    // Restore from git history when stamp count exceeds 2000
    // See StampsManager.swift for full documentation
    // ==================== FUTURE OPTIMIZATION ====================
    
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
    /// - Parameter forceRefresh: If true, bypass cache and fetch from server
    /// - Returns: Array of all collections
    ///
    /// **CURRENT STRATEGY (MVP):**
    /// Always force refresh (called with forceRefresh: true in StampsManager)
    /// - Ensures users see new collections immediately
    /// - Simple, works well for 7 collections at MVP scale
    ///
    /// **FUTURE OPTIMIZATION (1000+ users, 50+ collections):**
    /// Implement hybrid TTL + Schema Versioning:
    /// 1. TTL: Refresh if cache older than 6-24 hours (content updates)
    /// 2. Versioning: Refresh if schema changed (structure updates)
    /// 3. See StampsManager.loadCollections() for implementation guide
    func fetchCollections(forceRefresh: Bool = false) async throws -> [Collection] {
        let source: FirestoreSource = forceRefresh ? .server : .default
        
        let snapshot = try await db
            .collection("collections")
            .getDocuments(source: source)
        
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
    
    /// Get user's rank for a specific stamp (what number collector they were)
    /// 
    /// How it works: Like signing a guestbook - if you're the 23rd person to collect a stamp,
    /// you'll always be #23. Your rank never changes, just like your position in a concert line.
    /// We just read the collector list and find your position - simple and fast!
    /// 
    /// Returns the user's position in the collector order (1 = first to collect, 2 = second, etc.)
    /// This is efficient because it only reads one document and finds the index in an array
    func getUserRankForStamp(stampId: String, userId: String) async throws -> Int? {
        let stats = try await fetchStampStatistics(stampId: stampId)
        
        if let index = stats.collectorUserIds.firstIndex(of: userId) {
            return index + 1 // Rank is 1-indexed
        }
        
        return nil
    }
    
    // MARK: - User Profile Management
    
    /// Check if a user profile exists in Firestore
    /// Used to detect orphaned auth states or verify profile existence
    /// 
    /// - Returns: Optional Bool
    ///   - `true`: Profile exists
    ///   - `false`: Profile definitely doesn't exist (verified with server)
    ///   - `nil`: Couldn't determine (network error, offline, etc.)
    func userProfileExists(userId: String) async -> Bool? {
        do {
            let docRef = db.collection("users").document(userId)
            let document = try await docRef.getDocument()
            return document.exists
        } catch let error as NSError {
            // Check if this is a network/offline error
            // Domain: NSURLErrorDomain (network) or FIRFirestoreErrorDomain
            if error.domain == NSURLErrorDomain || 
               error.domain == "FIRFirestoreErrorDomain" && (error.code == 14 || error.code == 8) {
                // 14 = UNAVAILABLE (offline), 8 = DEADLINE_EXCEEDED (timeout)
                Logger.warning("Cannot check profile existence - network unavailable (offline or timeout)", category: "FirebaseService")
                return nil // Can't determine - network issue
            }
            
            // Other errors (permissions, invalid data, etc.) - treat as not exists
            Logger.error("Error checking user profile existence", error: error, category: "FirebaseService")
            return false
        }
    }
    
    /// Fetch user profile from Firestore
    /// Used when loading a user's profile data
    func fetchUserProfile(userId: String, forceRefresh: Bool = false) async throws -> UserProfile {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔍 [FirebaseService] fetchUserProfile(\(userId)) started")
        #endif
        
        // Check time-based cache first (unless forcing refresh)
        if !forceRefresh {
            let cachedProfile = profileFetchQueue.sync { () -> UserProfile? in
                guard let cached = profileCache[userId] else { return nil }
                let age = Date().timeIntervalSince(cached.timestamp)
                
                // Return cached profile if fresh (< 5 minutes old)
                if age < profileCacheExpiration {
                    #if DEBUG
                    print("⚡️ [FirebaseService] Using cached profile (age: \(String(format: "%.1f", age))s / 300s)")
                    #endif
                    return cached.profile
                }
                
                // Cache expired, remove it
                #if DEBUG
                print("🗑️ [FirebaseService] Cache expired (age: \(String(format: "%.1f", age))s > 300s), fetching fresh profile")
                #endif
                profileCache.removeValue(forKey: userId)
                return nil
            }
            
            if let profile = cachedProfile {
                return profile
            }
        } else {
            #if DEBUG
            print("🔄 [FirebaseService] Force refresh requested, bypassing cache")
            #endif
        }
        
        // ATOMIC: Check for existing task AND create new task if needed
        // This prevents race condition where multiple callers create duplicate tasks
        let fetchTask: Task<UserProfile, Error> = profileFetchQueue.sync {
            // Check if there's already a fetch in progress
            if let existingTask = inFlightProfileFetches[userId] {
                #if DEBUG
                print("⏱️ [FirebaseService] Waiting for in-flight profile fetch")
                #endif
                return existingTask
            }
            
            // Create and store new task atomically
            let newTask = Task<UserProfile, Error> {
                let docRef = self.db.collection("users").document(userId)
                
                #if DEBUG
                print("📡 [FirebaseService] Calling getDocument()...")
                #endif
                
                let document = try await docRef.getDocument()
                
                #if DEBUG
                let fetchTime = CFAbsoluteTimeGetCurrent() - startTime
                print("⏱️ [FirebaseService] User profile fetch: \(String(format: "%.3f", fetchTime))s")
                #endif
                
                if let profile = try? document.data(as: UserProfile.self) {
                    // Cache immediately after parsing, inside the task (runs only once)
                    self.profileFetchQueue.sync {
                        self.profileCache[userId] = (profile: profile, timestamp: Date())
                        self.inFlightProfileFetches.removeValue(forKey: userId)
                    }
                    
                    #if DEBUG
                    print("💾 [FirebaseService] Profile cached for \(userId)")
                    print("✅ [FirebaseService] Profile parsed successfully: @\(profile.username)")
                    #endif
                    
                    return profile
                } else {
                    // Clean up on parse failure
                    _ = self.profileFetchQueue.sync {
                        self.inFlightProfileFetches.removeValue(forKey: userId)
                    }
                    Logger.error("Profile document exists but failed to parse", category: "FirebaseService")
                    throw NSError(domain: "FirebaseService", code: 404, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
                }
            }
            
            inFlightProfileFetches[userId] = newTask
            return newTask
        }
        
        // Wait for fetch to complete and return (caching already done inside Task)
        return try await fetchTask.value
    }
    
    /// Invalidate cached profile for a user
    /// Call this when a profile is updated to force fresh fetch next time
    func invalidateProfileCache(userId: String) {
        profileFetchQueue.sync {
            _ = profileCache.removeValue(forKey: userId)
        }
        #if DEBUG
        print("🗑️ [FirebaseService] Invalidated profile cache for \(userId)")
        #endif
    }
    
    /// Create or update user profile in Firestore
    /// Uses merge:true to only update provided fields
    /// Automatically invalidates cache after update
    func saveUserProfile(_ profile: UserProfile) async throws {
        let docRef = db.collection("users").document(profile.id)
        try docRef.setData(from: profile, merge: true)
        
        // Invalidate cache so next fetch gets fresh data
        invalidateProfileCache(userId: profile.id)
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
        
        // Invalidate cache so next fetch gets fresh data
        invalidateProfileCache(userId: userId)
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
            Logger.error("Rank calculation failed after \(String(format: "%.3f", elapsed))s", error: error, category: "FirebaseService")
            
            if let firestoreError = error as NSError? {
                Logger.error("Error domain: \(firestoreError.domain), code: \(firestoreError.code)", category: "FirebaseService")
                Logger.error("Full error info: \(firestoreError)", category: "FirebaseService")
                
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
    // 🎯 ACTION TRIGGER: Migrate to CDN when image bandwidth > 100GB/month OR 500+ users
    
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
                Logger.warning("Could not delete old profile photo: \(error.localizedDescription)", category: "FirebaseService")
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
        
        // Upload to Firebase Storage and get download URL
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
        
        // Upload to Firebase Storage and get download URL
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
    // Following list rarely changes (only on follow/unfollow), so longer TTL is safe
    // Cache invalidation happens automatically via invalidateFollowingCache()
    private var followingCache: [String: (profiles: [UserProfile], timestamp: Date)] = [:]
    private let followingCacheExpiration: TimeInterval = 7200 // 2 hours (optimized from 30min)
    
    // MARK: - Follow/Unfollow System
    
    /// Follow a user (simple approach: just create the relationship document)
    /// For MVP scale (<100 users), we count subcollections on-demand instead of maintaining denormalized counts
    /// Returns true if follow was created, false if already following
    @discardableResult
    func followUser(followerId: String, followeeId: String) async throws -> Bool {
        guard followerId != followeeId else {
            throw NSError(domain: "FirebaseService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        let followingRef = db
            .collection("users")
            .document(followerId)
            .collection("following")
            .document(followeeId)
        
        // Check if already following (idempotency)
        let existingDoc = try await followingRef.getDocument()
        if existingDoc.exists {
            Logger.warning("Already following - skipping", category: "FirebaseService")
            return false
        }
        
        // Create follow relationship
        let followData: [String: Any] = [
            "id": followeeId,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        try await followingRef.setData(followData)
        
        print("✅ User \(followerId) followed \(followeeId)")
        // Invalidate following cache since list changed
        invalidateFollowingCache(userId: followerId)
        
        return true
    }
    
    /// Unfollow a user (simple approach: just delete the relationship document)
    /// For MVP scale (<100 users), we count subcollections on-demand instead of maintaining denormalized counts
    /// Returns true if unfollow was performed, false if wasn't following
    @discardableResult
    func unfollowUser(followerId: String, followeeId: String) async throws -> Bool {
        let followingRef = db
            .collection("users")
            .document(followerId)
            .collection("following")
            .document(followeeId)
        
        // Check if actually following (idempotency)
        let existingDoc = try await followingRef.getDocument()
        if !existingDoc.exists {
            Logger.warning("Not following - skipping", category: "FirebaseService")
            return false
        }
        
        // Delete follow relationship
        try await followingRef.delete()
        
        print("✅ User \(followerId) unfollowed \(followeeId)")
        // Invalidate following cache since list changed
        invalidateFollowingCache(userId: followerId)
        
        return true
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
    
    /// Count how many followers a user has (DEPRECATED - use denormalized count instead)
    /// 
    /// ⚠️ DEPRECATED: This expensive collection group query is no longer needed
    /// Use profile.followerCount instead (synced by Cloud Function updateFollowCounts)
    /// 
    /// Kept for backwards compatibility and reconciliation scripts only
    @available(*, deprecated, message: "Use profile.followerCount instead - counts are now denormalized by Cloud Function")
    func fetchFollowerCount(userId: String) async throws -> Int {
        // Query across all users who follow this user
        // This is efficient for <100 users
        let snapshot = try await db
            .collectionGroup("following")
            .whereField("id", isEqualTo: userId)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    /// Count how many users someone is following (DEPRECATED - use denormalized count instead)
    /// 
    /// ⚠️ DEPRECATED: This query is no longer needed
    /// Use profile.followingCount instead (synced by Cloud Function updateFollowCounts)
    /// 
    /// Kept for backwards compatibility and reconciliation scripts only
    @available(*, deprecated, message: "Use profile.followingCount instead - counts are now denormalized by Cloud Function")
    func fetchFollowingCount(userId: String) async throws -> Int {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("following")
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    /// Fetch list of user IDs who follow this user (for displaying followers list)
    /// Queries across all users' following subcollections
    func fetchFollowers(userId: String, limit: Int = 100) async throws -> [UserProfile] {
        // Query collection group to find all users who have this user in their following subcollection
        let snapshot = try await db
            .collectionGroup("following")
            .whereField("id", isEqualTo: userId)
            .limit(to: limit)
            .getDocuments()
        
        // Extract the user IDs who are following this user (from the document path)
        let followerIds = snapshot.documents.compactMap { doc -> String? in
            // Document path is: users/{followerId}/following/{followeeId}
            let components = doc.reference.path.components(separatedBy: "/")
            guard components.count >= 2, components[0] == "users" else { return nil }
            return components[1] // The followerId
        }
        
        guard !followerIds.isEmpty else {
            return []
        }
        
        // Batch fetch profiles
        let profiles = try await fetchProfilesBatched(userIds: followerIds)
        return profiles
    }
    
    /// Fetch list of users that a user is following
    /// Uses caching to reduce repeated queries (30 minute expiration)
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
        
        // Batch fetch profiles
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
    ///
    /// **USAGE:**
    /// - Following/followers lists (efficient batch loading)
    /// - Notification actor profiles (94% cost reduction vs individual fetches)
    /// - Any scenario requiring multiple profiles at once
    ///
    /// **COST:** ~1 read per 10 profiles (vs 1 read per profile individually)
    func fetchProfilesBatched(userIds: [String]) async throws -> [UserProfile] {
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
    
    // MARK: - User Search
    
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
        
        let profiles = try usernameSnapshot.documents.compactMap { doc -> UserProfile? in
            try doc.data(as: UserProfile.self)
        }
        
        return profiles
    }
    
    // MARK: - Feed System
    
    /// Fetch recent stamps from users that the current user is following (Instagram-style chronological feed)
    /// Returns tuples of (userProfile, collectedStamp) for rendering in feed
    /// 
    /// ARCHITECTURE: Instagram-style chronological pagination
    /// - Fetches posts chronologically across ALL users (not per-user limits)
    /// - Single query sorts by timestamp (database-side, very efficient)
    /// - Pagination cursor continues from last timestamp
    /// - Infinite scroll backwards through history ✅
    /// 
    /// COST COMPARISON (100 users, each with 100 stamps):
    /// - Old approach (5 per user): 500 reads per load 💸
    /// - New approach (20 chronological): 20 reads per load 💚
    /// - 96% cost reduction!
    ///
    /// REQUIRES COMPOSITE INDEX:
    /// Collection group: collected_stamps
    /// Fields: userId (Ascending), collectedDate (Descending)
    func fetchFollowingFeed(userId: String, limit: Int = 20, stampsPerUser: Int = 10, initialBatchSize: Int = 15, afterDate: Date? = nil) async throws -> [(profile: UserProfile, stamp: CollectedStamp)] {
        #if DEBUG
        let overallStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // 1. Get list of users to include in feed (current user + following)
        #if DEBUG
        let profileStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // NOTE: AuthManager also fetches currentUserProfile on app launch
        // This creates 2 fetches of same profile (AuthManager + FeedManager)
        // Test scenario (following yourself) creates 3rd fetch in followingProfiles
        // Deduplication happens in profileMap Dictionary below (prevents UI issues)
        // Not worth fixing at MVP scale - costs 1-2 extra reads per feed load
        let currentUserProfile = try await fetchUserProfile(userId: userId)
        let followingProfiles = try await fetchFollowing(userId: userId, useCache: true)
        
        #if DEBUG
        let profileTime = CFAbsoluteTimeGetCurrent() - profileStart
        print("⏱️ [FirebaseService] Profiles fetched: \(String(format: "%.3f", profileTime))s (1 current + \(followingProfiles.count) following)")
        #endif
        
        // 2. Create lookup map for user profiles
        let allProfiles = [currentUserProfile] + followingProfiles
        let profileMap = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0) })
        let userIds = Array(profileMap.keys)
        
        // 3. Fetch stamps chronologically across ALL users (Instagram-style)
        #if DEBUG
        let queryStart = CFAbsoluteTimeGetCurrent()
        print("🔄 [FirebaseService] Fetching \(limit) most recent stamps from \(userIds.count) users chronologically...")
        #endif
        
        var allFeedItems: [(profile: UserProfile, stamp: CollectedStamp)] = []
        
        // IMPORTANT: Firestore `in` query supports max 10 items
        // For MVP (<10 followed users), use single query
        // For scale (>10 users), batch the queries
        let maxBatchSize = 10
        let userIdBatches = stride(from: 0, to: userIds.count, by: maxBatchSize).map {
            Array(userIds[$0..<min($0 + maxBatchSize, userIds.count)])
        }
        
        // Fetch from each batch and combine
        for (batchIndex, batchUserIds) in userIdBatches.enumerated() {
            #if DEBUG
            print("📦 [FirebaseService] Batch \(batchIndex + 1)/\(userIdBatches.count): Querying \(batchUserIds.count) users...")
            #endif
            
            // Build query: collection group of all collected_stamps, filtered by userId
            let query = db.collectionGroup("collected_stamps")
                .whereField("userId", in: batchUserIds)
                .order(by: "collectedDate", descending: true)
                .limit(to: limit * 2) // Fetch extra to ensure enough after filtering
            
            let snapshot = try await query.getDocuments()
            
            for doc in snapshot.documents {
                guard let stamp = try? doc.data(as: CollectedStamp.self),
                      let profile = profileMap[stamp.userId] else {
                    continue
                }
                
                // Apply afterDate filter if provided
                if let afterDate = afterDate, stamp.collectedDate >= afterDate {
                    continue
                }
                
                allFeedItems.append((profile: profile, stamp: stamp))
            }
            
            #if DEBUG
            print("✅ [FirebaseService] Batch \(batchIndex + 1): Found \(snapshot.documents.count) stamps")
            #endif
        }
        
        #if DEBUG
        let queryTime = CFAbsoluteTimeGetCurrent() - queryStart
        print("⏱️ [FirebaseService] Query completed in \(String(format: "%.3f", queryTime))s (\(allFeedItems.count) stamps)")
        #endif
        
        // 4. Sort by date (already mostly sorted, but batches might be mixed)
        allFeedItems.sort { $0.stamp.collectedDate > $1.stamp.collectedDate }
        
        // 5. Limit to requested amount
        if allFeedItems.count > limit {
            allFeedItems = Array(allFeedItems.prefix(limit))
        }
        
        #if DEBUG
        let overallTime = CFAbsoluteTimeGetCurrent() - overallStart
        print("✅ [Instagram-style] Fetched \(allFeedItems.count) chronological posts in \(String(format: "%.3f", overallTime))s")
        #endif
        
        return allFeedItems
    }
    
    // MARK: - Likes & Comments System
    
    // TODO: PHASE 2 - Add reconciliation mechanism
    // Create reconcile_like_comment_counts.js to periodically verify:
    // - Count actual likes in subcollection
    // - Compare to stored likeCount
    // - Fix drift and log discrepancies
    // Run weekly or on-demand. See docs/LIKE_COUNT_FIX_ROADMAP.md
    
    // TODO: PHASE 2 - Add monitoring/alerting
    // Detect negative counts automatically:
    // - Option A: Add to reconciliation script (console.error + notification)
    // - Option B: Firebase Function trigger on write (validates counts >= 0)
    // See docs/LIKE_COUNT_FIX_ROADMAP.md
    
    // TODO: PHASE 3 - Move to Cloud Functions (at 1000+ users)
    // Replace client-side increment with server-side Cloud Function:
    // - exports.toggleLike = functions.https.onCall(...)
    // - Server validates auth and enforces business rules
    // - Prevents client manipulation
    // - Single source of logic
    // See docs/LIKE_COUNT_FIX_ROADMAP.md
    
    // TODO: PHASE 3 - Automated reconciliation (at 1000+ users)
    // Add scheduled Cloud Function to run daily:
    // - exports.dailyReconciliation = functions.pubsub.schedule('0 3 * * *')
    // - Automatically fixes drift without manual intervention
    // - Logs results for monitoring
    // See docs/LIKE_COUNT_FIX_ROADMAP.md
    
    /// Like a post (create or toggle like)
    /// Returns true if liked, false if unliked
    ///
    /// ✅ PHASE 1 COMPLETE: Fields now initialized to 0 on collection
    /// - FieldValue.increment() works correctly on initialized fields
    /// - No more undefined → -1 bug
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
    
    /// Fetch users who liked a post (ordered by most recent first)
    /// TODO: POST-MVP - Add pagination support (limit + offset) when posts regularly get 100+ likes
    /// Note: Requires composite index on likes collection (postId + createdAt)
    ///       Firebase will provide a link to create it automatically when you run this query
    func fetchPostLikes(postId: String, limit: Int? = nil) async throws -> [UserProfile] {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔍 [fetchPostLikes] Starting fetch for postId: \(postId)")
        #endif
        
        var query: Query = db.collection("likes")
            .whereField("postId", isEqualTo: postId)
            .order(by: "createdAt", descending: true)
        
        if let limit = limit {
            query = query.limit(to: limit)
        }
        
        #if DEBUG
        let queryStartTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        let snapshot = try await query.getDocuments()
        
        #if DEBUG
        let queryTime = CFAbsoluteTimeGetCurrent() - queryStartTime
        print("📊 [fetchPostLikes] Query completed in \(String(format: "%.3f", queryTime))s - found \(snapshot.documents.count) likes")
        #endif
        
        let userIds = snapshot.documents.compactMap { doc -> String? in
            try? doc.data(as: Like.self).userId
        }
        
        #if DEBUG
        print("👥 [fetchPostLikes] Extracted \(userIds.count) user IDs: \(userIds)")
        #endif
        
        guard !userIds.isEmpty else {
            #if DEBUG
            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            print("✅ [fetchPostLikes] No likes found - completed in \(String(format: "%.3f", totalTime))s")
            #endif
            return []
        }
        
        // Batch fetch user profiles
        #if DEBUG
        let batchStartTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        let profiles = try await fetchProfilesBatched(userIds: userIds)
        
        #if DEBUG
        let batchTime = CFAbsoluteTimeGetCurrent() - batchStartTime
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ [fetchPostLikes] Fetched \(profiles.count) profiles in \(String(format: "%.3f", batchTime))s")
        print("⏱️ [fetchPostLikes] Total time: \(String(format: "%.3f", totalTime))s")
        #endif
        
        return profiles
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
            // @DocumentID will automatically populate when decoding
            try? doc.data(as: Comment.self)
        }
        
        return comments
    }
    
    /// Delete a comment (only by comment author or post owner)
    func deleteComment(commentId: String, postOwnerId: String, stampId: String) async throws {
        let commentRef = db.collection("comments").document(commentId)
        
        // Delete the comment document
        try await commentRef.delete()
        
        // Then, decrement comment count on post (using transaction to prevent negative counts)
        let postRef = db.collection("users").document(postOwnerId).collection("collected_stamps").document(stampId)
        
        do {
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let postSnapshot: DocumentSnapshot
                do {
                    postSnapshot = try transaction.getDocument(postRef)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                // Get current count and decrement, but never go below 0
                let currentCount = postSnapshot.data()?["commentCount"] as? Int ?? 0
                let newCount = max(0, currentCount - 1)
                
                transaction.updateData([
                    "commentCount": newCount
                ], forDocument: postRef)
                
                return nil
            })
        } catch {
            Logger.warning("Failed to decrement comment count (comment was deleted but count may be off): \(error.localizedDescription)", category: "FirebaseService")
            // Don't throw here - comment deletion succeeded, count decrement is less critical
        }
        
        print("✅ Deleted comment: \(commentId)")
    }
    
    /// Fetch comment count for a post
    func fetchCommentCount(postId: String) async throws -> Int {
        let snapshot = try await db.collection("comments")
            .whereField("postId", isEqualTo: postId)
            .getDocuments()
        
        return snapshot.documents.count
    }
    
    // MARK: - Stamp Suggestions
    
    /// Submit a stamp or collection suggestion from a user
    /// Admins can review suggestions in Firebase Console under "stamp_suggestions" collection
    func submitStampSuggestion(_ suggestion: StampSuggestion) async throws {
        let docRef = db.collection("stamp_suggestions").document()
        try docRef.setData(from: suggestion)
        print("✅ Stamp suggestion submitted: \(docRef.documentID)")
    }
    
    // MARK: - Feedback System
    
    /// Submit user feedback or bug report to Firestore
    /// Admins can view feedback in Firebase Console under "feedback" collection
    ///
    /// - Parameters:
    ///   - userId: ID of user submitting feedback (or "anonymous" for unsigned-in users)
    ///   - type: Type of feedback (Bug Report, General Feedback, Feature Request, etc.)
    ///   - message: The feedback message
    func submitFeedback(userId: String, type: String, message: String) async throws {
        // Get device and app info
        let deviceInfo = [
            "device": UIDevice.current.model,
            "systemVersion": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        ]
        
        // Create feedback document
        let feedbackRef = db.collection("feedback").document()
        
        // Build feedback data with or without user profile info
        var feedbackData: [String: Any] = [
            "userId": userId,
            "type": type,
            "message": message,
            "deviceInfo": deviceInfo,
            "createdAt": FieldValue.serverTimestamp(),
            "status": "new" // Admin can mark as "reviewed", "in-progress", "resolved"
        ]
        
        // Fetch user profile for additional context (only if not anonymous)
        if userId != "anonymous" {
            do {
                let userProfile = try await fetchUserProfile(userId: userId)
                feedbackData["userEmail"] = userProfile.username + "@stampbook.app"
                feedbackData["username"] = userProfile.username
                feedbackData["displayName"] = userProfile.displayName
            } catch {
                // If profile fetch fails, continue with anonymous submission
                Logger.warning("Could not fetch user profile for feedback, submitting as anonymous: \(error.localizedDescription)", category: "FirebaseService")
                feedbackData["username"] = "anonymous"
                feedbackData["displayName"] = "Anonymous User"
            }
        } else {
            // Anonymous submission
            feedbackData["username"] = "anonymous"
            feedbackData["displayName"] = "Anonymous User"
        }
        
        try await feedbackRef.setData(feedbackData)
        
        print("✅ Feedback submitted: \(feedbackRef.documentID)")
    }
}

// MARK: - Stamp Statistics Model

struct StampStatistics: Codable {
    let stampId: String
    let totalCollectors: Int
    let collectorUserIds: [String] // Ordered by collection time (first to collect is first in array)
    let cachedAt: Date // Timestamp for cache expiry
    
    enum CodingKeys: String, CodingKey {
        case stampId
        case totalCollectors
        case collectorUserIds
    }
    
    // Custom init to set cachedAt (not stored in Firebase)
    init(stampId: String, totalCollectors: Int, collectorUserIds: [String], cachedAt: Date = Date()) {
        self.stampId = stampId
        self.totalCollectors = totalCollectors
        self.collectorUserIds = collectorUserIds
        self.cachedAt = cachedAt
    }
    
    // Custom decoder to set cachedAt when decoding from Firebase
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stampId = try container.decode(String.self, forKey: .stampId)
        totalCollectors = try container.decode(Int.self, forKey: .totalCollectors)
        collectorUserIds = try container.decode([String].self, forKey: .collectorUserIds)
        cachedAt = Date() // Set cache timestamp to now when fetching
    }
    
    // Check if cache is stale (older than 5 minutes)
    func isCacheStale(minutes: Int = 5) -> Bool {
        return Date().timeIntervalSince(cachedAt) > TimeInterval(minutes * 60)
    }
}

