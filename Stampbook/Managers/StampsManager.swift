import Foundation
import Combine
import MapKit

class StampsManager: ObservableObject {
    // Debug flag - set to true to enable debug logging
    private let DEBUG_STAMPS = true
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
    
    // Smart refresh tracking
    @Published var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    private let firebaseService = FirebaseService.shared
    
    init() {
        if DEBUG_STAMPS {
            print("⏱️ [StampsManager] init() started")
        }
        
        // Load collections in background
        Task {
            if DEBUG_STAMPS {
                print("⏱️ [StampsManager] Starting async collection load...")
            }
            await loadCollections()
            if DEBUG_STAMPS {
                print("✅ [StampsManager] Async collection load completed")
            }
        }
        
        // Forward changes from userCollection to this manager
        userCollection.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] init() completed (collection load is async)")
        }
    }
    
    /// Load just collections (fast - only ~5 documents)
    private func loadCollections() async {
        if DEBUG_STAMPS {
            print("🔄 [StampsManager] loadCollections() - about to fetch from Firebase")
        }
        do {
            // Fetch collections (no timeout wrapper - let Firebase SDK handle network timeouts)
            let fetchedCollections = try await firebaseService.fetchCollections()
            
            // Update published property on MainActor
            await MainActor.run {
            self.collections = fetchedCollections
            }
            if DEBUG_STAMPS {
                print("✅ [StampsManager] Loaded \(fetchedCollections.count) collections")
            }
        } catch {
            print("❌ [StampsManager] Failed to load collections: \(error.localizedDescription)")
            // Continue anyway - collections are not critical for app startup
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
    func refresh(profileManager: ProfileManager? = nil) async {
        guard let userId = userCollection.currentUserId else { return }
        
        // Refresh user's collected stamps from Firestore
        await userCollection.refresh(userId: userId)
        
        // Reconcile user stats to ensure they're correct
        await reconcileUserStats(userId: userId, profileManager: profileManager)
        
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
                           Date().timeIntervalSince(lastRefreshTime ?? Date.distantPast) > refreshInterval
        
        if shouldRefresh {
            await refresh()
        }
    }
    
    // MARK: - Lazy Loading Methods (NEW ARCHITECTURE)
    
    /// Fetch specific stamps by IDs (for feed, profiles)
    /// Uses LRU cache for instant repeat access
    /// - Parameter ids: Array of stamp IDs to fetch
    /// - Parameter includeRemoved: If true, returns removed stamps (for user's collected stamps/feed)
    ///                              If false, filters out removed stamps (for map/collections)
    /// - Returns: Array of stamps matching the IDs
    func fetchStamps(ids: [String], includeRemoved: Bool = false) async -> [Stamp] {
        var results: [Stamp] = []
        var uncachedIds: [String] = []
        
        // Check cache first
        for id in ids {
            if let cached = stampCache.get(id) {
                results.append(cached)
                if DEBUG_STAMPS {
                    print("💾 [StampsManager] Cache HIT: \(id)")
                }
            } else {
                uncachedIds.append(id)
            }
        }
        
        // Fetch uncached stamps from Firebase
        if !uncachedIds.isEmpty {
            if DEBUG_STAMPS {
                print("🌐 [StampsManager] Fetching \(uncachedIds.count) uncached stamps: [\(uncachedIds.joined(separator: ", "))]")
            }
            
            do {
                let fetched = try await firebaseService.fetchStampsByIds(uncachedIds)
                
                // Add to cache
                for stamp in fetched {
                    stampCache.set(stamp.id, stamp)
                }
                
                results.append(contentsOf: fetched)
                
                if DEBUG_STAMPS {
                    print("✅ [StampsManager] Fetched \(fetched.count) stamps from Firebase")
                }
            } catch {
                print("❌ [StampsManager] Failed to fetch stamps: \(error.localizedDescription)")
            }
        }
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] fetchStamps complete: \(results.count)/\(ids.count) stamps (includeRemoved: \(includeRemoved))")
        }
        
        // Filter based on context
        if includeRemoved {
            // For user's collected stamps/feed - return everything (even removed)
            // Users keep what they collected, even if stamp is later removed
            return results
        } else {
            // For map/collections - only show currently available stamps
            let available = filterAvailableStamps(results)
            return available
        }
    }
    
    /// Fetch all stamps globally (for map view)
    /// 
    /// **CURRENT STRATEGY (MVP with 100-1000 stamps):**
    /// Simple "fetch all" approach works perfectly because:
    /// - Firebase persistent cache makes subsequent loads instant (FREE)
    /// - First load: ~500ms for 400 stamps
    /// - All future loads: <50ms from cache (no Firebase reads)
    /// - Cost: ~12K reads/month for new users only = $0/month (under 1.5M free tier)
    /// 
    /// **WHEN TO SWITCH to fetchStampsInRegion():**
    /// - Stamp count exceeds ~1000 stamps
    /// - First load becomes too slow (>1 second)
    /// - Approaching Firebase free tier limits
    /// - See fetchStampsInRegion() below for region-based alternative
    /// 
    /// - Returns: Array of all stamps
    func fetchAllStamps() async -> [Stamp] {
        if DEBUG_STAMPS {
            print("🗺️ [StampsManager] Fetching all stamps globally...")
        }
        
        do {
            let fetched = try await firebaseService.fetchStamps()
            
            // Add to cache for future use
            for stamp in fetched {
                stampCache.set(stamp.id, stamp)
            }
            
            if DEBUG_STAMPS {
                print("✅ [StampsManager] Fetched \(fetched.count) stamps globally")
            }
            
            // Filter: Only return currently available stamps
            let available = filterAvailableStamps(fetched)
            
            return available
        } catch {
            print("❌ [StampsManager] Failed to fetch stamps: \(error.localizedDescription)")
            return []
        }
    }
    
    // ==================== FUTURE OPTIMIZATION ====================
    // Region-based stamp loading removed for MVP (stamp count: 1000)
    // 
    // This optimization becomes necessary when stamp count exceeds 2000.
    // To restore: Check git history for commit "Remove unused region-based loading"
    // 
    // When needed:
    // - Restores Geohash.swift utility
    // - Enables fetchStampsInRegion() in StampsManager
    // - Enables fetchStampsInRegion() in FirebaseService
    // - Updates MapView to call region-based loading
    // 
    // Benefits at scale: Only loads ~300 visible stamps instead of all 2000+
    // ==================== FUTURE OPTIMIZATION ====================
    
    /// Fetch stamps in a specific collection
    /// - Parameter collectionId: The collection ID
    /// - Returns: Array of stamps in the collection
    func fetchStampsInCollection(collectionId: String) async -> [Stamp] {
        if DEBUG_STAMPS {
            print("📚 [StampsManager] Fetching stamps in collection: \(collectionId)")
        }
        
        do {
            let fetched = try await firebaseService.fetchStampsInCollection(collectionId: collectionId)
            
            // Filter: Only show currently available stamps
            let available = filterAvailableStamps(fetched)
            
            // Add to cache
            for stamp in available {
                stampCache.set(stamp.id, stamp)
            }
            
            if DEBUG_STAMPS {
                print("✅ [StampsManager] Fetched \(available.count) stamps in collection")
            }
            return available
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
        if DEBUG_STAMPS {
            print("🗑️ [StampsManager] Cleared stamp cache")
        }
    }
    
    // MARK: - Visibility Filtering
    
    /// Filter stamps to only show currently available ones (respects status and dates)
    /// This is the SINGLE SOURCE OF TRUTH for stamp visibility
    /// - Parameter stamps: Array of stamps to filter
    /// - Returns: Only stamps that are currently available
    /// - Note: Does NOT affect collected stamps - users keep what they collected
    private func filterAvailableStamps(_ stamps: [Stamp]) -> [Stamp] {
        let available = stamps.filter { $0.isCurrentlyAvailable }
        
        if DEBUG_STAMPS && available.count < stamps.count {
            let filtered = stamps.count - available.count
            print("🔍 [StampsManager] Filtered out \(filtered) unavailable stamp(s)")
        }
        
        return available
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
    
    /// Get user's rank for a specific stamp (what number collector they were)
    /// Example: If you're the 23rd person to collect Baker Beach, you'll always be #23!
    func getUserRankForStamp(stampId: String, userId: String) async -> Int? {
        do {
            return try await firebaseService.getUserRankForStamp(stampId: stampId, userId: userId)
        } catch {
            print("⚠️ Failed to fetch rank for \(stampId): \(error.localizedDescription)")
            return nil
        }
    }
    
    func isCollected(_ stamp: Stamp) -> Bool {
        userCollection.isCollected(stamp.id)
    }
    
    /// Check if the user has claimed the welcome stamp
    func hasClaimedWelcomeStamp() -> Bool {
        return userCollection.isCollected("your-first-stamp")
    }
    
    /// Set the current user - filters collected stamps to show only this user's stamps
    func setCurrentUser(_ userId: String?, profileManager: ProfileManager? = nil) {
        userCollection.setCurrentUser(userId)
        
        // Reconcile user stats when user changes (signs in/out)
        if let userId = userId {
            Task {
                await reconcileUserStats(userId: userId, profileManager: profileManager)
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
        Task {
            // Collect the stamp locally first (optimistic update - no rank yet)
            await MainActor.run {
                userCollection.collectStamp(stamp.id, userId: userId, userRank: nil)
            }
            
            // Update Firebase statistics in the background
            do {
                // Update stamp statistics (collectors count) FIRST
                try await firebaseService.incrementStampCollectors(stampId: stamp.id, userId: userId)
                
                // NOW fetch the user's rank (after incrementing, so we get the correct position)
                let userRank = await getUserRankForStamp(stampId: stamp.id, userId: userId)
                
                // Update the cached rank in the collected stamp
                if let rank = userRank {
                    await MainActor.run {
                        userCollection.updateUserRank(for: stamp.id, rank: rank)
                    }
                }
                
                // Calculate new stats (async)
                let totalStamps = await MainActor.run { userCollection.collectedStamps.count }
                let collectedStampIds = await MainActor.run { userCollection.collectedStamps.map { $0.stampId } }
                let uniqueCountries = await calculateUniqueCountries(from: collectedStampIds)
                
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
                
                print("✅ Updated stamp statistics for \(stamp.id): \(updatedStats.totalCollectors) collectors (user rank: \(userRank ?? -1))")
                print("✅ Updated user stats: \(totalStamps) stamps, \(uniqueCountries) countries")
            } catch {
                print("⚠️ Failed to update statistics: \(error.localizedDescription)")
                // Don't revert local collection - stamp is saved locally and will auto-sync
                // on next app launch via UserStampCollection.syncLocalOnlyStamps()
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
    /// 🎯 ACTION TRIGGER: Migrate to Cloud Functions when adding Android app OR 500+ users
    func reconcileUserStats(userId: String, profileManager: ProfileManager? = nil) async {
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
                
                // CRITICAL FIX: Refresh ProfileManager to show updated counts
                // Without this, UI still shows old stats even though Firebase is updated
                if let profileManager = profileManager {
                    await MainActor.run {
                        profileManager.refreshProfile()
                    }
                    print("✅ ProfileManager refreshed with updated stats")
                }
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

