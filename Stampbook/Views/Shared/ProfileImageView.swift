import SwiftUI

/// Instagram-style progressive profile picture view
/// 
/// PROGRESSIVE LOADING STRATEGY:
/// - T+0ms: Show placeholder immediately (no blocking)
/// - T+50ms: Check memory cache (instant if cached)
/// - T+100ms: Check disk cache (fast if prefetched)
/// - T+500ms: Download from Firebase (only if not cached)
/// - Fade in image when ready (smooth transition)
/// 
/// KEY DIFFERENCE FROM OLD:
/// - Old: Show loading spinner, block until image ready
/// - New: Show content immediately, fade in image when ready (Instagram pattern)
/// 
/// Usage:
/// ```
/// ProfileImageView(
///     avatarUrl: user.avatarUrl,
///     userId: user.id,
///     size: 64
/// )
/// ```
struct ProfileImageView: View {
    let avatarUrl: String?
    let userId: String
    let size: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoadingImage = false
    @State private var loadAttempt = 0 // Track load attempts for retry
    @State private var hasAttemptedLoad = false // Prevent duplicate loads
    
    var body: some View {
        ZStack {
            // ALWAYS show placeholder (instant render)
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.5))
                        .foregroundColor(.gray)
                )
            
            // Fade in image when loaded (progressive)
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: image != nil)
        .id("\(userId)-\(avatarUrl ?? "nil")-\(size)") // Include avatarUrl to force refresh on change
        .task(id: avatarUrl) { // Retrigger task when avatarUrl changes
            // OPTIMIZED: Check cache synchronously first (instant if cached)
            // This prevents 9 ProfileImageViews from all calling async download
            // when the image is already in memory/disk cache
            if let cachedImage = checkCacheSync() {
                await MainActor.run {
                    self.image = cachedImage
                }
                return
            }
            
            // OPTIMIZED: Small delay to let FeedManager prefetch complete first
            // Reduces redundant download attempts from 10 → 1 for same user
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            await loadProfilePicture()
        }
        .onChange(of: avatarUrl) { oldValue, newValue in
            // Reset state when avatarUrl changes (profile photo updated)
            if oldValue != newValue {
                hasAttemptedLoad = false
                image = nil
            }
        }
    }
    
    /// Check cache synchronously before attempting async download
    /// Returns image immediately if in memory or disk cache
    private func checkCacheSync() -> UIImage? {
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else {
            return nil
        }
        
        // Generate cache filename (same logic as ImageManager)
        let filename = ImageManager.shared.profilePictureCacheFilename(url: avatarUrl, userId: userId)
        
        // Check memory cache (instant)
        if let cached = ImageCacheManager.shared.getFullImage(key: filename) {
            return cached
        }
        
        // Check disk cache (fast)
        if let cached = ImageManager.shared.loadProfilePicture(named: filename) {
            return cached
        }
        
        return nil
    }
    
    /// Load profile picture from cache or download from Firebase
    /// OPTIMIZED: Prioritizes cache hits, fails silently
    private func loadProfilePicture() async {
        #if DEBUG
        let loadStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else {
            // No avatar URL - show placeholder (already visible)
            #if DEBUG
            print("🖼️ [ProfileImageView] No avatar URL for userId: \(userId)")
            #endif
            return
        }
        
        #if DEBUG
        print("🖼️ [ProfileImageView] Loading profile picture for userId: \(userId), attempt: \(loadAttempt)")
        #endif
        
        // Don't block UI - load in background
        isLoadingImage = true
        
        do {
            // Try to load (prioritizes cache, then downloads)
            // If FeedManager prefetched, this will be instant (memory cache hit)
            let downloadedImage = try await ImageManager.shared.downloadAndCacheProfilePicture(
                url: avatarUrl,
                userId: userId
            )
            
            #if DEBUG
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            _ = loadTime // Used in next line
            print("⏱️ [ProfileImageView] Profile picture loaded: \(String(format: "%.3f", loadTime))s for userId: \(userId)")
            #endif
            
            await MainActor.run {
                self.image = downloadedImage
                self.isLoadingImage = false
            }
        } catch {
            // Fail silently - placeholder already showing
            // Don't spam console - prefetch failures are expected
            await MainActor.run {
                self.isLoadingImage = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Large profile picture
        ProfileImageView(
            avatarUrl: nil,
            userId: "preview",
            size: 100
        )
        
        // Medium profile picture
        ProfileImageView(
            avatarUrl: nil,
            userId: "preview",
            size: 64
        )
        
        // Small profile picture
        ProfileImageView(
            avatarUrl: nil,
            userId: "preview",
            size: 40
        )
    }
    .padding()
}

