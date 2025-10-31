import Foundation
import Combine

class StampsManager: ObservableObject {
    @Published var stamps: [Stamp] = []
    @Published var collections: [Collection] = []
    @Published var userCollection = UserStampCollection()
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    
    // Cache stamp statistics to avoid repeated fetches
    @Published var stampStatistics: [String: StampStatistics] = [:]
    
    // Smart refresh tracking
    @Published var lastRefreshTime: Date?
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    
    private var cancellables = Set<AnyCancellable>()
    private let firebaseService = FirebaseService.shared
    
    init() {
        loadData()
        
        // Forward changes from userCollection to this manager
        userCollection.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
        
        // Clear cached statistics so they refetch fresh data
        await MainActor.run {
            stampStatistics.removeAll()
        }
        
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
    
    // MARK: - Data Loading
    
    /// Load stamps and collections from Firebase
    /// Firebase automatically caches data locally for offline access after first load
    @MainActor
    private func loadStampsAndCollections() async {
        isLoading = true
        loadError = nil
        
        do {
            // Fetch from Firebase (uses cache if offline)
            let fetchedStamps = try await firebaseService.fetchStamps()
            let fetchedCollections = try await firebaseService.fetchCollections()
            
            self.stamps = fetchedStamps
            self.collections = fetchedCollections
            
            print("✅ Loaded \(fetchedStamps.count) stamps from Firebase")
            print("✅ Loaded \(fetchedCollections.count) collections from Firebase")
            
            if fetchedStamps.isEmpty {
                loadError = "No stamps found. Please add stamps in Firebase Console."
            }
            
        } catch {
            print("❌ Failed to load from Firebase: \(error.localizedDescription)")
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
    
    /// Get the user's rank for a specific stamp
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
    
    /// Set the current user - filters collected stamps to show only this user's stamps
    func setCurrentUser(_ userId: String?) {
        userCollection.setCurrentUser(userId)
    }
    
    // MARK: - User Actions
    
    /// Collect a stamp and update statistics
    func collectStamp(_ stamp: Stamp, userId: String) {
        // Collect the stamp locally first (optimistic update)
        userCollection.collectStamp(stamp.id, userId: userId)
        
        // Calculate new stats
        let totalStamps = userCollection.collectedStamps.count
        let collectedStampIds = userCollection.collectedStamps.map { $0.stampId }
        let uniqueCountries = calculateUniqueCountries(from: collectedStampIds)
        
        // Update Firebase statistics in the background
        Task {
            do {
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
    
    // Helper methods for collections
    func stampsInCollection(_ collectionId: String) -> [Stamp] {
        stamps.filter { $0.collectionIds.contains(collectionId) }
    }
    
    func collectedStampsInCollection(_ collectionId: String) -> Int {
        let stampsInCollection = stamps.filter { $0.collectionIds.contains(collectionId) }
        let collectedStampIds = Set(userCollection.collectedStamps.map { $0.stampId })
        return stampsInCollection.filter { collectedStampIds.contains($0.id) }.count
    }
    
    private func completionPercentage(for collectionId: String) -> Double {
        let total = stampsInCollection(collectionId).count
        guard total > 0 else { return 0 }
        let collected = collectedStampsInCollection(collectionId)
        return Double(collected) / Double(total)
    }
    
    var sortedCollections: [Collection] {
        collections.sorted { collection1, collection2 in
            let completion1 = completionPercentage(for: collection1.id)
            let completion2 = completionPercentage(for: collection2.id)
            
            if completion1 != completion2 {
                return completion1 > completion2  // Higher completion first
            } else {
                return collection1.name < collection2.name  // Alphabetical tiebreaker
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Calculate unique countries from a list of collected stamp IDs
    func calculateUniqueCountries(from collectedStampIds: [String]) -> Int {
        let collectedStamps = stamps.filter { collectedStampIds.contains($0.id) }
        
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
    
    /// Get the count of unique countries from collected stamps
    var uniqueCountriesCount: Int {
        let collectedStampIds = userCollection.collectedStamps.map { $0.stampId }
        return calculateUniqueCountries(from: collectedStampIds)
    }
}

