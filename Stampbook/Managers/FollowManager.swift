import Foundation
import Combine

/// Manages follow/unfollow operations and follow state
/// Should be used as a single shared instance (@EnvironmentObject) across the app
class FollowManager: ObservableObject {
    @Published var isFollowing: [String: Bool] = [:] // userId -> isFollowing
    @Published var followers: [UserProfile] = []
    @Published var following: [UserProfile] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isProcessingFollow: [String: Bool] = [:] // userId -> isProcessing (for button loading state)
    
    // Cache for follow counts (userId -> (followerCount, followingCount))
    @Published var followCounts: [String: (followers: Int, following: Int)] = [:]
    
    // Debouncing: Prevent rapid-fire follow/unfollow (Instagram-style UX)
    private var lastFollowAction: [String: Date] = [:] // userId -> last action time
    private let debounceInterval: TimeInterval = 0.5 // 500ms cooldown
    
    private let firebaseService = FirebaseService.shared
    
    // MARK: - Follow Status Checking
    
    /// Check if current user is following another user
    func checkFollowStatus(currentUserId: String, targetUserId: String) {
        print("🔍 [FollowManager] checkFollowStatus: \(currentUserId) -> \(targetUserId)")
        Task {
            do {
                let following = try await firebaseService.isFollowing(followerId: currentUserId, followeeId: targetUserId)
                await MainActor.run {
                    self.isFollowing[targetUserId] = following
                    print("✅ [FollowManager] isFollowing[\(targetUserId)] = \(following)")
                }
            } catch {
                Logger.error("Failed to check follow status", error: error, category: "FollowManager")
            }
        }
    }
    
    /// Check follow status for multiple users at once (batch operation)
    func checkFollowStatuses(currentUserId: String, targetUserIds: [String]) async {
        print("🔍 [FollowManager] Batch checking follow statuses for \(targetUserIds.count) users")
        
        await withTaskGroup(of: (String, Bool).self) { group in
            for targetUserId in targetUserIds {
                group.addTask {
                    do {
                        let following = try await self.firebaseService.isFollowing(followerId: currentUserId, followeeId: targetUserId)
                        return (targetUserId, following)
                    } catch {
                        Logger.error("Failed to check follow status for \(targetUserId)", error: error, category: "FollowManager")
                        return (targetUserId, false)
                    }
                }
            }
            
            // Collect all results
            var results: [String: Bool] = [:]
            for await (userId, isFollowing) in group {
                results[userId] = isFollowing
            }
            
            // Update state on main actor
            await MainActor.run {
                for (userId, isFollowing) in results {
                    self.isFollowing[userId] = isFollowing
                }
                print("✅ [FollowManager] Batch updated follow statuses for \(results.count) users")
            }
        }
    }
    
    // MARK: - Follow/Unfollow Actions
    
