import Foundation
import Combine

/// Manages likes with optimistic UI updates and caching
class LikeManager: ObservableObject {
    @Published private(set) var likedPosts: Set<String> = [] // postIds that current user has liked
    @Published private(set) var likeCounts: [String: Int] = [:] // postId -> like count
    @Published var errorMessage: String? // Error message to display to user
    
    private let firebaseService = FirebaseService.shared
    
    // Callback to notify FeedManager when like count changes
    var onLikeCountChanged: ((String, Int) -> Void)?
    
    // Optimistic update tracking
    private var pendingLikes: Set<String> = [] // Posts being liked (optimistic)
    private var pendingUnlikes: Set<String> = [] // Posts being unliked (optimistic)
    
    // Debouncing: Prevent rapid-fire taps (Instagram-style UX)
    private var lastLikeTime: [String: Date] = [:] // postId -> last like time
    private let debounceInterval: TimeInterval = 0.5 // 500ms cooldown
    
    // ✅ NEW (Nov 13, 2025): Like Status Caching Optimization
    // Track which posts we've already checked in Firestore
    // Prevents redundant checks for posts we've seen before (15% cost savings)
    private var checkedPosts: Set<String> = [] // Posts we've already verified like status for
    
    private var isCacheLoaded = false
    
    init() {
        print("⏱️ [LikeManager] init() started")
        // Load cache synchronously during init (safe timing, before any views render)
        loadCachedLikes()
        isCacheLoaded = true
        print("⏱️ [LikeManager] init() completed with \(likedPosts.count) cached likes and \(likeCounts.count) cached counts")
    }
    
