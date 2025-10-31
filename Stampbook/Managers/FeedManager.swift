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
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var lastRefreshTime: Date?
    @Published var hasMorePosts = true
    
    /// Computed property: Filter current user's posts from feed
    /// This enables instant "Only Yours" tab when "All" tab has loaded
    /// No additional Firebase query needed!
    var myPosts: [FeedPost] {
        feedPosts.filter { $0.isCurrentUser }
    }
    
    private let firebaseService = FirebaseService.shared
    private let imageManager = ImageManager.shared
    private let refreshInterval: TimeInterval = 300 // 5 minutes
    private let postsPerPage = 20
    
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
        // STEP 1: Check if memory cache is fresh
        if !forceRefresh,
           !feedPosts.isEmpty,
           let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshInterval {
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
            loadDiskCache()
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
    
    /// Load more posts (pagination)
    func loadMorePosts(userId: String, stampsManager: StampsManager) async {
        guard !isLoadingMore && hasMorePosts else { return }
        
        await MainActor.run {
            isLoadingMore = true
        }
        
        // For now, just mark as no more posts since we're fetching everything at once
        // In a real pagination system, you'd fetch the next page here
        await MainActor.run {
            isLoadingMore = false
            hasMorePosts = false
        }
    }
    
    /// Fetch feed from Firebase + prefetch all images (Instagram-style)
    /// 
    /// KEY DIFFERENCE FROM OLD CODE:
    /// - Old: UI waits for each image to load individually
    /// - New: Start prefetching ALL images immediately, UI doesn't wait
    private func fetchFeedAndPrefetch(userId: String, stampsManager: StampsManager, isInitialLoad: Bool) async {
        let overallStart = CFAbsoluteTimeGetCurrent()
        print("⏱️ [FeedManager] Starting feed fetch...")
        
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
            let fetchStart = CFAbsoluteTimeGetCurrent()
            print("📡 [FeedManager] Fetching feed from Firebase...")
            let feedItems = try await firebaseService.fetchFollowingFeed(
                userId: userId,
                limit: 50,
                stampsPerUser: 10
            )
            let fetchTime = CFAbsoluteTimeGetCurrent() - fetchStart
            print("⏱️ [FeedManager] Firebase feed fetch: \(String(format: "%.3f", fetchTime))s (\(feedItems.count) items)")
            print("📊 [FeedManager] Breakdown: User profiles + collected stamps fetch completed")
            
            // Extract unique stamp IDs
            let uniqueStampIds = Array(Set(feedItems.map { $0.1.stampId }))
            
            // Fetch only the stamps needed for this feed
            let stampsStart = CFAbsoluteTimeGetCurrent()
            let stamps = await stampsManager.fetchStamps(ids: uniqueStampIds)
            let stampsTime = CFAbsoluteTimeGetCurrent() - stampsStart
            print("⏱️ [FeedManager] Stamps fetch: \(String(format: "%.3f", stampsTime))s (\(stamps.count) stamps)")
            
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
                    stampImageName: stamp.imageName,
                    location: stamp.cityCountry,
                    date: collectedStamp.collectedDate.formattedMedium(),
                    actualDate: collectedStamp.collectedDate,
                    isCurrentUser: profile.id == userId,
                    stampId: stamp.id,
                    userPhotos: collectedStamp.userImageNames,
                    note: collectedStamp.userNotes.isEmpty ? nil : collectedStamp.userNotes,
                    likeCount: 0,
                    commentCount: 0
                )
                posts.append(post)
            }
            
            let processingTime = CFAbsoluteTimeGetCurrent() - overallStart
            print("⏱️ [FeedManager] Total processing time: \(String(format: "%.3f", processingTime))s")
            
            // Update UI immediately
            await MainActor.run {
                self.feedPosts = posts
                self.lastRefreshTime = Date()
                self.isLoading = false
                self.isLoadingMore = false
                self.hasMorePosts = posts.count >= 50
            }
            print("⏱️ [FeedManager] UI updated with \(posts.count) posts")
            
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
            }
        }
    }
    
    /// Refresh feed (force fetch from server)
    func refresh(userId: String, stampsManager: StampsManager) async {
        await fetchFeedAndPrefetch(userId: userId, stampsManager: stampsManager, isInitialLoad: true)
    }
    
    /// Clear cached feed data
    func clearCache() {
        feedPosts = []
        lastRefreshTime = nil
        hasMorePosts = true
        clearDiskCache()
    }
    
    // MARK: - Disk Cache (Instagram Pattern)
    
    /// Load feed from disk cache (instant, even if stale)
    /// This is the "Instagram trick" - always show something on cold start
    private func loadDiskCache() {
        guard FileManager.default.fileExists(atPath: diskCacheURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: diskCacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedPosts = try decoder.decode([FeedPost].self, from: data)
            
            // Show cached posts immediately (even if stale)
            feedPosts = cachedPosts
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
        let prefetchStart = CFAbsoluteTimeGetCurrent()
        
        // Collect all unique profile picture URLs
        var profileUrls: Set<String> = []
        for post in posts {
            if let avatarUrl = post.avatarUrl, !avatarUrl.isEmpty {
                profileUrls.insert(avatarUrl)
            }
        }
        
        guard !profileUrls.isEmpty else {
            print("⏱️ [FeedManager] No profile pictures to prefetch")
            return
        }
        
        print("⏱️ [FeedManager] Starting prefetch of \(profileUrls.count) profile pictures...")
        
        // Prefetch all profile pics in parallel
        await withTaskGroup(of: Void.self) { group in
            for url in profileUrls {
                group.addTask {
                    let imageStart = CFAbsoluteTimeGetCurrent()
                    do {
                        _ = try await self.imageManager.downloadAndCacheProfilePicture(
                            url: url,
                            userId: "prefetch"
                        )
                        let imageTime = CFAbsoluteTimeGetCurrent() - imageStart
                        print("⏱️ [FeedManager] Profile pic prefetch: \(String(format: "%.3f", imageTime))s")
                    } catch {
                        // Silently fail - UI will show placeholder
                        print("⏱️ [FeedManager] Profile pic prefetch failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        let totalPrefetchTime = CFAbsoluteTimeGetCurrent() - prefetchStart
        print("⏱️ [FeedManager] Total profile pic prefetch: \(String(format: "%.3f", totalPrefetchTime))s")
    }
}

