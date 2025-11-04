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
                print("❌ [FollowManager] Failed to check follow status: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check follow status for multiple users at once (batch operation)
    func checkFollowStatuses(currentUserId: String, targetUserIds: [String]) {
        for targetUserId in targetUserIds {
            checkFollowStatus(currentUserId: currentUserId, targetUserId: targetUserId)
        }
    }
    
    // MARK: - Follow/Unfollow Actions
    
    /// Follow a user (with optimistic UI update)
    /// Counts are fetched separately on-demand, so we don't manage them here
    func followUser(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        print("🔵 [FollowManager] followUser called: \(currentUserId) -> \(targetUserId)")
        
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
                        
                        // Refresh counts from Firebase to get accurate numbers
                        Task {
                            await self.refreshFollowCounts(userId: currentUserId)
                            await self.refreshFollowCounts(userId: targetUserId)
                            print("✅ [FollowManager] Refreshed counts from Firebase after follow")
                        }
                        
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
                        print("⚠️ [FollowManager] Already following, rolling back optimistic updates")
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
                print("❌ [FollowManager] Failed to follow user: \(error.localizedDescription)")
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
                    
                    // Refresh counts from Firebase to get accurate numbers
                    Task {
                        await self.refreshFollowCounts(userId: currentUserId)
                        await self.refreshFollowCounts(userId: targetUserId)
                        print("✅ [FollowManager] Refreshed counts from Firebase after unfollow")
                    }
                    
                    onSuccess?(nil)
                } else {
                    print("⚠️ [FollowManager] Wasn't following, rolling back optimistic updates")
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
                print("❌ [FollowManager] Failed to unfollow user: \(error.localizedDescription)")
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
    func fetchFollowers(userId: String) {
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
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                print("❌ Failed to fetch followers: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch following for a user
    func fetchFollowing(userId: String) {
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
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
                print("❌ Failed to fetch following: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Count Management (Deprecated - counts are fetched on-demand now)
    
    /// Legacy method - kept for backwards compatibility
    /// For MVP scale, fetch counts directly using FirebaseService.fetchFollowerCount/fetchFollowingCount
    func updateFollowCounts(userId: String, followerCount: Int, followingCount: Int) {
        print("📊 [FollowManager] updateFollowCounts: \(userId) -> followers=\(followerCount), following=\(followingCount)")
        followCounts[userId] = (followerCount, followingCount)
    }
    
    /// Fetch and cache follow counts for a user (on-demand from subcollections)
    func refreshFollowCounts(userId: String) async {
        print("🔄 [FollowManager] refreshFollowCounts called for userId: \(userId)")
        do {
            let followerCount = try await firebaseService.fetchFollowerCount(userId: userId)
            let followingCount = try await firebaseService.fetchFollowingCount(userId: userId)
            await MainActor.run {
                self.followCounts[userId] = (followerCount, followingCount)
                print("✅ [FollowManager] Updated counts for \(userId): followers=\(followerCount), following=\(followingCount)")
            }
        } catch {
            print("❌ [FollowManager] Failed to refresh follow counts: \(error.localizedDescription)")
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