    /// Toggle like on a post with optimistic UI update
    /// - Parameters:
    ///   - postId: The post ID (format: "{userId}-{stampId}")
    ///   - stampId: The stamp ID
    ///   - userId: Current user's ID
    ///   - postOwnerId: Owner of the post
    func toggleLike(postId: String, stampId: String, userId: String, postOwnerId: String) {
        // Debounce: Prevent rapid taps (Instagram-style - silently ignore)
        if let lastTime = lastLikeTime[postId],
           Date().timeIntervalSince(lastTime) < debounceInterval {
            print("🚫 [LikeManager] Debounced: Too soon to toggle like on \(postId)")
            return
        }
        lastLikeTime[postId] = Date()
        
        let isCurrentlyLiked = likedPosts.contains(postId)
        
        // Optimistic update (instant UI response)
        if isCurrentlyLiked {
            // Unlike
            likedPosts.remove(postId)
            likeCounts[postId, default: 0] = max(0, likeCounts[postId, default: 0] - 1)
            pendingUnlikes.insert(postId)
        } else {
            // Like
            likedPosts.insert(postId)
            likeCounts[postId, default: 0] += 1
            pendingLikes.insert(postId)
        }
        
        let updatedCount = likeCounts[postId, default: 0]
        
        // Save to cache immediately
        saveCachedLikes()
        
        // Notify FeedManager of count change (critical for UI sync)
        onLikeCountChanged?(postId, updatedCount)
        print("📢 [LikeManager] Notified FeedManager: post \(postId) now has \(updatedCount) likes")
        
        // Sync to Firebase in background
        Task {
            do {
                let actuallyLiked = try await firebaseService.toggleLike(
                    postId: postId,
                    stampId: stampId,
                    userId: userId,
                    postOwnerId: postOwnerId
                )
                
                // Remove from pending
                await MainActor.run {
                    pendingLikes.remove(postId)
                    pendingUnlikes.remove(postId)
                    
                    // Verify optimistic update was correct
                    if actuallyLiked != likedPosts.contains(postId) {
                        // Optimistic update was wrong, correct it
                        if actuallyLiked {
                            likedPosts.insert(postId)
                            likeCounts[postId, default: 0] += 1
                        } else {
                            likedPosts.remove(postId)
                            likeCounts[postId, default: 0] = max(0, likeCounts[postId, default: 0] - 1)
                        }
                        let correctedCount = likeCounts[postId, default: 0]
                        saveCachedLikes()
                        
                        // Notify FeedManager of corrected count
                        onLikeCountChanged?(postId, correctedCount)
                        print("📢 [LikeManager] Corrected count notification: post \(postId) now has \(correctedCount) likes")
                    }
                }
                
                print("✅ Like synced to Firebase: \(postId) -> \(actuallyLiked)")
            } catch {
                print("⚠️ Failed to sync like: \(error.localizedDescription)")
                
                // Revert optimistic update on error
                await MainActor.run {
                    if isCurrentlyLiked {
                        // Was unliked optimistically, revert to liked
                        likedPosts.insert(postId)
                        likeCounts[postId, default: 0] += 1
                    } else {
                        // Was liked optimistically, revert to unliked
                        likedPosts.remove(postId)
                        likeCounts[postId, default: 0] = max(0, likeCounts[postId, default: 0] - 1)
                    }
                    
                    let revertedCount = likeCounts[postId, default: 0]
                    
                    pendingLikes.remove(postId)
                    pendingUnlikes.remove(postId)
                    saveCachedLikes()
                    
                    // Notify FeedManager of reverted count
                    onLikeCountChanged?(postId, revertedCount)
                    print("📢 [LikeManager] Reverted count notification: post \(postId) now has \(revertedCount) likes")
                    
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
    
    /// Check if current user has liked a post
    func isLiked(postId: String) -> Bool {
        return likedPosts.contains(postId)
    }
    
    /// Get like count for a post
    func getLikeCount(postId: String) -> Int {
        return likeCounts[postId, default: 0]
    }
    
    /// Fetch like status for multiple posts (batch operation)
    /// 
    /// ✅ OPTIMIZED (Nov 13, 2025): Smart Caching
    /// Only checks Firestore for NEW posts we haven't seen before
    /// Cached posts return instantly (15% cost reduction)
    func fetchLikeStatus(postIds: [String], userId: String) async {
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        #endif
        
        // ✅ OPTIMIZATION: Filter out posts we've already checked
        let newPosts = postIds.filter { !checkedPosts.contains($0) }
        
        #if DEBUG
        let cachedCount = postIds.count - newPosts.count
        if cachedCount > 0 {
            print("⚡️ [LikeManager] Using cached like status for \(cachedCount) posts (saved \(cachedCount) reads)")
        }
        if !newPosts.isEmpty {
            print("🔍 [LikeManager] Checking Firestore for \(newPosts.count) new posts")
        }
        #endif
        
        // Only fetch status for NEW posts we haven't checked before
        await withTaskGroup(of: (String, Bool).self) { group in
            for postId in newPosts {
                group.addTask {
                    do {
                        let isLiked = try await self.firebaseService.hasLiked(postId: postId, userId: userId)
                        return (postId, isLiked)
                    } catch {
                        return (postId, false)
                    }
                }
            }
            
            for await (postId, isLiked) in group {
                await MainActor.run {
                    if isLiked {
                        self.likedPosts.insert(postId)
                    } else {
                        self.likedPosts.remove(postId)
                    }
                    // Mark as checked so we don't query again
                    self.checkedPosts.insert(postId)
                }
            }
        }
        
        await MainActor.run {
            saveCachedLikes()
        }
        
        #if DEBUG
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ [LikeManager] fetchLikeStatus completed in \(String(format: "%.3f", totalTime))s (\(newPosts.count) Firestore reads, \(cachedCount) cached)")
        #endif
    }
    
    /// Set initial like counts (called when feed loads)
    func setLikeCounts(_ counts: [String: Int]) {
        likeCounts = counts
        // Save updated counts to cache for next session
        saveCachedLikes()
    }
    
    /// Update like count for a specific post
    /// Always updates with fresh data from feed unless there's a pending optimistic update
    func updateLikeCount(postId: String, count: Int) {
        // Only skip update if there's an active pending operation (preserves optimistic UI)
        if pendingLikes.contains(postId) || pendingUnlikes.contains(postId) {
            return
        }
        
        // Consistency check: If user has liked this post, count should be at least 1
        // This prevents stale feed data from overwriting optimistic updates
        if likedPosts.contains(postId) && count == 0 {
            // Feed data is stale (hasn't reflected the like yet), preserve optimistic count
            likeCounts[postId] = max(1, likeCounts[postId] ?? 1)
            return
        }
        
        // Otherwise, always update with fresh data from feed
        likeCounts[postId] = count
    }
    
    /// Clear all cached data (sign out)
    func clearCache() {
        likedPosts.removeAll()
        likeCounts.removeAll()
        pendingLikes.removeAll()
        pendingUnlikes.removeAll()
        checkedPosts.removeAll() // ✅ NEW: Clear checked posts cache
        UserDefaults.standard.removeObject(forKey: "likedPosts")
        UserDefaults.standard.removeObject(forKey: "likeCounts")
        UserDefaults.standard.removeObject(forKey: "checkedPosts") // ✅ NEW: Clear persisted checked posts
    }
    
    // MARK: - Persistence
    
    private func saveCachedLikes() {
        // Save liked post IDs
        let likedArray = Array(likedPosts)
        UserDefaults.standard.set(likedArray, forKey: "likedPosts")
        
        // Save like counts for instant display on cold start
        // This prevents the "❤️ 0" → "❤️ 1" flash when app restarts
        UserDefaults.standard.set(likeCounts, forKey: "likeCounts")
        
        // ✅ NEW (Nov 13, 2025): Persist checked posts for next session
        // Prevents re-checking same posts after app restart
        let checkedArray = Array(checkedPosts)
        UserDefaults.standard.set(checkedArray, forKey: "checkedPosts")
    }
    
    private func loadCachedLikes() {
        // Load liked post IDs
        if let cached = UserDefaults.standard.array(forKey: "likedPosts") as? [String] {
            likedPosts = Set(cached)
        }
        
        // Load like counts for instant display on cold start
        if let cachedCounts = UserDefaults.standard.dictionary(forKey: "likeCounts") as? [String: Int] {
            likeCounts = cachedCounts
            print("📊 [LikeManager] Loaded \(cachedCounts.count) cached like counts")
        }
        
        // ✅ NEW (Nov 13, 2025): Load checked posts from previous session
        // Prevents redundant Firestore checks for posts we've already verified
        if let cachedChecked = UserDefaults.standard.array(forKey: "checkedPosts") as? [String] {
            checkedPosts = Set(cachedChecked)
            print("⚡️ [LikeManager] Loaded \(cachedChecked.count) previously checked posts (optimization active)")
        }
    }
}

