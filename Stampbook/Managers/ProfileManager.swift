import Foundation
import Combine

/// Notification posted when current user's profile is updated
/// Used to invalidate caches and refresh UI across the app
extension Notification.Name {
    static let profileDidUpdate = Notification.Name("profileDidUpdate")
    static let stampDidCollect = Notification.Name("stampDidCollect")
    static let followingListDidChange = Notification.Name("followingListDidChange")
}

/// Manages user profile state and operations
class ProfileManager: ObservableObject {
    @Published var currentUserProfile: UserProfile?
    @Published var isLoading = false
    @Published var error: String?
    
    // TODO: POST-MVP - User Ranking System
    // Global rank calculation requires comparing all users (expensive Firestore query)
    // Consider implementing with:
    // - Periodic Cloud Function to update cached ranks
    // - Leaderboard limited to top users
    // - Approximate ranking for better performance
    // @Published var userRank: Int? // Global rank based on totalStamps
    
    private let firebaseService = FirebaseService.shared
    
    // TODO: POST-MVP - Rank caching (disabled until rank feature is implemented)
    // private var cachedRanks: [String: (rank: Int, timestamp: Date)] = [:]
    // private let rankCacheExpiration: TimeInterval = 1800 // 30 minutes
    
    // MARK: - Lifecycle
    