    /// Follow a user (with optimistic UI update)
    /// Counts are fetched separately on-demand, so we don't manage them here
    func followUser(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        print("🔵 [FollowManager] followUser called: \(currentUserId) -> \(targetUserId)")
        
        // Debounce: Prevent rapid follow/unfollow (Instagram-style - silently ignore)
        if let lastTime = lastFollowAction[targetUserId],
           Date().timeIntervalSince(lastTime) < debounceInterval {
            print("🚫 [FollowManager] Debounced: Too soon to toggle follow for \(targetUserId)")
            return
        }
        lastFollowAction[targetUserId] = Date()
        
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = true
        print("✅ [FollowManager] Optimistic update: isFollowing[\(targetUserId)] = true")
        
        // Optimistically increment following count for current user
        if var currentCounts = followCounts[currentUserId] {
            currentCounts.following += 1
            followCounts[currentUserId] = currentCounts
            print("✅ [FollowManager] Optimistic count update: \(currentUserId) following: \(currentCounts.following)")
        }
        
        // Optimistically increment follower count for target user
        if var targetCounts = followCounts[targetUserId] {
            targetCounts.followers += 1
            followCounts[targetUserId] = targetCounts
            print("✅ [FollowManager] Optimistic count update: \(targetUserId) followers: \(targetCounts.followers)")
        } else {
            // Initialize count if not cached yet
            // We only know followers changed (0→1), don't know their following count yet
            // Profile load will fill in the following count
            followCounts[targetUserId] = (followers: 1, following: 0)
            print("✅ [FollowManager] Optimistic count init: \(targetUserId) followers: 1 (following will be filled by profile)")
        }
        
        Task {
            do {
                let didFollow = try await firebaseService.followUser(followerId: currentUserId, followeeId: targetUserId)
                print("🔄 [FollowManager] Firebase followUser returned: \(didFollow)")
                
                await MainActor.run {
                    self.isProcessingFollow[targetUserId] = false
                    
                    // Add to following list if we're currently viewing it
                    if didFollow {
                        print("✅ [FollowManager] Successfully followed user \(targetUserId)")
                        
                        // Optimistic updates are already applied above
                        // Cloud Function will update denormalized counts in background
                        // Next profile load will fetch correct counts (eventual consistency)
                        
                        // Notify observers that following list changed (triggers feed refresh)
                        NotificationCenter.default.post(name: .followingListDidChange, object: nil)
                        
                        // Try to fetch the target user's profile to add to list
                        Task {
                            if let profile = try? await firebaseService.fetchUserProfile(userId: targetUserId) {
                                await MainActor.run {
                                    if !self.following.contains(where: { $0.id == targetUserId }) {
                                        self.following.append(profile)
                                        print("✅ [FollowManager] Added \(profile.username) to following list")
                                    }
                                }
                                onSuccess?(profile)
                            }
                        }
                    } else {
                        Logger.warning("Already following, rolling back optimistic updates", category: "FollowManager")
                        // Already following - rollback optimistic updates
                        if var currentCounts = self.followCounts[currentUserId] {
                            currentCounts.following = max(0, currentCounts.following - 1)
                            self.followCounts[currentUserId] = currentCounts
                        }
                        if var targetCounts = self.followCounts[targetUserId] {
                            targetCounts.followers = max(0, targetCounts.followers - 1)
                            self.followCounts[targetUserId] = targetCounts
                        }
                    }
                }
            } catch {
                Logger.error("Failed to follow user", error: error, category: "FollowManager")
                // Rollback on error
                await MainActor.run {
                    self.isFollowing[targetUserId] = false
                    self.isProcessingFollow[targetUserId] = false
                    self.error = "Couldn't follow user. Check your connection."
                    
                    // Rollback count changes
                    if var currentCounts = self.followCounts[currentUserId] {
                        currentCounts.following = max(0, currentCounts.following - 1)
                        self.followCounts[currentUserId] = currentCounts
                        print("🔄 [FollowManager] Rolled back count: \(currentUserId) following: \(currentCounts.following)")
                    }
                    if var targetCounts = self.followCounts[targetUserId] {
                        targetCounts.followers = max(0, targetCounts.followers - 1)
                        self.followCounts[targetUserId] = targetCounts
                        print("🔄 [FollowManager] Rolled back count: \(targetUserId) followers: \(targetCounts.followers)")
                    }
                }
            }
        }
    }
    
