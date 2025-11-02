import Foundation
import Combine
import MapKit

class StampsManager: ObservableObject {
    // DEPRECATED: For backward compatibility during migration
    // Views should use lazy loading methods (fetchStamps, fetchStampsInRegion, etc.)
    @Published var stamps: [Stamp] = []
    
    @Published var collections: [Collection] = []
    @Published var userCollection = UserStampCollection()
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    
    // Cache stamp statistics to avoid repeated fetches
    @Published var stampStatistics: [String: StampStatistics] = [:]
    
    // LRU cache for stamp data (max 300 stamps in memory)
    private let stampCache = LRUCache<String, Stamp>(capacity: 300)
    
    // In-flight request deduplication: Track pending fetches by stamp ID
    // Prevents duplicate concurrent requests for the same stamp
    // Uses actor for thread-safe async access
    private let fetchCoordinator = FetchCoordinator()
    
    // Smart refresh tracking
    @Published var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    private let firebaseService = FirebaseService.shared
    
    init() {
        // DON'T eagerly load all stamps - let views lazy-load what they need
        // loadData() // ← Removed: 7+ second blocking load of all stamps
        
        // But DO load collections (fast, only ~5 documents, 0.1s load time)
        Task {
            await loadCollections()
        }
        
        // Forward changes from userCollection to this manager
        userCollection.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    /// Load just collections (fast - only ~5 documents)
    @MainActor
    private func loadCollections() async {
        do {
            let fetchedCollections = try await firebaseService.fetchCollections()
            self.collections = fetchedCollections
            print("✅ [StampsManager] Loaded \(fetchedCollections.count) collections")
        } catch {
            print("❌ [StampsManager] Failed to load collections: \(error.localizedDescription)")
        }
    }
    
    /// Wait for stamps to be loaded (async-friendly, no busy-wait)
    /// Returns immediately if stamps are already loaded
    func waitForStamps() async -> [Stamp] {
        // If stamps are already loaded, return immediately
        if !stamps.isEmpty {
            return stamps
        }
        
        // Otherwise, wait for stamps to be published
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = $stamps
                .filter { !$0.isEmpty }
                .first()
                .sink { stamps in
                    continuation.resume(returning: stamps)
                    cancellable?.cancel()
                }
        }
    }
    
    /// Load stamps and collections from Firebase (with local fallback)
    func loadData() {
        Task {
            await loadStampsAndCollections()
        }
    }
    
    /// Refresh data from server (pull-to-refresh)
    func refresh() async {
        guard let userId = userCollection.currentUserId else { return }
        
        // Refresh user's collected stamps from Firestore
        await userCollection.refresh(userId: userId)
        
        // Reconcile user stats to ensure they're correct
        await reconcileUserStats(userId: userId)
        
        // Clear cached statistics so they refetch fresh data
        await MainActor.run {
            stampStatistics.removeAll()
        }
        
        // Update last refresh time
        lastRefreshTime = Date()
    }
    
    /// Refresh ONLY user collection data (for feed refresh)
    /// DON'T clear statistics cache - keeps feed fast
    func refreshUserCollection() async {
        guard let userId = userCollection.currentUserId else { return }
        
        // Refresh user's collected stamps from Firestore
        await userCollection.refresh(userId: userId)
        
        // Update last refresh time
        lastRefreshTime = Date()
    }
    
    /// Smart refresh - only refreshes if data is stale (>5 minutes)
    /// Shows cached data immediately, refreshes in background if needed
    func refreshIfNeeded() async {
        let shouldRefresh = lastRefreshTime == nil || 
                           Date().timeIntervalSince(lastRefreshTime!) > refreshInterval
        
        if shouldRefresh {
            await refresh()
        }
    }
    
    // MARK: - Lazy Loading Methods (NEW ARCHITECTURE)
    
