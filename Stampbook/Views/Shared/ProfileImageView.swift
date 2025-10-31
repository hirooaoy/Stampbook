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
        .id("\(userId)-\(size)") // Stable identity prevents unnecessary recreation
        .task(id: "\(userId)-\(avatarUrl ?? "")-\(loadAttempt)") {
            // Only load once per unique user/avatar combination
            guard !hasAttemptedLoad || loadAttempt > 0 else { return }
            hasAttemptedLoad = true
            await loadProfilePicture()
        }
        .onAppear {
            // Only schedule retries if we have a valid avatar URL and haven't loaded yet
            guard let url = avatarUrl, !url.isEmpty, image == nil else { return }
            
            // Retry loading after short delays if image still not loaded
            // This handles the case where prefetch completes after initial render
            Task {
                // Try again after 300ms (prefetch should be done by then)
                try? await Task.sleep(nanoseconds: 300_000_000)
                if image == nil && avatarUrl != nil && !avatarUrl!.isEmpty {
                    loadAttempt += 1
                }
                
                // One more retry after 1s just in case
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if image == nil && avatarUrl != nil && !avatarUrl!.isEmpty {
                    loadAttempt += 1
                }
            }
        }
    }
    
    /// Load profile picture from cache or download from Firebase
    /// OPTIMIZED: Prioritizes cache hits, fails silently
    private func loadProfilePicture() async {
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else {
            // No avatar URL - show placeholder (already visible)
            print("🖼️ [ProfileImageView] No avatar URL for userId: \(userId)")
            return
        }
        
        print("🖼️ [ProfileImageView] Loading profile picture for userId: \(userId), attempt: \(loadAttempt)")
        
        // Don't block UI - load in background
        isLoadingImage = true
        
        do {
            // Try to load (prioritizes cache, then downloads)
            // If FeedManager prefetched, this will be instant (memory cache hit)
            let downloadedImage = try await ImageManager.shared.downloadAndCacheProfilePicture(
                url: avatarUrl,
                userId: userId
            )
            
            await MainActor.run {
                self.image = downloadedImage
                self.isLoadingImage = false
                print("✅ [ProfileImageView] Profile picture loaded for userId: \(userId)")
            }
        } catch {
            // Fail silently - placeholder already showing
            // Don't spam console - prefetch failures are expected
            await MainActor.run {
                self.isLoadingImage = false
                print("⚠️ [ProfileImageView] Failed to load profile picture for userId: \(userId): \(error.localizedDescription)")
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

