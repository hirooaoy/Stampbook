import Foundation
import Combine

/// Manages comments with optimistic UI updates and caching
class CommentManager: ObservableObject {
    @Published private(set) var comments: [String: [Comment]] = [:] // postId -> comments
    @Published private(set) var commentCounts: [String: Int] = [:] // postId -> comment count
    @Published var isLoading: [String: Bool] = [:] // postId -> loading state
    @Published var errorMessage: String? // Error message to display to user
    
    private let firebaseService = FirebaseService.shared
    
    // Callback to notify FeedManager when comment count changes
    var onCommentCountChanged: ((String, Int) -> Void)?
    
    // Debouncing: Prevent rapid-fire comment posting
    private var lastCommentTime: Date?
    private let debounceInterval: TimeInterval = 0.5 // 500ms cooldown
    
    init() {
        print("⏱️ [CommentManager] init() started")
        // Load cached comment counts for instant display on cold start
        loadCachedCommentCounts()
        print("⏱️ [CommentManager] init() completed with \(commentCounts.count) cached comment counts")
    }
    
    /// Fetch comments for a post
    func fetchComments(postId: String) async {
        await MainActor.run {
            isLoading[postId] = true
        }
        
        do {
            let fetchedComments = try await firebaseService.fetchComments(postId: postId, limit: 100)
            
            await MainActor.run {
                comments[postId] = fetchedComments
                // Always update count to match actual fetched comments
                // This fixes desync between cached feed count and actual Firebase count
                commentCounts[postId] = fetchedComments.count
                isLoading[postId] = false
                
                // Save to cache for next session
                saveCachedCommentCounts()
                
                // Notify FeedManager of the updated count
                onCommentCountChanged?(postId, fetchedComments.count)
            }
            
            print("✅ Fetched \(fetchedComments.count) comments for post: \(postId)")
        } catch {
            print("⚠️ Failed to fetch comments: \(error.localizedDescription)")
            await MainActor.run {
                isLoading[postId] = false
                
                // Show user-friendly error message
                errorMessage = "Couldn't load comments. Pull to refresh."
                
                // Clear message after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        if errorMessage == "Couldn't load comments. Pull to refresh." {
                            errorMessage = nil
                        }
                    }
                }
            }
        }
    }
    
    /// Add a comment to a post with optimistic UI update
    @MainActor
    func addComment(postId: String, stampId: String, postOwnerId: String, userId: String, text: String, userProfile: UserProfile) {
        // Debounce: Prevent rapid comment posting (Instagram-style - silently ignore)
        if let lastTime = lastCommentTime,
           Date().timeIntervalSince(lastTime) < debounceInterval {
            print("🚫 [CommentManager] Debounced: Too soon to post another comment")
            return
        }
        lastCommentTime = Date()
        
        // Create optimistic comment
        let optimisticComment = Comment(
            userId: userId,
            postId: postId,
            stampId: stampId,
            postOwnerId: postOwnerId,
            text: text,
            userDisplayName: userProfile.displayName,
            userUsername: userProfile.username,
            userAvatarUrl: userProfile.avatarUrl,
            createdAt: Date()
        )
        
        // Optimistic update
        if comments[postId] == nil {
            comments[postId] = []
        }
        comments[postId]?.append(optimisticComment)
        commentCounts[postId, default: 0] += 1
        let updatedCount = commentCounts[postId, default: 0]
        
        // Save to cache immediately
        saveCachedCommentCounts()
        
        // Notify FeedManager of count change (critical for UI sync)
        onCommentCountChanged?(postId, updatedCount)
        print("📢 [CommentManager] Notified FeedManager: post \(postId) now has \(updatedCount) comments")
        
        // Sync to Firebase in background
        Task {
            do {
                let savedComment = try await firebaseService.addComment(
                    postId: postId,
                    stampId: stampId,
                    postOwnerId: postOwnerId,
                    userId: userId,
                    text: text,
                    userProfile: userProfile
                )
                
                // Replace optimistic comment with actual comment (which has ID)
                await MainActor.run {
                    if let index = comments[postId]?.firstIndex(where: { 
                        $0.createdAt == optimisticComment.createdAt && $0.userId == userId 
                    }) {
                        comments[postId]?[index] = savedComment
                    }
                }
                
                print("✅ Comment added to Firebase: \(postId)")
            } catch {
                print("⚠️ Failed to add comment: \(error.localizedDescription)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    comments[postId]?.removeAll(where: { 
                        $0.createdAt == optimisticComment.createdAt && $0.userId == userId 
                    })
                    commentCounts[postId, default: 1] = max(0, commentCounts[postId, default: 1] - 1)
                    let revertedCount = commentCounts[postId, default: 0]
                    
                    // Save reverted state to cache
                    saveCachedCommentCounts()
                    
                    // Notify FeedManager of reverted count
                    onCommentCountChanged?(postId, revertedCount)
                    print("📢 [CommentManager] Reverted count notification: post \(postId) now has \(revertedCount) comments")
                    
                    // Show user-friendly error message
                    errorMessage = "Couldn't post comment. Check your connection."
                    
                    // Clear message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            if errorMessage == "Couldn't post comment. Check your connection." {
                                errorMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Delete a comment
    @MainActor
    func deleteComment(commentId: String, postId: String, postOwnerId: String, stampId: String) {
        // Optimistic update
        let removedCount = comments[postId]?.count ?? 0
        comments[postId]?.removeAll(where: { $0.id == commentId })
        let newCount = comments[postId]?.count ?? 0
        
        if removedCount == newCount {
            print("⚠️ Comment not found in cache: \(commentId)")
        }
        
        commentCounts[postId, default: 1] = max(0, commentCounts[postId, default: 1] - 1)
        let updatedCount = commentCounts[postId, default: 0]
        
        // Save to cache immediately
        saveCachedCommentCounts()
        
        // Notify FeedManager of count change (critical for UI sync)
        onCommentCountChanged?(postId, updatedCount)
        print("📢 [CommentManager] Notified FeedManager: post \(postId) now has \(updatedCount) comments")
        
        // Sync to Firebase in background
        Task {
            do {
                try await firebaseService.deleteComment(
                    commentId: commentId,
                    postOwnerId: postOwnerId,
                    stampId: stampId
                )
                
                print("✅ Comment deleted from Firebase: \(commentId)")
                
                // Refetch to ensure accuracy
                await fetchComments(postId: postId)
            } catch {
                print("❌ Failed to delete comment: \(error.localizedDescription)")
                
                // On error, refetch to restore accurate state
                await fetchComments(postId: postId)
                
                // Show user-friendly error message
                await MainActor.run {
                    errorMessage = "Couldn't delete comment. Try again."
                    
                    // Clear message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            if errorMessage == "Couldn't delete comment. Try again." {
                                errorMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Get comments for a post
    func getComments(postId: String) -> [Comment] {
        return comments[postId] ?? []
    }
    
    /// Get comment count for a post
    func getCommentCount(postId: String) -> Int {
        // Never return negative counts (defensive programming against bad data)
        return max(0, commentCounts[postId, default: 0])
    }
    
    /// Set initial comment counts (called when feed loads)
    /// Overwrites existing counts with authoritative data from Firestore
    func setCommentCounts(_ counts: [String: Int]) {
        #if DEBUG
        print("📊 [CommentManager] setCommentCounts called with \(counts.count) posts")
        #endif
        commentCounts = counts
        saveCachedCommentCounts() // Persist to disk so cache stays fresh
    }
    
    /// Update comment count for a specific post
    /// When forceUpdate is true, always updates (used for feed refresh)
    /// When false, only updates if count doesn't exist (preserves optimistic updates)
    func updateCommentCount(postId: String, count: Int, forceUpdate: Bool = false) {
        if forceUpdate || commentCounts[postId] == nil {
            // Validate count - never allow negative values (defensive programming)
            commentCounts[postId] = max(0, count)
            // Save updated count to cache
            saveCachedCommentCounts()
        }
    }
    
    /// Clear all cached data (sign out)
    func clearCache() {
        comments.removeAll()
        commentCounts.removeAll()
        isLoading.removeAll()
        UserDefaults.standard.removeObject(forKey: "commentCounts")
    }
    
    // MARK: - Persistence
    
    private func saveCachedCommentCounts() {
        // Save comment counts for instant display on cold start
        // This prevents showing stale counts from disk cache after comment deletion
        UserDefaults.standard.set(commentCounts, forKey: "commentCounts")
    }
    
    private func loadCachedCommentCounts() {
        // Load comment counts for instant display on cold start
        if let cachedCounts = UserDefaults.standard.dictionary(forKey: "commentCounts") as? [String: Int] {
            // Validate cached counts - fix any negative values (defensive programming)
            commentCounts = cachedCounts.mapValues { max(0, $0) }
            print("📊 [CommentManager] Loaded \(cachedCounts.count) cached comment counts")
        }
    }
}

