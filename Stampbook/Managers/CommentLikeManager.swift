import Foundation
import Combine

/// Manages comment likes with optimistic UI updates and caching
@MainActor
class CommentLikeManager: ObservableObject {
    @Published private(set) var likedComments: Set<String> = [] // commentIds that current user has liked
    @Published private(set) var likeCounts: [String: Int] = [:] // commentId -> like count
    @Published var errorMessage: String? // Error message to display to user
    
    private let firebaseService = FirebaseService.shared
    
    // Callback to notify CommentManager when like count changes
    var onLikeCountChanged: ((String, Int) -> Void)?
    
    // Optimistic update tracking
    private var pendingLikes: Set<String> = [] // Comments being liked (optimistic)
    private var pendingUnlikes: Set<String> = [] // Comments being unliked (optimistic)
    
    // Debouncing: Prevent rapid-fire taps (Instagram-style UX)
    private var lastLikeTime: [String: Date] = [:] // commentId -> last like time
    private let debounceInterval: TimeInterval = 0.5 // 500ms cooldown
    
    // Like Status Caching Optimization
    // Track which comments we've already checked in Firestore
    private var checkedComments: Set<String> = [] // Comments we've already verified like status for
    
    private var isCacheLoaded = false
    
    init() {
        print("⏱️ [CommentLikeManager] init() started")
        // Load cache synchronously during init (safe timing, before any views render)
        loadCachedLikes()
        isCacheLoaded = true
        print("⏱️ [CommentLikeManager] init() completed with \(likedComments.count) cached likes and \(likeCounts.count) cached counts")
    }
    
