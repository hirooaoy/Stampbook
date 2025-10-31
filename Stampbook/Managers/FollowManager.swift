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
    
    /// Follow a user (with optimistic UI update and state synchronization)
    func followUser(currentUserId: String, targetUserId: String, onSuccess: ((UserProfile?) -> Void)? = nil) {
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = true
        
        // Optimistically increment counts
        if let counts = followCounts[currentUserId] {
            followCounts[currentUserId] = (counts.followers, counts.following + 1)
        }
        if let counts = followCounts[targetUserId] {
            followCounts[targetUserId] = (counts.followers + 1, counts.following)
        }
        
        Task {
            do {
                let didFollow = try await firebaseService.followUser(followerId: currentUserId, followeeId: targetUserId)
                
                if didFollow {
                    // Fetch updated profile to get accurate counts
                    let targetProfile = try? await firebaseService.fetchUserProfile(userId: targetUserId)
                    let currentProfile = try? await firebaseService.fetchUserProfile(userId: currentUserId)
                    
                    await MainActor.run {
                        // Update cached counts with real values
                        if let profile = targetProfile {
                            self.followCounts[targetUserId] = (profile.followerCount, profile.followingCount)
                            
                            // SMART UPDATE: Add to following list if we're currently viewing it
                            // (only if not already in the list)
                            if !self.following.contains(where: { $0.id == targetUserId }) {
                                self.following.append(profile)
                            }
                        }
                        if let profile = currentProfile {
                            self.followCounts[currentUserId] = (profile.followerCount, profile.followingCount)
                        }
                        
                        self.isProcessingFollow[targetUserId] = false
                        onSuccess?(targetProfile)
                    }
                    print("✅ Followed user \(targetUserId)")
                } else {
                    // Already following - sync state
                    await MainActor.run {
                        self.isFollowing[targetUserId] = true
                        self.isProcessingFollow[targetUserId] = false
                    }
                    print("ℹ️ Already following user \(targetUserId)")
                }
            } catch {
                // Rollback on error
                await MainActor.run {
                    self.isFollowing[targetUserId] = false
                    
                    // Rollback count changes
                    if let counts = self.followCounts[currentUserId] {
                        self.followCounts[currentUserId] = (counts.followers, max(0, counts.following - 1))
                    }
                    if let counts = self.followCounts[targetUserId] {
                        self.followCounts[targetUserId] = (max(0, counts.followers - 1), counts.following)
                    }
                    
                    // Remove from following list if it was added
                    self.following.removeAll { $0.id == targetUserId }
                    
                    self.isProcessingFollow[targetUserId] = false
                    self.error = error.localizedDescription
                }
                print("❌ Failed to follow user: \(error.localizedDescription)")
            }
        }
    }
    
    /// Unfollow a user (with optimistic UI update and state synchronization)
    func unfollowUser(currentUserId: String, targetUserId: String, onSuccess: ((UserProfile?) -> Void)? = nil) {
        // Set processing state
        isProcessingFollow[targetUserId] = true
        
        // Optimistic update
        isFollowing[targetUserId] = false
        
        // Optimistically decrement counts
        if let counts = followCounts[currentUserId] {
            followCounts[currentUserId] = (counts.followers, max(0, counts.following - 1))
        }
        if let counts = followCounts[targetUserId] {
            followCounts[targetUserId] = (max(0, counts.followers - 1), counts.following)
        }
        
        // SMART UPDATE: Remove from following list immediately (optimistic)
        following.removeAll { $0.id == targetUserId }
        
        Task {
            do {
                let didUnfollow = try await firebaseService.unfollowUser(followerId: currentUserId, followeeId: targetUserId)
                
                if didUnfollow {
                    // Fetch updated profile to get accurate counts
                    let targetProfile = try? await firebaseService.fetchUserProfile(userId: targetUserId)
                    let currentProfile = try? await firebaseService.fetchUserProfile(userId: currentUserId)
                    
                    await MainActor.run {
                        // Update cached counts with real values
                        if let profile = targetProfile {
                            self.followCounts[targetUserId] = (profile.followerCount, profile.followingCount)
                        }
                        if let profile = currentProfile {
                            self.followCounts[currentUserId] = (profile.followerCount, profile.followingCount)
                        }
                        
                        self.isProcessingFollow[targetUserId] = false
                        onSuccess?(targetProfile)
                    }
                    print("✅ Unfollowed user \(targetUserId)")
                } else {
                    // Wasn't following - sync state
                    await MainActor.run {
                        self.isFollowing[targetUserId] = false
                        self.isProcessingFollow[targetUserId] = false
                    }
                    print("ℹ️ Wasn't following user \(targetUserId)")
                }
            } catch {
                // Rollback on error - re-add to following list
                await MainActor.run {
                    self.isFollowing[targetUserId] = true
                    
                    // Rollback count changes
                    if let counts = self.followCounts[currentUserId] {
                        self.followCounts[currentUserId] = (counts.followers, counts.following + 1)
                    }
                    if let counts = self.followCounts[targetUserId] {
                        self.followCounts[targetUserId] = (counts.followers + 1, counts.following)
                    }
                    
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
    func toggleFollow(currentUserId: String, targetUserId: String, onSuccess: ((UserProfile?) -> Void)? = nil) {
        let currentlyFollowing = isFollowing[targetUserId] ?? false
        
        if currentlyFollowing {
            unfollowUser(currentUserId: currentUserId, targetUserId: targetUserId, onSuccess: onSuccess)
        } else {
            followUser(currentUserId: currentUserId, targetUserId: targetUserId, onSuccess: onSuccess)
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
    
    // MARK: - Count Management
    
    /// Update cached follow counts for a user
    func updateFollowCounts(userId: String, followerCount: Int, followingCount: Int) {
        followCounts[userId] = (followerCount, followingCount)
    }
    
    /// Fetch and cache follow counts for a user
    func refreshFollowCounts(userId: String) {
        Task {
            do {
                let profile = try await firebaseService.fetchUserProfile(userId: userId)
                await MainActor.run {
                    self.followCounts[userId] = (profile.followerCount, profile.followingCount)
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

