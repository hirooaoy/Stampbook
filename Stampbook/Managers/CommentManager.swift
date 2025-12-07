import Foundation
import Combine

/// Manages comments with optimistic UI updates and caching
class CommentManager: ObservableObject {
    @Published private(set) var comments: [String: [Comment]] = [:] // postId -> comments
    @Published private(set) var commentCounts: [String: Int] = [:] // postId -> comment count
    @Published var isLoading: [String: Bool] = [:] // postId -> loading state
    @Published var errorMessage: String? // Error message to display to user
    @Published var hasMoreComments: [String: Bool] = [:] // postId -> has more to load
    
    private let firebaseService = FirebaseService.shared
    
    // Callback to notify FeedManager when comment count changes
    var onCommentCountChanged: ((String, Int) -> Void)?
    
    // Pagination state
    private var lastCommentDate: [String: Date] = [:] // postId -> last comment's createdAt
    
    init() {
        print("⏱️ [CommentManager] init() started")
        // Load cached comment counts for instant display on cold start
        loadCachedCommentCounts()
        print("⏱️ [CommentManager] init() completed with \(commentCounts.count) cached comment counts")
    }
    
    /// Fetch comments for a post (initial load or pagination)
    /// - Parameters:
    ///   - postId: The post ID
    ///   - loadMore: If true, loads next page. If false, refreshes from start.
    func fetchComments(postId: String, loadMore: Bool = false) async {
        await MainActor.run {
            isLoading[postId] = true
        }
        
        // Get pagination cursor (nil for initial load)
        let afterDate = loadMore ? lastCommentDate[postId] : nil
        
        do {
            let fetchedComments = try await firebaseService.fetchComments(
                postId: postId,
                limit: 50,
                after: afterDate
            )
            
            await MainActor.run {
                if loadMore {
                    // Append to existing comments
                    comments[postId]?.append(contentsOf: fetchedComments)
                } else {
                    // Replace with fresh data
                    comments[postId] = fetchedComments
                    // Always update count to match actual fetched comments
                    // This fixes desync between cached feed count and actual Firebase count
                    commentCounts[postId] = fetchedComments.count
                }
                
                // Update pagination state
                if let lastComment = fetchedComments.last {
                    lastCommentDate[postId] = lastComment.createdAt
                }
                
                // If we got fewer than the limit, there are no more comments
                hasMoreComments[postId] = fetchedComments.count >= 50
                
                isLoading[postId] = false
                
                // Save to cache for next session
                saveCachedCommentCounts()
                
                // Notify FeedManager of the updated count (only for initial load)
                if !loadMore {
                    let currentCount = comments[postId]?.count ?? 0
                    onCommentCountChanged?(postId, currentCount)
                }
            }
            
            print("✅ Fetched \(fetchedComments.count) comments for post: \(postId) (loadMore: \(loadMore))")
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
    func addComment(postId: String, stampId: String, postOwnerId: String, userId: String, text: String, userProfile: UserProfile, parentCommentId: String? = nil) {
        // ✅ REMOVED DEBOUNCE: Allow rapid commenting
        // Users should be able to post multiple comments quickly without blocking
        
        // Create optimistic comment with temp ID
        let optimisticComment = Comment(
            userId: userId,
            postId: postId,
            stampId: stampId,
            postOwnerId: postOwnerId,
            text: text,
            userDisplayName: userProfile.displayName,
            userUsername: userProfile.username,
            userAvatarUrl: userProfile.avatarUrl,
            parentCommentId: parentCommentId,
            createdAt: Date()
        )
        
        // Store the temp ID for later replacement
        let tempId = optimisticComment.computedId
        
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
                    userProfile: userProfile,
                    parentCommentId: parentCommentId
                )
                
                // Replace optimistic comment with actual comment (which has Firebase ID)
                await MainActor.run {
                    if let index = comments[postId]?.firstIndex(where: { $0.computedId == tempId }) {
                        comments[postId]?[index] = savedComment
                    }
                }
                
                print("✅ Comment added to Firebase: \(postId)")
            } catch {
                print("⚠️ Failed to add comment: \(error.localizedDescription)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    comments[postId]?.removeAll(where: { $0.computedId == tempId })
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
        // Optimistic update: Remove the comment from local cache
        // Note: Firebase will handle orphaning replies (setting parentCommentId to nil)
        // We'll refetch on error to sync with Firebase's authoritative state
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
                // Pass flag to orphan replies when deleting parent
                try await firebaseService.deleteComment(
                    commentId: commentId,
                    postOwnerId: postOwnerId,
                    stampId: stampId,
                    orphanReplies: true
                )
                
                print("✅ Comment deleted from Firebase: \(commentId)")
                
                // Refetch to sync with Firebase's orphaning of replies
                // (Backend sets parentCommentId to null for child replies)
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
    
    /// Get comments for a post, organized into threads
    /// Top-level comments sorted by date, with replies grouped under parents
    func getComments(postId: String) -> [Comment] {
        guard let allComments = comments[postId] else { return [] }
        
        // Separate top-level comments and replies
        let topLevel = allComments.filter { $0.parentCommentId == nil }
        let replies = allComments.filter { $0.parentCommentId != nil }
        
        // Sort top-level comments by date (oldest first for now - can adjust)
        let sortedTopLevel = topLevel.sorted { $0.createdAt < $1.createdAt }
        
        // Build threaded list with recursive reply gathering
        var threaded: [Comment] = []
        
        for parent in sortedTopLevel {
            // Add parent
            threaded.append(parent)
            
            // Recursively add all nested replies
            addReplies(to: parent, from: replies, into: &threaded)
        }
        
        return threaded
    }
    
    /// Recursively add replies and their nested replies
    private func addReplies(to parent: Comment, from allReplies: [Comment], into threaded: inout [Comment]) {
        guard let parentId = parent.id else { return }
        
        // Find direct replies to this parent
        let directReplies = allReplies.filter { $0.parentCommentId == parentId }
            .sorted { $0.createdAt < $1.createdAt }
        
        // Add each reply and recursively add its replies
        for reply in directReplies {
            threaded.append(reply)
            addReplies(to: reply, from: allReplies, into: &threaded)
        }
    }
    
    /// Get comment count for a post
    func getCommentCount(postId: String) -> Int {
        // Never return negative counts (defensive programming against bad data)
        return max(0, commentCounts[postId, default: 0])
    }
    
    /// Check if manager has count data for a post (to distinguish between "has 0 comments" vs "no data yet")
    func hasCountData(postId: String) -> Bool {
        return commentCounts[postId] != nil
    }
    
    /// Set initial comment counts (called when feed loads)
    /// - Parameters:
    ///   - counts: Dictionary of postId -> comment count from feed data
    ///   - isStaleData: If true, only fills in missing posts (doesn't overwrite existing)
    func setCommentCounts(_ counts: [String: Int], isStaleData: Bool = false) {
        if isStaleData {
            // Stale disk cache: Only fill in posts we don't have data for yet
            // This prevents overwriting fresh UserDefaults cache with old counts
            for (postId, count) in counts {
                if commentCounts[postId] == nil {
                    commentCounts[postId] = count
                }
            }
            #if DEBUG
            let addedCount = counts.filter { commentCounts[$0.key] == $0.value }.count
            print("📊 [CommentManager] Initialized \(addedCount) new posts from STALE data (preserved existing cache)")
            #endif
        } else {
            // Fresh Firebase data: Replace all counts with authoritative data
            commentCounts = counts
            #if DEBUG
            print("📊 [CommentManager] Replaced all counts with FRESH Firebase data (\(counts.count) posts)")
            #endif
        }
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
        hasMoreComments.removeAll()
        lastCommentDate.removeAll()
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

