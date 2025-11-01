import Foundation
import Combine

/// Manages comments with optimistic UI updates
class CommentManager: ObservableObject {
    @Published private(set) var comments: [String: [Comment]] = [:] // postId -> comments
    @Published private(set) var commentCounts: [String: Int] = [:] // postId -> comment count
    @Published var isLoading: [String: Bool] = [:] // postId -> loading state
    
    private let firebaseService = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    /// Fetch comments for a post
    func fetchComments(postId: String) async {
        await MainActor.run {
            isLoading[postId] = true
        }
        
        do {
            let fetchedComments = try await firebaseService.fetchComments(postId: postId, limit: 100)
            
            await MainActor.run {
                comments[postId] = fetchedComments
                commentCounts[postId] = fetchedComments.count
                isLoading[postId] = false
            }
            
            print("✅ Fetched \(fetchedComments.count) comments for post: \(postId)")
        } catch {
            print("⚠️ Failed to fetch comments: \(error.localizedDescription)")
            await MainActor.run {
                isLoading[postId] = false
            }
        }
    }
    
    /// Add a comment to a post with optimistic UI update
    @MainActor
    func addComment(postId: String, stampId: String, postOwnerId: String, userId: String, text: String, userProfile: UserProfile) {
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
                }
            }
        }
    }
    
    /// Delete a comment
    @MainActor
    func deleteComment(commentId: String, postId: String, postOwnerId: String, stampId: String) {
        print("🗑️ CommentManager: Deleting comment \(commentId) from post \(postId)")
        
        // Optimistic update
        let removedCount = comments[postId]?.count ?? 0
        comments[postId]?.removeAll(where: { $0.id == commentId })
        let newCount = comments[postId]?.count ?? 0
        
        print("   Removed from UI: \(removedCount) -> \(newCount) comments")
        
        commentCounts[postId, default: 1] = max(0, commentCounts[postId, default: 1] - 1)
        
        // Sync to Firebase in background
        Task {
            do {
                try await firebaseService.deleteComment(
                    commentId: commentId,
                    postOwnerId: postOwnerId,
                    stampId: stampId
                )
                
                print("✅ CommentManager: Comment deleted from Firebase: \(commentId)")
            } catch {
                print("❌ CommentManager: Failed to delete comment: \(error.localizedDescription)")
                
                // On error, refetch comments to get accurate state
                print("   Refetching comments to restore accurate state...")
                await fetchComments(postId: postId)
            }
        }
    }
    
    /// Get comments for a post
    func getComments(postId: String) -> [Comment] {
        return comments[postId] ?? []
    }
    
    /// Get comment count for a post
    func getCommentCount(postId: String) -> Int {
        return commentCounts[postId, default: 0]
    }
    
    /// Set initial comment counts (called when feed loads)
    func setCommentCounts(_ counts: [String: Int]) {
        commentCounts = counts
    }
    
    /// Update comment count for a specific post
    /// Only updates if the post doesn't already have a count (preserves optimistic updates)
    func updateCommentCount(postId: String, count: Int) {
        // Don't overwrite existing count if it's already set
        // This preserves optimistic updates and prevents stale feed data from overwriting
        if commentCounts[postId] == nil {
            commentCounts[postId] = count
        }
    }
    
    /// Clear all cached data (sign out)
    func clearCache() {
        comments.removeAll()
        commentCounts.removeAll()
        isLoading.removeAll()
    }
}

