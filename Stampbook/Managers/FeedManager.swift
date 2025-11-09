import Foundation
import Combine

/// Manages feed data with Instagram-style prefetching and disk caching
/// 
/// ARCHITECTURE:
/// - Disk cache: Shows last feed instantly on cold start (perceived < 0.5s)
/// - Prefetch: Proactively loads all images when feed data arrives
/// - Progressive: Content shows before images (no blocking)
/// 
/// This follows Instagram/Beli's "perception-first" loading model
class FeedManager: ObservableObject {
    @Published var feedPosts: [FeedPost] = []
    @Published var myPosts: [FeedPost] = [] // Separate list for "Only Yours" tab
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var lastRefreshTime: Date?
    @Published var hasMorePosts = true
    @Published var errorMessage: String? = nil // For displaying errors to user
    private var lastFetchedPostDate: Date? = nil // Track pagination cursor for "All" tab
    private var lastFetchedMyPostDate: Date? = nil // Track pagination cursor for "Only Yours" tab
    
    private let firebaseService = FirebaseService.shared
    private let imageManager = ImageManager.shared
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    private let postsPerPage = 20
    
    // MARK: - Lifecycle
    
    init() {
        // Listen for profile updates to invalidate feed cache
        // When user updates their profile photo/name, we need to refresh feed
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileUpdate),
            name: .profileDidUpdate,
            object: nil
        )
        
        // Listen for stamp collection to invalidate feed cache
        // When user collects a stamp, we need to refresh feed to show it
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStampCollection),
            name: .stampDidCollect,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Handle profile update notification
    /// Clears cached feed data so next load fetches fresh data with updated profile info
    @objc private func handleProfileUpdate(_ notification: Notification) {
        print("🔔 [FeedManager] Received profile update notification - clearing feed cache")
        
        // Clear all cached feed data (memory and disk)
        clearCache()
        
        // Post to main actor to ensure published properties update on main thread
        DispatchQueue.main.async {
            // Clear published arrays to force refresh on next view
            self.feedPosts = []
            self.myPosts = []
            print("✅ [FeedManager] Feed cache cleared, ready for refresh")
        }
    }
    
    /// Handle stamp collection notification
    /// Clears cached feed data so next load fetches fresh data with newly collected stamp
    @objc private func handleStampCollection(_ notification: Notification) {
        print("🔔 [FeedManager] Received stamp collection notification - clearing feed cache")
        
        // Clear all cached feed data (memory and disk)
        clearCache()
        
        // Post to main actor to ensure published properties update on main thread
        DispatchQueue.main.async {
            // Clear published arrays to force refresh on next view
            self.feedPosts = []
            self.myPosts = []
            print("✅ [FeedManager] Feed cache cleared after stamp collection, ready for refresh")
        }
    }
    
    // MARK: - Disk Cache (Instagram-style warm start)
    
    /// Maximum posts to persist to disk (keep recent feed for instant cold start)
    private let diskCacheLimit = 10
    
    /// File URL for persisted feed cache
    private var diskCacheURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("feed_cache.json")
    }
    
    struct FeedPost: Identifiable, Codable {
        let id: String
        let userId: String
        let userName: String
        let displayName: String
        let avatarUrl: String?
        let stampName: String
        let stampImageName: String
        let location: String
        let date: String
        let actualDate: Date
        let isCurrentUser: Bool
        let stampId: String
        let userPhotos: [String]
        let note: String?
        let likeCount: Int
        let commentCount: Int
    }
    
    /// Load feed with Instagram-style instant perceived load
    /// 
    /// FLOW:
    /// T+0ms: Load disk cache (stale feed from last session) - shows instantly
    /// T+50ms: Fetch fresh data from Firebase
    /// T+100ms: Prefetch all profile pics in parallel
    /// T+500ms: Fresh data replaces stale cache
    /// 
    /// User perceives: <100ms "instant" load
    func loadFeed(userId: String, stampsManager: StampsManager, forceRefresh: Bool = false) async {
        #if DEBUG
        print("🔍 [DEBUG] FeedManager.loadFeed called (forceRefresh: \(forceRefresh), hasPosts: \(!feedPosts.isEmpty))")
        #endif
        
        // STEP 1: Check if memory cache is fresh
        if !forceRefresh,
           !feedPosts.isEmpty,
           let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshInterval {
            #if DEBUG
            print("🔍 [DEBUG] FeedManager using cached data (age: \(Date().timeIntervalSince(lastRefresh))s)")
            #endif
            return
        }
        
        // STEP 2: Remember if we had fresh data in memory
        let hadMemoryCachedData = !feedPosts.isEmpty && lastRefreshTime != nil
        
        // STEP 3: Set loading state if we don't have fresh memory cache
        if !hadMemoryCachedData {
            await MainActor.run {
                self.isLoading = true
            }
        }
        
        // STEP 4: Show disk cache immediately (Instagram trick)
        if feedPosts.isEmpty && !forceRefresh {
            await loadDiskCache()
        }
        
        // STEP 5: Fetch fresh data from Firebase
        if !forceRefresh && hadMemoryCachedData {
            // Refresh in background
            Task {
                await fetchFeedAndPrefetch(userId: userId, stampsManager: stampsManager, isInitialLoad: false)
            }
            return
        }
        
        // First load or force refresh
        await fetchFeedAndPrefetch(userId: userId, stampsManager: stampsManager, isInitialLoad: true)
    }
    
    /// Load "Only Yours" feed (all your stamps in chronological order)
    func loadMyPosts(userId: String, stampsManager: StampsManager, forceRefresh: Bool = false) async {
        #if DEBUG
        print("🔍 [DEBUG] FeedManager.loadMyPosts called (forceRefresh: \(forceRefresh), hasPosts: \(!myPosts.isEmpty))")
        #endif
        
        // Check if we have fresh data in memory
        if !forceRefresh,
           !myPosts.isEmpty,
           let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshInterval {
            #if DEBUG
            print("🔍 [DEBUG] FeedManager using cached 'Only Yours' data")
            #endif
            return
        }
        
        await MainActor.run {
            self.isLoading = true
        }
        
        do {
            // Fetch user's profile
            let userProfile = try await firebaseService.fetchUserProfile(userId: userId)
            
            // Fetch user's collected stamps (limit 20 for first page)
            let collectedStamps = try await firebaseService.fetchCollectedStamps(for: userId, limit: 20)
            
            // Get unique stamp IDs
            let stampIds = collectedStamps.map { $0.stampId }
            // Include removed stamps - users keep feed posts even if stamp removed
            let stamps = await stampsManager.fetchStamps(ids: stampIds, includeRemoved: true)
            let stampLookup = Dictionary(uniqueKeysWithValues: stamps.map { ($0.id, $0) })
            
            // Convert to FeedPost
            var posts: [FeedPost] = []
            for collectedStamp in collectedStamps {
                guard let stamp = stampLookup[collectedStamp.stampId] else { continue }
                
                let post = FeedPost(
                    id: "\(userId)-\(collectedStamp.stampId)",
                    userId: userId,
                    userName: userProfile.username,
                    displayName: userProfile.displayName,
                    avatarUrl: userProfile.avatarUrl,
                    stampName: stamp.name,
                    stampImageName: stamp.imageUrl ?? "",
                    location: stamp.cityCountry,
                    date: collectedStamp.collectedDate.formattedMedium(),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: true,
                    stampId: stamp.id,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: collectedStamp.likeCount,
                    commentCount: collectedStamp.commentCount
                )
                posts.append(post)
            }
            
            // Update cursor
            if let lastPost = posts.last {
                lastFetchedMyPostDate = lastPost.actualDate
            }
            
            // Update UI
            await MainActor.run {
                self.myPosts = posts
                self.isLoading = false
                // Only set hasMorePosts if we got a full page
                self.hasMorePosts = posts.count == 20
            }
            
            #if DEBUG
            print("✅ [FeedManager] Loaded \(posts.count) 'Only Yours' posts")
            #endif
            
            // Prefetch images in background
            Task {
                await prefetchFeedImages(posts: posts)
            }
            
        } catch {
            print("❌ [FeedManager] Failed to load 'Only Yours' feed: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = self.getUserFriendlyError(error)
            }
            
            // Auto-dismiss error after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.errorMessage = nil
                }
            }
        }
    }
    
    /// Load more posts (pagination) for "Only Yours" tab
    func loadMoreMyPosts(userId: String, stampsManager: StampsManager) async {
        guard !isLoadingMore && hasMorePosts else { return }
        
        #if DEBUG
        print("📄 [FeedManager] Loading more 'Only Yours' posts (cursor: \(lastFetchedMyPostDate?.description ?? "none"))")
        #endif
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        do {
            // Fetch user's profile
            let userProfile = try await firebaseService.fetchUserProfile(userId: userId)
            
            // Fetch next batch of user's collected stamps with cursor
            let collectedStamps = try await firebaseService.fetchCollectedStamps(
                for: userId,
                limit: 20,
                afterDate: lastFetchedMyPostDate
            )
            
            if collectedStamps.isEmpty {
                #if DEBUG
                print("📄 [FeedManager] No more 'Only Yours' posts available")
                #endif
                await MainActor.run {
                    isLoadingMore = false
                    hasMorePosts = false
                }
                return
            }
            
            // Extract unique stamp IDs
            let stampIds = collectedStamps.map { $0.stampId }
            // Include removed stamps - users keep feed posts even if stamp removed
            let stamps = await stampsManager.fetchStamps(ids: stampIds, includeRemoved: true)
            let stampLookup = Dictionary(uniqueKeysWithValues: stamps.map { ($0.id, $0) })
            
            // Convert to FeedPost
            var newPosts: [FeedPost] = []
            for collectedStamp in collectedStamps {
                guard let stamp = stampLookup[collectedStamp.stampId] else { continue }
                
                let post = FeedPost(
                    id: "\(userId)-\(collectedStamp.stampId)",
                    userId: userId,
                    userName: userProfile.username,
                    displayName: userProfile.displayName,
                    avatarUrl: userProfile.avatarUrl,
                    stampName: stamp.name,
                    stampImageName: stamp.imageUrl ?? "",
                    location: stamp.cityCountry,
                    date: collectedStamp.collectedDate.formattedMedium(),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: true,
                    stampId: stamp.id,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: collectedStamp.likeCount,
                    commentCount: collectedStamp.commentCount
                )
                newPosts.append(post)
            }
            
            // Update cursor
            if let lastPost = newPosts.last {
                lastFetchedMyPostDate = lastPost.actualDate
            }
            
            // Filter out any duplicates before appending (safety check)
            let existingIds = Set(myPosts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }
            
            // Append to existing posts
            await MainActor.run {
                self.myPosts.append(contentsOf: uniqueNewPosts)
                self.isLoadingMore = false
                // Only set hasMorePosts if we got a full page
                self.hasMorePosts = newPosts.count == 20
            }
            
            #if DEBUG
            print("📄 [FeedManager] Loaded \(uniqueNewPosts.count) more 'Only Yours' posts (\(newPosts.count) fetched, \(newPosts.count - uniqueNewPosts.count) duplicates filtered, total: \(self.myPosts.count))")
            #endif
            
            // Prefetch images in background
            Task {
                await prefetchFeedImages(posts: uniqueNewPosts)
            }
            
        } catch {
            print("❌ [FeedManager] Failed to load more 'Only Yours' posts: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoadingMore = false
                self.errorMessage = self.getUserFriendlyError(error)
            }
            
            // Auto-dismiss error after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.errorMessage = nil
                }
            }
        }
    }
    
    /// Convert technical errors to user-friendly messages
    private func getUserFriendlyError(_ error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("network") || errorString.contains("internet") || errorString.contains("connection") {
            return "No internet connection. Showing cached posts."
        } else if errorString.contains("permission") {
            return "Unable to load feed. Please try again."
        } else if errorString.contains("timeout") {
            return "Request timed out. Please check your connection."
        } else {
            return "Couldn't load feed. Pull to refresh to try again."
        }
    }
    
    /// Load more posts (pagination)
    func loadMorePosts(userId: String, stampsManager: StampsManager) async {
        guard !isLoadingMore && hasMorePosts else { return }
        
        #if DEBUG
        print("📄 [FeedManager] Loading more posts (cursor: \(lastFetchedPostDate?.description ?? "none"))")
        #endif
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        do {
            // Fetch next batch with cursor
            let feedItems = try await firebaseService.fetchFollowingFeed(
                userId: userId,
                limit: 20,
                afterDate: lastFetchedPostDate // Cursor for pagination
            )
            
            if feedItems.isEmpty {
                #if DEBUG
                print("📄 [FeedManager] No more posts available")
                #endif
                await MainActor.run {
                    isLoadingMore = false
                    hasMorePosts = false
                }
                return
            }
            
            // Extract unique stamp IDs
            let uniqueStampIds = Array(Set(feedItems.map { $0.1.stampId }))
            // Include removed stamps - users keep feed posts even if stamp removed
            let stamps = await stampsManager.fetchStamps(ids: uniqueStampIds, includeRemoved: true)
            let stampLookup = Dictionary(uniqueKeysWithValues: stamps.map { ($0.id, $0) })
            
            // Convert to FeedPost
            var newPosts: [FeedPost] = []
            for (_, (profile, collectedStamp)) in feedItems.enumerated() {
                guard let stamp = stampLookup[collectedStamp.stampId] else {
                    continue
                }
                
                let post = FeedPost(
                    id: "\(profile.id)-\(collectedStamp.stampId)",
                    userId: profile.id,
                    userName: profile.username,
                    displayName: profile.displayName,
                    avatarUrl: profile.avatarUrl,
                    stampName: stamp.name,
                    stampImageName: stamp.imageUrl ?? "",
                    location: stamp.cityCountry,
                    date: collectedStamp.collectedDate.formattedMedium(),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: profile.id == userId,
                    stampId: stamp.id,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: collectedStamp.likeCount,
                    commentCount: collectedStamp.commentCount
                )
                newPosts.append(post)
            }
            
            // Update cursor
            if let lastPost = newPosts.last {
                lastFetchedPostDate = lastPost.actualDate
            }
            
            // Filter out any duplicates before appending (safety check)
            let existingIds = Set(feedPosts.map { $0.id })
            let uniqueNewPosts = newPosts.filter { !existingIds.contains($0.id) }
            
            // Append to existing posts
            await MainActor.run {
                self.feedPosts.append(contentsOf: uniqueNewPosts)
                self.isLoadingMore = false
                // Only set hasMorePosts if we got a full page (exactly 20 = might be more)
                self.hasMorePosts = newPosts.count == 20
            }
            
            #if DEBUG
            print("📄 [FeedManager] Loaded \(uniqueNewPosts.count) more posts (\(newPosts.count) fetched, \(newPosts.count - uniqueNewPosts.count) duplicates filtered, total: \(self.feedPosts.count))")
            #endif
            
            // Prefetch images in background
            Task {
                await prefetchFeedImages(posts: newPosts)
            }
            
        } catch {
            print("❌ [FeedManager] Failed to load more posts: \(error.localizedDescription)")
            await MainActor.run {
                isLoadingMore = false
            }
        }
    }
    
    /// Fetch feed from Firebase + prefetch all images (Instagram-style)
    /// 
    /// KEY DIFFERENCE FROM OLD CODE:
    /// - Old: UI waits for each image to load individually
    /// - New: Start prefetching ALL images immediately, UI doesn't wait
    /// 
    /// 🎯 POST-MVP OPTIMIZATION: Denormalize feed to separate collection when hitting 1K users
    /// - Create feed/{userId}/posts/{postId} collection via Cloud Function
    /// - Reduces reads from 150 to 20 per feed load (87% savings)
    /// - ACTION TRIGGER: Feed load time > 3s consistently OR 1000+ users
    private func fetchFeedAndPrefetch(userId: String, stampsManager: StampsManager, isInitialLoad: Bool) async {
        #if DEBUG
        let overallStart = CFAbsoluteTimeGetCurrent()
        print("⏱️ [FeedManager] Starting feed fetch...")
        #endif
        
        await MainActor.run {
            if isInitialLoad {
                isLoading = true
                hasMorePosts = true
            } else {
                isLoadingMore = true
            }
        }
        
        do {
            // Fetch feed data from Firebase
            #if DEBUG
            let fetchStart = CFAbsoluteTimeGetCurrent()
            print("📡 [FeedManager] Fetching feed from Firebase...")
            #endif
            
            let feedItems = try await firebaseService.fetchFollowingFeed(
                userId: userId,
                limit: 20  // ✅ Instagram-style: Fetch 20 most recent posts chronologically
            )
            
            #if DEBUG
            let fetchTime = CFAbsoluteTimeGetCurrent() - fetchStart
            print("⏱️ [FeedManager] Firebase feed fetch: \(String(format: "%.3f", fetchTime))s (\(feedItems.count) items)")
            print("📊 [FeedManager] Breakdown: User profiles + collected stamps fetch completed")
            #endif
            
            // Extract unique stamp IDs
            let uniqueStampIds = Array(Set(feedItems.map { $0.1.stampId }))
            
            // Fetch only the stamps needed for this feed
            #if DEBUG
            let stampsStart = CFAbsoluteTimeGetCurrent()
            #endif
            
            // Include removed stamps - users keep feed posts even if stamp removed
            let stamps = await stampsManager.fetchStamps(ids: uniqueStampIds, includeRemoved: true)
            
            #if DEBUG
            let stampsTime = CFAbsoluteTimeGetCurrent() - stampsStart
            print("⏱️ [FeedManager] Stamps fetch: \(String(format: "%.3f", stampsTime))s (\(stamps.count) stamps)")
            #endif
            
            // Create stamp lookup dictionary
            let stampLookup = Dictionary(uniqueKeysWithValues: stamps.map { ($0.id, $0) })
            
            // Convert to FeedPost
            var posts: [FeedPost] = []
            
            for (_, (profile, collectedStamp)) in feedItems.enumerated() {
                guard let stamp = stampLookup[collectedStamp.stampId] else {
                    continue
                }
                
                let post = FeedPost(
                    id: "\(profile.id)-\(collectedStamp.stampId)",
                    userId: profile.id,
                    userName: profile.username,
                    displayName: profile.displayName,
                    avatarUrl: profile.avatarUrl,
                    stampName: stamp.name,
                    stampImageName: stamp.imageUrl ?? "", // Use Firebase URL instead of deprecated imageName
                    location: stamp.cityCountry,
                    date: collectedStamp.collectedDate.formattedMedium(),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: profile.id == userId,
                    stampId: stamp.id,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: collectedStamp.likeCount,
                    commentCount: collectedStamp.commentCount
                )
                posts.append(post)
            }
            
            #if DEBUG
            let processingTime = CFAbsoluteTimeGetCurrent() - overallStart
            print("⏱️ [FeedManager] Total processing time: \(String(format: "%.3f", processingTime))s")
            #endif
            
            // Update cursor for pagination
            if let lastPost = posts.last {
                lastFetchedPostDate = lastPost.actualDate
            }
            
            // Update UI immediately
            await MainActor.run {
                self.feedPosts = posts
                self.lastRefreshTime = Date()
                self.isLoading = false
                self.isLoadingMore = false
                // Only set hasMorePosts if we got a full page (exactly 20 = might be more)
                self.hasMorePosts = posts.count == 20
            }
            
            #if DEBUG
            print("⏱️ [FeedManager] UI updated with \(posts.count) posts")
            #endif
            
            // Prefetch images in background (non-blocking)
            Task {
                await prefetchFeedImages(posts: posts)
            }
            
            // Save to disk for next cold start
            saveToDiskCache(posts: posts)
        } catch {
            print("❌ [FeedManager] Failed to load feed: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
                self.isLoadingMore = false
                self.errorMessage = self.getUserFriendlyError(error)
            }
            
            // Auto-dismiss error after 3 seconds
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.errorMessage = nil
                }
            }
        }
    }
    
    /// Refresh feed (force fetch from server)
    func refresh(userId: String, stampsManager: StampsManager) async {
        await fetchFeedAndPrefetch(userId: userId, stampsManager: stampsManager, isInitialLoad: true)
    }
    
    /// Update comment count for a specific post (called after comment deletion/addition)
    func updatePostCommentCount(postId: String, newCount: Int) {
        // Update in "All" feed
        if let index = feedPosts.firstIndex(where: { $0.id == postId }) {
            let updatedPost = feedPosts[index]
            feedPosts[index] = FeedPost(
                id: updatedPost.id,
                userId: updatedPost.userId,
                userName: updatedPost.userName,
                displayName: updatedPost.displayName,
                avatarUrl: updatedPost.avatarUrl,
                stampName: updatedPost.stampName,
                stampImageName: updatedPost.stampImageName,
                location: updatedPost.location,
                date: updatedPost.date,
                actualDate: updatedPost.actualDate,
                isCurrentUser: updatedPost.isCurrentUser,
                stampId: updatedPost.stampId,
                userPhotos: updatedPost.userPhotos,
                note: updatedPost.note,
                likeCount: updatedPost.likeCount,
                commentCount: newCount // Update only the comment count
            )
            print("✅ [FeedManager] Updated comment count for post \(postId) in 'All' feed: \(newCount)")
        }
        
        // Update in "Only Yours" feed
        if let index = myPosts.firstIndex(where: { $0.id == postId }) {
            let updatedPost = myPosts[index]
            myPosts[index] = FeedPost(
                id: updatedPost.id,
                userId: updatedPost.userId,
                userName: updatedPost.userName,
                displayName: updatedPost.displayName,
                avatarUrl: updatedPost.avatarUrl,
                stampName: updatedPost.stampName,
                stampImageName: updatedPost.stampImageName,
                location: updatedPost.location,
                date: updatedPost.date,
                actualDate: updatedPost.actualDate,
                isCurrentUser: updatedPost.isCurrentUser,
                stampId: updatedPost.stampId,
                userPhotos: updatedPost.userPhotos,
                note: updatedPost.note,
                likeCount: updatedPost.likeCount,
                commentCount: newCount // Update only the comment count
            )
            print("✅ [FeedManager] Updated comment count for post \(postId) in 'Only Yours' feed: \(newCount)")
        }
    }
    
    /// Clear cached feed data
    func clearCache() {
        feedPosts = []
        lastRefreshTime = nil
        hasMorePosts = true
        lastFetchedPostDate = nil // Reset pagination cursor
        clearDiskCache()
    }
    
    // MARK: - Disk Cache (Instagram Pattern)
    
    /// Load feed from disk cache (instant, even if stale)
    /// This is the "Instagram trick" - always show something on cold start
    private func loadDiskCache() async {
        guard FileManager.default.fileExists(atPath: diskCacheURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: diskCacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedPosts = try decoder.decode([FeedPost].self, from: data)
            
            // ⚡ CRITICAL FIX: Force next run loop to avoid "Publishing changes during view update"
            // Without this, disk cache loads SO FAST that state updates in same cycle as view render
            await Task.yield()
            
            // Show cached posts immediately (even if stale) - use MainActor to avoid publishing during view update
            await MainActor.run {
                self.feedPosts = cachedPosts
            }
        } catch {
            // Silently fail - will load fresh data
        }
    }
    
    /// Save feed to disk (for next cold start)
    private func saveToDiskCache(posts: [FeedPost]) {
        // Only save recent posts (limit disk usage)
        let postsToCache = Array(posts.prefix(diskCacheLimit))
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(postsToCache)
            try data.write(to: diskCacheURL, options: .atomic)
        } catch {
            // Silently fail - not critical
        }
    }
    
    /// Clear disk cache
    private func clearDiskCache() {
        try? FileManager.default.removeItem(at: diskCacheURL)
    }
    
    // MARK: - Image Prefetching (Instagram Pattern)
    
    /// Prefetch all feed images proactively (Instagram-style)
    /// 
    /// KEY INSIGHT:
    /// - Don't wait for UI to request images
    /// - Start downloading ALL images as soon as feed data arrives
    /// - UI renders immediately with placeholders, images fade in as ready
    private func prefetchFeedImages(posts: [FeedPost]) async {
        #if DEBUG
        let prefetchStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Collect all unique profile picture URLs
        var profileUrls: Set<String> = []
        for post in posts {
            if let avatarUrl = post.avatarUrl, !avatarUrl.isEmpty {
                profileUrls.insert(avatarUrl)
            }
        }
        
        guard !profileUrls.isEmpty else {
            #if DEBUG
            print("⏱️ [FeedManager] No profile pictures to prefetch")
            #endif
            return
        }
        
        #if DEBUG
        print("⏱️ [FeedManager] Starting prefetch of \(profileUrls.count) profile pictures...")
        #endif
        
        // Prefetch all profile pics in parallel
        await withTaskGroup(of: Void.self) { group in
            for url in profileUrls {
                group.addTask {
                    #if DEBUG
                    let imageStart = CFAbsoluteTimeGetCurrent()
                    #endif
                    
                    do {
                        _ = try await self.imageManager.downloadAndCacheProfilePicture(
                            url: url,
                            userId: "prefetch"
                        )
                        #if DEBUG
                        let imageTime = CFAbsoluteTimeGetCurrent() - imageStart
                        print("⏱️ [FeedManager] Profile pic prefetch: \(String(format: "%.3f", imageTime))s")
                        #endif
                    } catch {
                        // Silently fail - UI will show placeholder
                        #if DEBUG
                        print("⏱️ [FeedManager] Profile pic prefetch failed: \(error.localizedDescription)")
                        #endif
                    }
                }
            }
        }
        
        #if DEBUG
        let totalPrefetchTime = CFAbsoluteTimeGetCurrent() - prefetchStart
        print("⏱️ [FeedManager] Total profile pic prefetch: \(String(format: "%.3f", totalPrefetchTime))s")
        #endif
    }
}