    /// Fetch specific stamps by IDs (for feed, profiles)
    /// Uses LRU cache for instant repeat access + in-flight request deduplication
    /// - Parameter ids: Array of stamp IDs to fetch
    /// - Returns: Array of stamps matching the IDs
    func fetchStamps(ids: [String]) async -> [Stamp] {
        let fetchStart = CFAbsoluteTimeGetCurrent()
        
        var results: [Stamp] = []
        var uncachedIds: [String] = []
        var pendingTasks: [Task<[Stamp], Never>] = []
        
        // Check cache and in-flight requests
        for id in ids {
            if let cached = stampCache.get(id) {
                results.append(cached)
                print("💾 [StampsManager] Cache HIT: \(id)")
            } else if let existingTask = await fetchCoordinator.getTask(for: id) {
                // Another request is already fetching this stamp - wait for it
                pendingTasks.append(existingTask)
                print("⏳ [StampsManager] Waiting for in-flight fetch: \(id)")
            } else {
                uncachedIds.append(id)
            }
        }
        
        // Wait for any pending tasks
        for task in pendingTasks {
            let stamps = await task.value
            results.append(contentsOf: stamps)
        }
        
        // Fetch uncached stamps from Firebase
        if !uncachedIds.isEmpty {
            let firebaseStart = CFAbsoluteTimeGetCurrent()
            print("🌐 [StampsManager] Fetching \(uncachedIds.count) uncached stamps: [\(uncachedIds.joined(separator: ", "))]")
            
            // Create a task for this fetch and store it
            let fetchTask = Task<[Stamp], Never> {
                do {
                    let fetchStart = CFAbsoluteTimeGetCurrent()
                    let fetched = try await self.firebaseService.fetchStampsByIds(uncachedIds)
                    let totalFetchTime = CFAbsoluteTimeGetCurrent() - fetchStart
                    
                    // Add to cache
                    let cacheStart = CFAbsoluteTimeGetCurrent()
                    for stamp in fetched {
                        self.stampCache.set(stamp.id, stamp)
                    }
                    let cacheTime = CFAbsoluteTimeGetCurrent() - cacheStart
                    
                    print("⏱️ [StampsManager] Firebase fetch: \(String(format: "%.3f", totalFetchTime))s (\(fetched.count) stamps) - cache: \(String(format: "%.3f", cacheTime))s")
                    return fetched
                } catch {
                    let errorTime = CFAbsoluteTimeGetCurrent() - firebaseStart
                    print("❌ [StampsManager] Failed to fetch stamps after \(String(format: "%.3f", errorTime))s: \(error.localizedDescription)")
                    return []
                }
            }
            
            // Register the task for each ID being fetched
            await fetchCoordinator.registerTask(fetchTask, for: uncachedIds)
            
            // Wait for fetch to complete
            let fetched = await fetchTask.value
            results.append(contentsOf: fetched)
            
            // Clean up completed tasks
            await fetchCoordinator.removeTask(for: uncachedIds)
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - fetchStart
        print("⏱️ [StampsManager] Total fetchStamps: \(String(format: "%.3f", totalTime))s (\(results.count)/\(ids.count) stamps)")
        
        return results
    }
    
    /// Fetch stamps in a geographic region (for map view)
    /// Uses geohash for efficient spatial queries
    /// - Parameter region: The visible map region
    /// - Parameter precision: Geohash precision (default 5 = ~5km)
    /// - Returns: Array of stamps in the region
    func fetchStampsInRegion(region: MKCoordinateRegion, precision: Int = 5) async -> [Stamp] {
        let (minGeohash, maxGeohash) = Geohash.bounds(for: region, precision: precision)
        
        print("🗺️ [StampsManager] Fetching stamps in region: \(minGeohash) to \(maxGeohash)")
        
        do {
            let fetched = try await firebaseService.fetchStampsInRegion(
                minGeohash: minGeohash,
                maxGeohash: maxGeohash,
                limit: 500  // Generous limit for complete metro area coverage
            )
            
            // Add to cache for future use
            for stamp in fetched {
                stampCache.set(stamp.id, stamp)
            }
            
            print("✅ [StampsManager] Fetched \(fetched.count) stamps in region")
            return fetched
        } catch {
            print("❌ [StampsManager] Failed to fetch stamps in region: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Fetch stamps in a specific collection
    /// - Parameter collectionId: The collection ID
    /// - Returns: Array of stamps in the collection
    func fetchStampsInCollection(collectionId: String) async -> [Stamp] {
        print("📚 [StampsManager] Fetching stamps in collection: \(collectionId)")
        
        do {
            let fetched = try await firebaseService.fetchStampsInCollection(collectionId: collectionId)
            
            // Add to cache
            for stamp in fetched {
                stampCache.set(stamp.id, stamp)
            }
            
            print("✅ [StampsManager] Fetched \(fetched.count) stamps in collection")
            return fetched
        } catch {
            print("❌ [StampsManager] Failed to fetch stamps in collection: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Synchronously check if a stamp is in cache (for instant prefetch checks)
    /// - Parameter id: The stamp ID to check
    /// - Returns: The cached stamp if available, nil otherwise
    func getCachedStamp(id: String) -> Stamp? {
        return stampCache.get(id)
    }
    
    /// Clear stamp cache (for debugging or low memory situations)
    func clearCache() {
        stampCache.removeAll()
        print("🗑️ [StampsManager] Cleared stamp cache")
    }
    
    // MARK: - Data Loading
    
    /// Load stamps and collections from Firebase
    /// Firebase automatically caches data locally for offline access after first load
    @MainActor
    private func loadStampsAndCollections() async {
        #if DEBUG
        let startTime = Date()
        print("🔄 [StampsManager] Starting stamps load...")
        #endif
        
        isLoading = true
        loadError = nil
        
        do {
            #if DEBUG
            let fetchStartTime = Date()
            #endif
            
            let fetchedStamps = try await firebaseService.fetchStamps()
            
            #if DEBUG
            let fetchStampsDuration = Date().timeIntervalSince(fetchStartTime)
            let collectionsStartTime = Date()
            #endif
            
            let fetchedCollections = try await firebaseService.fetchCollections()
            
            #if DEBUG
            let fetchCollectionsDuration = Date().timeIntervalSince(collectionsStartTime)
            #endif
            
            self.stamps = fetchedStamps
            self.collections = fetchedCollections
            
            #if DEBUG
            let totalDuration = Date().timeIntervalSince(startTime)
            print("⏱️ [StampsManager] Stamps: \(String(format: "%.2f", fetchStampsDuration))s, Collections: \(String(format: "%.2f", fetchCollectionsDuration))s")
            print("✅ [StampsManager] Loaded \(fetchedStamps.count) stamps in \(String(format: "%.2f", totalDuration))s")
            #endif
            
            if fetchedStamps.isEmpty {
                loadError = "No stamps found. Please add stamps in Firebase Console."
            }
            
        } catch {
            #if DEBUG
            let totalDuration = Date().timeIntervalSince(startTime)
            print("❌ [StampsManager] Failed to load after \(String(format: "%.2f", totalDuration))s: \(error.localizedDescription)")
            #else
            print("❌ [StampsManager] Failed to load: \(error.localizedDescription)")
            #endif
            loadError = "Unable to load stamps. Please check your internet connection."
        }
        
        isLoading = false
    }
    
    /// Fetch statistics for a specific stamp
    func fetchStampStatistics(stampId: String) async -> StampStatistics? {
        // Check cache first
        if let cached = stampStatistics[stampId] {
            return cached
        }
        
        // Fetch from Firebase
        do {
            let stats = try await firebaseService.fetchStampStatistics(stampId: stampId)
            await MainActor.run {
                stampStatistics[stampId] = stats
            }
            return stats
        } catch {
            print("⚠️ Failed to fetch statistics for \(stampId): \(error.localizedDescription)")
            return nil
        }
    }
    
    // TODO: POST-MVP - Per-Stamp Ranking System
    // Disabled for MVP to reduce complexity and Firestore queries
    // Consider implementing post-MVP with cached collector order
    /*
    func getUserRankForStamp(stampId: String, userId: String) async -> Int? {
        do {
            return try await firebaseService.getUserRankForStamp(stampId: stampId, userId: userId)
        } catch {
            print("⚠️ Failed to fetch rank for \(stampId): \(error.localizedDescription)")
            return nil
        }
    }
    */
    
    func isCollected(_ stamp: Stamp) -> Bool {
        userCollection.isCollected(stamp.id)
    }
    
    /// Set the current user - filters collected stamps to show only this user's stamps
    func setCurrentUser(_ userId: String?) {
        userCollection.setCurrentUser(userId)
        
        // Reconcile user stats when user changes (signs in/out)
        if let userId = userId {
            Task {
                await reconcileUserStats(userId: userId)
            }
        }
    }
    
    // MARK: - User Actions
    
    /// Collect a stamp and update statistics
    ///
    /// **Current Implementation:**
    /// - Optimistic local update (instant UX)
    /// - Background Firebase sync
    /// - Client-side reconciliation on app launch/refresh if sync fails
    ///
    /// **FUTURE UPGRADE:** When scaling, migrate to Cloud Functions (see reconcileUserStats comment)
    func collectStamp(_ stamp: Stamp, userId: String) {
        // Collect the stamp locally first (optimistic update)
        userCollection.collectStamp(stamp.id, userId: userId)
        
        // Update Firebase statistics in the background
        Task {
            do {
                // Calculate new stats (async)
                let totalStamps = userCollection.collectedStamps.count
                let collectedStampIds = userCollection.collectedStamps.map { $0.stampId }
                let uniqueCountries = await calculateUniqueCountries(from: collectedStampIds)
                
                // Update stamp statistics (collectors count)
                try await firebaseService.incrementStampCollectors(stampId: stamp.id, userId: userId)
                
                // Update user profile statistics
                try await firebaseService.updateUserStampStats(
                    userId: userId,
                    totalStamps: totalStamps,
                    uniqueCountriesVisited: uniqueCountries
                )
                
                // Refetch the updated stamp statistics immediately
                let updatedStats = try await firebaseService.fetchStampStatistics(stampId: stamp.id)
                await MainActor.run {
                    stampStatistics[stamp.id] = updatedStats
                }
                
                print("✅ Updated stamp statistics for \(stamp.id): \(updatedStats.totalCollectors) collectors")
                print("✅ Updated user stats: \(totalStamps) stamps, \(uniqueCountries) countries")
            } catch {
                print("⚠️ Failed to update statistics: \(error.localizedDescription)")
                // Don't revert local collection - sync will retry later
                // Invalidate cache so it will be refetched next time
                await MainActor.run {
                    _ = stampStatistics.removeValue(forKey: stamp.id)
                }
            }
        }
    }
    
    // MARK: - Development/Testing Functions Only
    // ⚠️ These functions are for DEVELOPMENT PURPOSES ONLY
    // They are NOT accessible from the UI and should only be used for testing/debugging
    
    /// Collects all stamps for testing purposes. Not accessible from UI.
    func obtainAll(userId: String) {
        for stamp in stamps {
            userCollection.collectStamp(stamp.id, userId: userId)
        }
    }
    
    /// Collects half of all stamps for testing purposes. Not accessible from UI.
    func obtainHalf(userId: String) {
        for (index, stamp) in stamps.enumerated() {
            if index % 2 == 0 {
                userCollection.collectStamp(stamp.id, userId: userId)
            }
        }
    }
    
    /// Resets all collected stamps for testing purposes. Not accessible from UI.
    func resetAll() {
        userCollection.resetAll()
        // Future: await cloudSync.resetUserData()
    }
    
    // MARK: - Statistics
    
    /// Reconcile user stats with actual collected stamps count
    /// This ensures stats are correct even if Firebase updates failed previously
    ///
    /// Called automatically on:
    /// - App launch / user sign in
    /// - Pull to refresh
    ///
    /// **FUTURE UPGRADE PATH:**
    /// When scaling beyond 10K+ users or adding multiple platforms (Android/Web),
    /// migrate this logic to Firebase Cloud Functions for server-side counting:
    /// - Trigger: onCreate/onDelete of users/{userId}/collected_stamps/{stampId}
    /// - Action: Automatically update totalStamps & uniqueCountriesVisited
    /// - Benefits: Single source of truth, handles all edge cases, multi-platform support
    /// - Cost: ~$0 until 100K+ users (2M free invocations/month)
    ///
    /// For now, client-side reconciliation is perfect for your scale.
    func reconcileUserStats(userId: String) async {
        do {
            // Fetch actual collected stamps count from Firestore
            let collectedStamps = try await firebaseService.fetchCollectedStamps(for: userId)
            let actualTotal = collectedStamps.count
            let collectedStampIds = collectedStamps.map { $0.stampId }
            let actualUniqueCountries = await calculateUniqueCountries(from: collectedStampIds)
            
            // Fetch current profile stats
            guard let profile = try? await firebaseService.fetchUserProfile(userId: userId) else {
                print("⚠️ Could not fetch user profile for reconciliation")
                return
            }
            
            // Check if stats need updating
            if profile.totalStamps != actualTotal || profile.uniqueCountriesVisited != actualUniqueCountries {
                print("🔄 Reconciling user stats: \(profile.totalStamps) → \(actualTotal) stamps, \(profile.uniqueCountriesVisited) → \(actualUniqueCountries) countries")
                
                // Update Firebase with correct counts
                try await firebaseService.updateUserStampStats(
                    userId: userId,
                    totalStamps: actualTotal,
                    uniqueCountriesVisited: actualUniqueCountries
                )
                
                print("✅ User stats reconciled successfully")
            } else {
                print("✅ User stats already correct (\(actualTotal) stamps, \(actualUniqueCountries) countries)")
            }
        } catch {
            print("⚠️ Failed to reconcile user stats: \(error.localizedDescription)")
            // Don't crash - stats will be reconciled on next app launch
        }
    }
    
    /// Calculate unique countries from a list of collected stamp IDs (async, fetches from Firebase)
    func calculateUniqueCountries(from collectedStampIds: [String]) async -> Int {
        guard !collectedStampIds.isEmpty else { return 0 }
        
        // Fetch the actual stamps from Firebase (uses cache if available)
        let collectedStamps = await fetchStamps(ids: collectedStampIds)
        
        let countries = Set(collectedStamps.compactMap { stamp -> String? in
            // Parse country from address
            // Supported formats:
            // - "Street\nCity, State, Country PostalCode" (US format)
            // - "Street\nCity, Country" (International format)
            let lines = stamp.address.components(separatedBy: "\n")
            guard lines.count >= 2 else {
                print("⚠️ Invalid address format for stamp \(stamp.id): \(stamp.address)")
                return nil
            }
            
            let secondLine = lines[1]
            let parts = secondLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            // Try to extract country code
            if parts.count >= 3 {
                // Format: "City, State, Country PostalCode"
                let countryPart = parts[2].components(separatedBy: " ").first ?? parts[2]
                return countryPart.isEmpty ? nil : countryPart
            } else if parts.count == 2 {
                // Format: "City, Country" (no state/province)
                let countryPart = parts[1].components(separatedBy: " ").first ?? parts[1]
                return countryPart.isEmpty ? nil : countryPart
            } else {
                print("⚠️ Unexpected address format for stamp \(stamp.id): \(stamp.address)")
                return nil
            }
        })
        
        return countries.count
    }
}

// MARK: - Fetch Coordinator Actor

/// Thread-safe coordinator for in-flight fetch requests
/// Prevents duplicate concurrent fetches of the same stamp
actor FetchCoordinator {
    private var inFlightFetches: [String: Task<[Stamp], Never>] = [:]
    
    /// Get existing task for stamp ID, if any
    func getTask(for id: String) -> Task<[Stamp], Never>? {
        return inFlightFetches[id]
    }
    
    /// Register a new fetch task for stamp IDs
    func registerTask(_ task: Task<[Stamp], Never>, for ids: [String]) {
        for id in ids {
            inFlightFetches[id] = task
        }
    }
    
    /// Remove completed tasks for stamp IDs
    func removeTask(for ids: [String]) {
        for id in ids {
            inFlightFetches.removeValue(forKey: id)
        }
    }
}

