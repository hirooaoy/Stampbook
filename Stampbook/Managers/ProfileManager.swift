import Foundation
import Combine

/// Notification posted when current user's profile is updated
/// Used to invalidate caches and refresh UI across the app
extension Notification.Name {
    static let profileDidUpdate = Notification.Name("profileDidUpdate")
    static let stampDidCollect = Notification.Name("stampDidCollect")
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
    
    /// Load the current user's profile from Firebase
    /// Counts are fetched separately for MVP simplicity
    func loadProfile(userId: String, loadRank: Bool = false) {
        // Skip if already loaded for this user (avoid redundant loads)
        if let currentProfile = currentUserProfile, currentProfile.id == userId, !isLoading {
            print("✅ [ProfileManager] Profile already loaded for userId: \(userId)")
            return
        }
        
        // Prevent duplicate loads
        if isLoading {
            print("⚠️ [ProfileManager] Already loading profile, skipping duplicate request")
            return
        }
        
        isLoading = true
        error = nil
        
        print("🔄 [ProfileManager] Loading profile for userId: \(userId)")
        
        Task {
            do {
                var profile = try await firebaseService.fetchUserProfile(userId: userId)
                
                // Fetch counts on-demand for MVP scale (<100 users)
                let followerCount = try await firebaseService.fetchFollowerCount(userId: userId)
                let followingCount = try await firebaseService.fetchFollowingCount(userId: userId)
                
                // Update profile with actual counts from subcollections
                profile.followerCount = followerCount
                profile.followingCount = followingCount
                
                await MainActor.run {
                    self.currentUserProfile = profile
                    self.isLoading = false
                }
                print("✅ [ProfileManager] Loaded user profile: \(profile.displayName) (\(followerCount) followers, \(followingCount) following)")
                
                // TODO: POST-MVP - Rank loading disabled
                // if loadRank {
                //     await fetchUserRank(for: profile)
                // }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                print("❌ [ProfileManager] Failed to load profile: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update the current user's profile
    /// Posts notification to invalidate caches across the app
    func updateProfile(_ profile: UserProfile) {
        print("🔄 [ProfileManager] Updating profile: @\(profile.username)")
        currentUserProfile = profile
        
        // Notify the app that profile has been updated
        // This triggers feed cache invalidation and UI refresh
        NotificationCenter.default.post(
            name: .profileDidUpdate,
            object: nil,
            userInfo: ["profile": profile]
        )
        print("📢 [ProfileManager] Posted profileDidUpdate notification")
    }
    
    /// Refresh the current user's profile from Firebase
    /// Useful after collecting stamps or other actions that update stats
    func refreshProfile() {
        guard let userId = currentUserProfile?.id else { return }
        loadProfile(userId: userId)
    }
    
    /// Refresh profile data from server (pull-to-refresh)
    /// Counts are fetched separately for MVP simplicity
    func refresh() async {
        guard let userId = currentUserProfile?.id else { return }
        
        do {
            var profile = try await firebaseService.fetchUserProfile(userId: userId)
            
            // Fetch counts on-demand for MVP scale (<100 users)
            let followerCount = try await firebaseService.fetchFollowerCount(userId: userId)
            let followingCount = try await firebaseService.fetchFollowingCount(userId: userId)
            
            // Update profile with actual counts from subcollections
            profile.followerCount = followerCount
            profile.followingCount = followingCount
            
            await MainActor.run {
                self.currentUserProfile = profile
            }
            
            // TODO: POST-MVP - Rank refresh disabled
            // if userRank != nil {
            //     await fetchUserRank(for: profile)
            // }
        } catch {
            print("⚠️ Failed to refresh profile: \(error.localizedDescription)")
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
        print("🗑️ [ProfileManager] Clearing profile data")
        currentUserProfile = nil
        // userRank = nil // TODO: POST-MVP
        error = nil
        // cachedRanks.removeAll() // TODO: POST-MVP
    }
}