    /// Toggle like on a comment with optimistic UI update
    /// - Parameters:
    ///   - commentId: The comment ID
    ///   - postId: The post ID (format: "{userId}-{stampId}")
    ///   - stampId: The stamp ID
    ///   - userId: Current user's ID
    ///   - commentOwnerId: Owner of the comment being liked
    func toggleLike(commentId: String, postId: String, stampId: String, userId: String, commentOwnerId: String) {
        // Debounce: Prevent rapid taps (Instagram-style - silently ignore)
        if let lastTime = lastLikeTime[commentId],
           Date().timeIntervalSince(lastTime) < debounceInterval {
            print("🚫 [CommentLikeManager] Debounced: Too soon to toggle like on \(commentId)")
            return
        }
        lastLikeTime[commentId] = Date()
        
        let isCurrentlyLiked = likedComments.contains(commentId)
        
        // Optimistic update (instant UI response)
        if isCurrentlyLiked {
            // Unlike
            likedComments.remove(commentId)
            likeCounts[commentId, default: 0] = max(0, likeCounts[commentId, default: 0] - 1)
            pendingUnlikes.insert(commentId)
        } else {
            // Like
            likedComments.insert(commentId)
            likeCounts[commentId, default: 0] += 1
            pendingLikes.insert(commentId)
        }
        
        let updatedCount = likeCounts[commentId, default: 0]
        
        // Save to cache immediately
        saveCachedLikes()
        
        // Notify CommentManager of count change (critical for UI sync)
        onLikeCountChanged?(commentId, updatedCount)
        print("📢 [CommentLikeManager] Notified CommentManager: comment \(commentId) now has \(updatedCount) likes")
        
        // Sync to Firebase in background
        Task {
            do {
                let actuallyLiked = try await firebaseService.toggleCommentLike(
                    commentId: commentId,
                    postId: postId,
                    stampId: stampId,
                    userId: userId,
                    commentOwnerId: commentOwnerId
                )
                
                // Remove from pending
                await MainActor.run {
                    pendingLikes.remove(commentId)
                    pendingUnlikes.remove(commentId)
                    
                    // Verify optimistic update was correct
                    if actuallyLiked != likedComments.contains(commentId) {
                        // Optimistic update was wrong, correct it
                        if actuallyLiked {
                            likedComments.insert(commentId)
                            likeCounts[commentId, default: 0] += 1
                        } else {
                            likedComments.remove(commentId)
                            likeCounts[commentId, default: 0] = max(0, likeCounts[commentId, default: 0] - 1)
                        }
                        let correctedCount = likeCounts[commentId, default: 0]
                        saveCachedLikes()
                        
                        // Notify CommentManager of corrected count
                        onLikeCountChanged?(commentId, correctedCount)
                        print("📢 [CommentLikeManager] Corrected count notification: comment \(commentId) now has \(correctedCount) likes")
                    }
                }
                
                print("✅ Comment like synced to Firebase: \(commentId) -> \(actuallyLiked)")
            } catch {
                print("⚠️ Failed to sync comment like: \(error.localizedDescription)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    if isCurrentlyLiked {
                        // Was unliked optimistically, revert to liked
                        likedComments.insert(commentId)
                        likeCounts[commentId, default: 0] += 1
                    } else {
                        // Was liked optimistically, revert to unliked
                        likedComments.remove(commentId)
                        likeCounts[commentId, default: 0] = max(0, likeCounts[commentId, default: 0] - 1)
                    }
                    
                    let revertedCount = likeCounts[commentId, default: 0]
                    
                    pendingLikes.remove(commentId)
                    pendingUnlikes.remove(commentId)
                    saveCachedLikes()
                    
                    // Notify CommentManager of reverted count
                    onLikeCountChanged?(commentId, revertedCount)
                    print("📢 [CommentLikeManager] Reverted count notification: comment \(commentId) now has \(revertedCount) likes")
                    
                    // Show user-friendly error message
                    errorMessage = "Couldn't sync like. Check your connection."
                    
                    // Clear message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            if errorMessage == "Couldn't sync like. Check your connection." {
                                errorMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Check if current user has liked a comment
    func isLiked(commentId: String) -> Bool {
        return likedComments.contains(commentId)
    }
    
    /// Get like count for a comment
    func getLikeCount(commentId: String) -> Int {
        return likeCounts[commentId, default: 0]
    }
    
    /// Check if manager has count data for a comment
    func hasCountData(commentId: String) -> Bool {
        return likeCounts[commentId] != nil
    }
    
    /// Fetch like status for multiple comments (batch operation)
    func fetchLikeStatus(commentIds: [String], userId: String) async {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Filter out comments we've already checked
        let newComments = commentIds.filter { !checkedComments.contains($0) }
        
        #if DEBUG
        let cachedCount = commentIds.count - newComments.count
        if cachedCount > 0 {
            print("⚡️ [CommentLikeManager] Using cached like status for \(cachedCount) comments (saved \(cachedCount) reads)")
        }
        if !newComments.isEmpty {
            print("🔍 [CommentLikeManager] Batch checking Firestore for \(newComments.count) new comments")
        }
        #endif
        
        guard !newComments.isEmpty else { return }
        
        // ✅ OPTIMIZED: Use batch query instead of N+1 individual queries
        // Old: 100 comments = 100 individual reads
        // New: 100 comments = 10 batched queries (90% cost reduction)
        do {
            let likedCommentIds = try await firebaseService.batchCheckCommentLikes(
                commentIds: newComments,
                userId: userId
            )
            
            await MainActor.run {
                // Update liked status for all checked comments
                for commentId in newComments {
                    if likedCommentIds.contains(commentId) {
                        self.likedComments.insert(commentId)
                    } else {
                        self.likedComments.remove(commentId)
                    }
                    // Mark as checked so we don't query again
                    self.checkedComments.insert(commentId)
                }
                
                saveCachedLikes()
            }
        } catch {
            print("⚠️ [CommentLikeManager] Failed to batch check comment likes: \(error.localizedDescription)")
        }
        
        #if DEBUG
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ [CommentLikeManager] fetchLikeStatus completed in \(String(format: "%.3f", totalTime))s (\(newComments.count) comments checked, \(cachedCount) cached)")
        #endif
    }
    
    /// Set initial like counts for comments (called when comments load)
    func setLikeCounts(_ counts: [String: Int]) {
        for (commentId, count) in counts {
            // Only update if we don't have data yet (prevents overwriting optimistic updates)
            if likeCounts[commentId] == nil {
                likeCounts[commentId] = count
            }
        }
        saveCachedLikes()
    }
    
    /// Update like count for a specific comment
    func updateLikeCount(commentId: String, count: Int) {
        // Only skip update if there's an active pending operation
        if pendingLikes.contains(commentId) || pendingUnlikes.contains(commentId) {
            return
        }
        
        // Consistency check: If user has liked this comment, count should be at least 1
        if likedComments.contains(commentId) && count == 0 {
            likeCounts[commentId] = max(1, likeCounts[commentId] ?? 1)
            return
        }
        
        likeCounts[commentId] = count
    }
    
    /// Clear all cached data (sign out)
    func clearCache() {
        likedComments.removeAll()
        likeCounts.removeAll()
        pendingLikes.removeAll()
        pendingUnlikes.removeAll()
        checkedComments.removeAll()
        UserDefaults.standard.removeObject(forKey: "likedComments")
        UserDefaults.standard.removeObject(forKey: "commentLikeCounts")
        UserDefaults.standard.removeObject(forKey: "checkedComments")
    }
    
    // MARK: - Persistence
    
    private func saveCachedLikes() {
        let likedArray = Array(likedComments)
        UserDefaults.standard.set(likedArray, forKey: "likedComments")
        
        UserDefaults.standard.set(likeCounts, forKey: "commentLikeCounts")
        
        let checkedArray = Array(checkedComments)
        UserDefaults.standard.set(checkedArray, forKey: "checkedComments")
    }
    
    private func loadCachedLikes() {
        if let cached = UserDefaults.standard.array(forKey: "likedComments") as? [String] {
            likedComments = Set(cached)
        }
        
        if let cachedCounts = UserDefaults.standard.dictionary(forKey: "commentLikeCounts") as? [String: Int] {
            likeCounts = cachedCounts
            print("📊 [CommentLikeManager] Loaded \(cachedCounts.count) cached comment like counts")
        }
        
        if let cachedChecked = UserDefaults.standard.array(forKey: "checkedComments") as? [String] {
            checkedComments = Set(cachedChecked)
            print("⚡️ [CommentLikeManager] Loaded \(cachedChecked.count) previously checked comments (optimization active)")
        }
    }
}

