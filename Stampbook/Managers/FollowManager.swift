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
        Task {
            do {
                let following = try await firebaseService.isFollowing(followerId: currentUserId, followeeId: targetUserId)
                await MainActor.run {
                    self.isFollowing[targetUserId] = following
                }
            } catch {
                print("❌ Failed to check follow status: \(error.localizedDescription)")
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
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = true
        
        Task {
            do {
                let didFollow = try await firebaseService.followUser(followerId: currentUserId, followeeId: targetUserId)
                
                await MainActor.run {
                    self.isProcessingFollow[targetUserId] = false
                    
                    // Add to following list if we're currently viewing it
                    if didFollow {
                        // Try to fetch the target user's profile to add to list
                        Task {
                            if let profile = try? await firebaseService.fetchUserProfile(userId: targetUserId) {
                                await MainActor.run {
                                    if !self.following.contains(where: { $0.id == targetUserId }) {
                                        self.following.append(profile)
                                    }
                                }
                                onSuccess?(profile)
                            }
                        }
                    }
                }
                print("✅ Followed user \(targetUserId)")
            } catch {
                // Rollback on error
                await MainActor.run {
                    self.isFollowing[targetUserId] = false
                    self.isProcessingFollow[targetUserId] = false
                    self.error = error.localizedDescription
                }
                print("❌ Failed to follow user: \(error.localizedDescription)")
            }
        }
    }
    
    /// Unfollow a user (with optimistic UI update)
    /// Counts are fetched separately on-demand, so we don't manage them here
    func unfollowUser(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = false
        
        // Remove from following list immediately (optimistic)
        following.removeAll { $0.id == targetUserId }
        
        Task {
            do {
                let didUnfollow = try await firebaseService.unfollowUser(followerId: currentUserId, followeeId: targetUserId)
                
                await MainActor.run {
                    self.isProcessingFollow[targetUserId] = false
                }
                
                if didUnfollow {
                    print("✅ Unfollowed user \(targetUserId)")
                    onSuccess?(nil)
                }
            } catch {
                // Rollback on error - re-add to following list
                await MainActor.run {
                    self.isFollowing[targetUserId] = true
                    
                    // Re-fetch following list to restore state
                    self.fetchFollowing(userId: currentUserId)
                    
                    self.isProcessingFollow[targetUserId] = false
                    self.error = error.localizedDescription
                }
                print("❌ Failed to unfollow user: \(error.localizedDescription)")
            }
        }
    }
    
    /// Toggle follow status for a user
    func toggleFollow(currentUserId: String, targetUserId: String, profileManager: ProfileManager? = nil, onSuccess: ((UserProfile?) -> Void)? = nil) {
        let currentlyFollowing = isFollowing[targetUserId] ?? false
        
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
        followCounts[userId] = (followerCount, followingCount)
    }
    
    /// Fetch and cache follow counts for a user (on-demand from subcollections)
    func refreshFollowCounts(userId: String) {
        Task {
            do {
                let followerCount = try await firebaseService.fetchFollowerCount(userId: userId)
                let followingCount = try await firebaseService.fetchFollowingCount(userId: userId)
                await MainActor.run {
                    self.followCounts[userId] = (followerCount, followingCount)
                }
            } catch {
                print("❌ Failed to refresh follow counts: \(error.localizedDescription)")
            }
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