    /// Unfollow a user (with optimistic UI update)
    /// Counts are fetched separately on-demand, so we don't manage them here
    func unfollowUser(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        print("🔴 [FollowManager] unfollowUser called: \(currentUserId) -> \(targetUserId)")
        
        // Debounce: Prevent rapid follow/unfollow (Instagram-style - silently ignore)
        if let lastTime = lastFollowAction[targetUserId],
           Date().timeIntervalSince(lastTime) < debounceInterval {
            print("🚫 [FollowManager] Debounced: Too soon to toggle follow for \(targetUserId)")
            return
        }
        lastFollowAction[targetUserId] = Date()
        
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = false
        print("✅ [FollowManager] Optimistic update: isFollowing[\(targetUserId)] = false")
        
        // Optimistically decrement following count for current user
        if var currentCounts = followCounts[currentUserId] {
            currentCounts.following = max(0, currentCounts.following - 1)
            followCounts[currentUserId] = currentCounts
            print("✅ [FollowManager] Optimistic count update: \(currentUserId) following: \(currentCounts.following)")
        }
        
        // Optimistically decrement follower count for target user
        if var targetCounts = followCounts[targetUserId] {
            targetCounts.followers = max(0, targetCounts.followers - 1)
            followCounts[targetUserId] = targetCounts
            print("✅ [FollowManager] Optimistic count update: \(targetUserId) followers: \(targetCounts.followers)")
        } else {
            // Initialize count if not cached yet
            // We only know followers changed (1→0), don't know their following count yet
            // Profile load will fill in the following count
            followCounts[targetUserId] = (followers: 0, following: 0)
            print("✅ [FollowManager] Optimistic count init: \(targetUserId) followers: 0 (following will be filled by profile)")
        }
        
        // Remove from following list immediately (optimistic)
        following.removeAll { $0.id == targetUserId }
        print("✅ [FollowManager] Removed \(targetUserId) from following list")
        
        Task {
            do {
                let didUnfollow = try await firebaseService.unfollowUser(followerId: currentUserId, followeeId: targetUserId)
                print("🔄 [FollowManager] Firebase unfollowUser returned: \(didUnfollow)")
                
                await MainActor.run {
                    self.isProcessingFollow[targetUserId] = false
                }
                
                if didUnfollow {
                    print("✅ [FollowManager] Successfully unfollowed user \(targetUserId)")
                    
                    // Optimistic updates are already applied above
                    // Cloud Function will update denormalized counts in background
                    // Next profile load will fetch correct counts (eventual consistency)
                    
                    // Notify observers that following list changed (triggers feed refresh)
                    NotificationCenter.default.post(name: .followingListDidChange, object: nil)
                    
                    onSuccess?(nil)
                } else {
                    Logger.warning("Wasn't following, rolling back optimistic updates", category: "FollowManager")
                    // Wasn't following - rollback optimistic updates
                    await MainActor.run {
                        self.isFollowing[targetUserId] = true
                        
                        if var currentCounts = self.followCounts[currentUserId] {
                            currentCounts.following += 1
                            self.followCounts[currentUserId] = currentCounts
                        }
                        if var targetCounts = self.followCounts[targetUserId] {
                            targetCounts.followers += 1
                            self.followCounts[targetUserId] = targetCounts
                        }
                        
                        // Re-fetch following list to restore state
                        self.fetchFollowing(userId: currentUserId)
                    }
                }
            } catch {
                Logger.error("Failed to unfollow user", error: error, category: "FollowManager")
                // Rollback on error - re-add to following list
                await MainActor.run {
                    self.isFollowing[targetUserId] = true
                    
                    // Re-fetch following list to restore state
                    self.fetchFollowing(userId: currentUserId)
                    
                    // Rollback count changes
                    if var currentCounts = self.followCounts[currentUserId] {
                        currentCounts.following += 1
                        self.followCounts[currentUserId] = currentCounts
                        print("🔄 [FollowManager] Rolled back count: \(currentUserId) following: \(currentCounts.following)")
                    }
                    if var targetCounts = self.followCounts[targetUserId] {
                        targetCounts.followers += 1
                        self.followCounts[targetUserId] = targetCounts
                        print("🔄 [FollowManager] Rolled back count: \(targetUserId) followers: \(targetCounts.followers)")
                    }
                    
                    self.isProcessingFollow[targetUserId] = false
                    self.error = "Couldn't unfollow user. Check your connection."
                }
            }
        }
    }
    