    init() {
        // Listen for following list changes to refresh current user's follow counts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFollowingListChange),
            name: .followingListDidChange,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Handle following list change notification
    /// Force refresh current user's profile to get updated follow counts
    @objc private func handleFollowingListChange(_ notification: Notification) {
        print("🔔 [ProfileManager] ========================================")
        print("🔔 [ProfileManager] Received following list change notification - refreshing profile")
        
        guard let userId = currentUserProfile?.id else {
            print("⚠️ [ProfileManager] No current user profile to refresh")
            return
        }
        
        print("🔔 [ProfileManager] Current profile BEFORE refresh:")
        print("🔔 [ProfileManager]   userId: \(userId)")
        print("🔔 [ProfileManager]   followers: \(currentUserProfile?.followerCount ?? -1)")
        print("🔔 [ProfileManager]   following: \(currentUserProfile?.followingCount ?? -1)")
        
        // Force refresh profile from Firebase to get latest follow counts
        Task {
            do {
                print("🔔 [ProfileManager] Fetching fresh profile from Firebase...")
                let profile = try await firebaseService.fetchUserProfile(userId: userId, forceRefresh: true)
                print("🔔 [ProfileManager] Fresh profile fetched:")
                print("🔔 [ProfileManager]   followers: \(profile.followerCount)")
                print("🔔 [ProfileManager]   following: \(profile.followingCount)")
                await MainActor.run {
                    print("🔔 [ProfileManager] About to update currentUserProfile...")
                    self.currentUserProfile = profile
                    print("✅ [ProfileManager] Profile refreshed and @Published property updated")
                    print("✅ [ProfileManager]   followers: \(profile.followerCount), following: \(profile.followingCount)")
                    print("🔔 [ProfileManager] ========================================")
                }
            } catch {
                Logger.error("Failed to refresh profile after follow change", error: error, category: "ProfileManager")
            }
        }
    }
    
    /// Load the current user's profile from Firebase
    /// Counts are fetched separately for MVP simplicity
    func loadProfile(userId: String, loadRank: Bool = false) {
        // Skip if already loaded for this user (avoid redundant loads)
        if let currentProfile = currentUserProfile, currentProfile.id == userId, !isLoading {
            Logger.debug("Profile already loaded for userId: \(userId)")
            return
        }
        
        // Prevent duplicate loads
        if isLoading {
            Logger.warning("Already loading profile, skipping duplicate request")
            return
        }
        
        isLoading = true
        error = nil
        
        Logger.info("Loading profile for userId: \(userId)", category: "ProfileManager")
        
        Task {
            do {
                // ✅ OPTIMIZED: Counts now denormalized on profile (Cloud Function keeps them in sync)
                // No need to query subcollections - saves 20-100 reads per profile view (97% cost reduction)
                let profile = try await firebaseService.fetchUserProfile(userId: userId)
                // Counts are already on profile.followerCount and profile.followingCount
                
                await MainActor.run {
                    self.currentUserProfile = profile
                    self.isLoading = false
                }
                Logger.success("Loaded user profile: \(profile.displayName) (\(profile.followerCount) followers, \(profile.followingCount) following)", category: "ProfileManager")
                
                // TODO: POST-MVP - Rank loading disabled
                // if loadRank {
                //     await fetchUserRank(for: profile)
                // }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                Logger.error("Failed to load profile", error: error, category: "ProfileManager")
            }
        }
    }
    
    /// Update the current user's profile
    /// Posts notification to invalidate caches across the app
    func updateProfile(_ profile: UserProfile) {
        Logger.info("Updating profile: @\(profile.username)", category: "ProfileManager")
        currentUserProfile = profile
        
        // Notify the app that profile has been updated
        // This triggers feed cache invalidation and UI refresh
        NotificationCenter.default.post(
            name: .profileDidUpdate,
            object: nil,
            userInfo: ["profile": profile]
        )
        Logger.debug("Posted profileDidUpdate notification")
    }
    
    /// Refresh the current user's profile from Firebase
    /// Useful after collecting stamps or other actions that update stats
    func refreshProfile() {
        guard let userId = currentUserProfile?.id else { return }
        loadProfile(userId: userId)
    }
    
    /// Refresh profile data from server (pull-to-refresh)
    /// Counts are denormalized on profile (no separate fetching needed)
    func refresh() async {
        guard let userId = currentUserProfile?.id else { return }
        
        do {
            // ✅ Force refresh to bypass cache and get latest data from Firebase
            let profile = try await firebaseService.fetchUserProfile(userId: userId, forceRefresh: true)
            
            await MainActor.run {
                self.currentUserProfile = profile
            }
            
            // TODO: POST-MVP - Rank refresh disabled
            // if userRank != nil {
            //     await fetchUserRank(for: profile)
            // }
        } catch {
            Logger.warning("Failed to refresh profile", category: "ProfileManager")
        }
    }
    
    // TODO: POST-MVP - User Ranking System
    // This function is disabled for MVP due to expensive Firestore queries
    // Comparing all users requires fetching large datasets and complex caching
    // Consider implementing post-MVP with Cloud Functions for periodic rank updates
    /*
    func fetchUserRank(for profile: UserProfile) async {
        let startTime = Date()
        print("🔍 [ProfileManager] Fetching rank for \(profile.displayName) (userId: \(profile.id), totalStamps: \(profile.totalStamps))")
        
        // Check cache first
        if let cached = cachedRanks[profile.id],
           Date().timeIntervalSince(cached.timestamp) < rankCacheExpiration {
            let elapsed = Date().timeIntervalSince(startTime)
            await MainActor.run {
                self.userRank = cached.rank
            }
            print("✅ [ProfileManager] Using cached rank for \(profile.displayName): #\(cached.rank) (cache age: \(String(format: "%.0f", Date().timeIntervalSince(cached.timestamp)))s, query took: \(String(format: "%.3f", elapsed))s)")
            return
        }
        
        // Store current rank in case fetch fails
        let previousRank = userRank
        
        print("🔄 [ProfileManager] Cache miss - fetching rank from Firestore...")
        
        do {
            let rank = try await firebaseService.calculateUserRank(
                userId: profile.id,
                totalStamps: profile.totalStamps
            )
            let elapsed = Date().timeIntervalSince(startTime)
            await MainActor.run {
                self.userRank = rank
                // Cache the rank
                self.cachedRanks[profile.id] = (rank: rank, timestamp: Date())
            }
            print("✅ [ProfileManager] User rank fetched: #\(rank) (total time: \(String(format: "%.3f", elapsed))s)")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("❌ [ProfileManager] Failed to fetch rank after \(String(format: "%.3f", elapsed))s: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ [ProfileManager] Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            
            // Preserve previous rank if fetch fails (don't reset to nil)
            if let previousRank = previousRank {
                await MainActor.run {
                    self.userRank = previousRank
                }
                print("ℹ️ [ProfileManager] Keeping previous rank: #\(previousRank)")
            }
            // Don't set error - rank is optional/non-critical
        }
    }
    */
    
    /// Clear profile data (on sign out)
    func clearProfile() {
        Logger.info("Clearing profile data", category: "ProfileManager")
        currentUserProfile = nil
        // userRank = nil // TODO: POST-MVP
        error = nil
        // cachedRanks.removeAll() // TODO: POST-MVP
    }
}

