import Foundation
import Combine

/// Manages user blocking operations and blocked user state
/// Should be used as a single shared instance (@EnvironmentObject) across the app
class BlockManager: ObservableObject {
    @Published var blockedUserIds: Set<String> = [] // User IDs that current user has blocked
    @Published var isBlocking: [String: Bool] = [:] // userId -> isBlocking (for button loading state)
    @Published var error: String?
    
    private let firebaseService = FirebaseService.shared
    
    // MARK: - Block Status Checking
    
    /// Check if current user has blocked another user
    func isUserBlocked(_ userId: String) -> Bool {
        return blockedUserIds.contains(userId)
    }
    
    /// Load blocked users list for current user
    func loadBlockedUsers(currentUserId: String) {
        Task {
            do {
                let blockedIds = try await firebaseService.fetchBlockedUserIds(userId: currentUserId)
                await MainActor.run {
                    self.blockedUserIds = Set(blockedIds)
                }
                print("✅ Loaded \(blockedIds.count) blocked users")
            } catch {
                print("❌ Failed to load blocked users: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Block/Unblock Actions
    
    /// Block a user
    /// - Automatically unfollows the user if following
    /// - Removes them from followers if they were following you
    /// - Hides their content from your feed
    func blockUser(currentUserId: String, targetUserId: String, onSuccess: (() -> Void)? = nil) {
        guard currentUserId != targetUserId else {
            error = "Cannot block yourself"
            return
        }
        
        // Set processing state
        isBlocking[targetUserId] = true
        
        // Optimistic update
        blockedUserIds.insert(targetUserId)
        
        Task {
            do {
                let didBlock = try await firebaseService.blockUser(blockerId: currentUserId, blockedId: targetUserId)
                
                if didBlock {
                    await MainActor.run {
                        self.isBlocking[targetUserId] = false
                        onSuccess?()
                    }
                    print("✅ Blocked user \(targetUserId)")
                } else {
                    // Already blocked
                    await MainActor.run {
                        self.isBlocking[targetUserId] = false
                    }
                    print("ℹ️ Already blocked user \(targetUserId)")
                }
            } catch {
                // Rollback on error
                await MainActor.run {
                    self.blockedUserIds.remove(targetUserId)
                    self.isBlocking[targetUserId] = false
                    self.error = error.localizedDescription
                }
                print("❌ Failed to block user: \(error.localizedDescription)")
            }
        }
    }
    
    /// Unblock a user
    func unblockUser(currentUserId: String, targetUserId: String, onSuccess: (() -> Void)? = nil) {
        // Set processing state
        isBlocking[targetUserId] = true
        
        // Optimistic update
        blockedUserIds.remove(targetUserId)
        
        Task {
            do {
                let didUnblock = try await firebaseService.unblockUser(blockerId: currentUserId, blockedId: targetUserId)
                
                if didUnblock {
                    await MainActor.run {
                        self.isBlocking[targetUserId] = false
                        onSuccess?()
                    }
                    print("✅ Unblocked user \(targetUserId)")
                } else {
                    // Wasn't blocked
                    await MainActor.run {
                        self.isBlocking[targetUserId] = false
                    }
                    print("ℹ️ Wasn't blocked user \(targetUserId)")
                }
            } catch {
                // Rollback on error
                await MainActor.run {
                    self.blockedUserIds.insert(targetUserId)
                    self.isBlocking[targetUserId] = false
                    self.error = error.localizedDescription
                }
                print("❌ Failed to unblock user: \(error.localizedDescription)")
            }
        }
    }
    
    /// Check if we should show a user's content
    /// Returns false if user is blocked
    func shouldShowUser(_ userId: String) -> Bool {
        return !blockedUserIds.contains(userId)
    }
    
    // MARK: - Cleanup
    
    /// Clear all block data (on sign out)
    func clearBlockData() {
        blockedUserIds.removeAll()
        isBlocking.removeAll()
        error = nil
    }
}