    /// Toggle follow status for a user
    func toggleFollow(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        let currentlyFollowing = isFollowing[targetUserId] ?? false
        print("🔄 [FollowManager] toggleFollow called: \(targetUserId), currentlyFollowing: \(currentlyFollowing)")
        
        if currentlyFollowing {
            unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId, profileManager: profileManager, onSuccess: onSuccess)
        } else {
            followUser(currentUserId: currentUserId, targetUserId: targetUserId, profileManager: profileManager, onSuccess: onSuccess)
        }
    }
    
    // MARK: - List Fetching
    
    /// Fetch followers for a user
    func fetchFollowers(userId: String, currentUserId: String? = nil) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let profiles = try await firebaseService.fetchFollowers(userId: userId)
                await MainActor.run {
                    self.followers = profiles
                    self.isLoading = false
                }
                print("✅ Fetched \(profiles.count) followers")
                
                // Batch check follow statuses if current user is provided
                if let currentUserId = currentUserId {
                    let userIds = profiles.map { $0.id }
                    await checkFollowStatuses(currentUserId: currentUserId, targetUserIds: userIds)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                Logger.error("Failed to fetch followers", error: error, category: "FollowManager")
            }
        }
    }
    
    /// Fetch following for a user
    func fetchFollowing(userId: String, currentUserId: String? = nil) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let profiles = try await firebaseService.fetchFollowing(userId: userId)
                await MainActor.run {
                    self.following = profiles
                    self.isLoading = false
                }
                print("✅ Fetched \(profiles.count) following")
                
                // Batch check follow statuses if current user is provided
                if let currentUserId = currentUserId {
                    let userIds = profiles.map { $0.id }
                    await checkFollowStatuses(currentUserId: currentUserId, targetUserIds: userIds)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                Logger.error("Failed to fetch following", error: error, category: "FollowManager")
            }
        }
    }
    
    // MARK: - Count Management (Deprecated - counts are fetched on-demand now)
    
    /// Legacy method - kept for backwards compatibility
    /// For MVP scale, fetch counts directly using FirebaseService.fetchFollowerCount/fetchFollowingCount
    func updateFollowCounts(userId: String, followerCount: Int, followingCount: Int) {
        print("📊 [FollowManager] updateFollowCounts called")
        print("📊 [FollowManager]   userId: \(userId)")
        print("📊 [FollowManager]   NEW followers: \(followerCount), following: \(followingCount)")
        print("📊 [FollowManager]   OLD followers: \(followCounts[userId]?.followers ?? -1), following: \(followCounts[userId]?.following ?? -1)")
        followCounts[userId] = (followerCount, followingCount)
        print("📊 [FollowManager]   Cache updated. Current cache count: \(followCounts.count) users")
        print("📊 [FollowManager]   Verified cache for \(userId): followers=\(followCounts[userId]?.followers ?? -1), following=\(followCounts[userId]?.following ?? -1)")
    }
    
    /// Fetch and cache follow counts for a user (from denormalized profile data)
    func refreshFollowCounts(userId: String) async {
        print("🔄 [FollowManager] refreshFollowCounts called for userId: \(userId)")
        do {
            // IMPORTANT: Force refresh to bypass cache and get latest counts from Firebase
            // This ensures optimistic updates don't get overwritten by stale cached data
            let profile = try await firebaseService.fetchUserProfile(userId: userId, forceRefresh: true)
            await MainActor.run {
                self.followCounts[userId] = (profile.followerCount, profile.followingCount)
                print("✅ [FollowManager] Updated counts for \(userId): followers=\(profile.followerCount), following=\(profile.followingCount)")
            }
        } catch {
            Logger.error("Failed to refresh follow counts", error: error, category: "FollowManager")
        }
    }
    
    // MARK: - Cleanup
    
    /// Clear all follow data (on sign out)
    func clearFollowData() {
        isFollowing.removeAll()
        followers.removeAll()
        following.removeAll()
        followCounts.removeAll()
        isProcessingFollow.removeAll()
        error = nil
    }
}

