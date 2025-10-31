import SwiftUI

/// Reusable profile picture view with automatic caching
/// 
/// Features:
/// - Checks local cache first (fast)
/// - Downloads and caches from Firebase if needed
/// - Shows loading state while downloading
/// - Falls back to placeholder if no avatar
/// - Works offline with cached images
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
    @State private var isLoading = false
    @State private var loadFailed = false
    
    var body: some View {
        Group {
            if let image = image {
                // Successfully loaded image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if isLoading {
                // Loading state
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            } else {
                // Placeholder (no avatar or failed to load)
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundColor(.gray)
                    )
            }
        }
        .task {
            await loadProfilePicture()
        }
    }
    
    /// Load profile picture from cache or download from Firebase
    private func loadProfilePicture() async {
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else {
            // No avatar URL - show placeholder
            return
        }
        
        isLoading = true
        loadFailed = false
        
        do {
            // Try to download and cache (will use cache if available)
            let downloadedImage = try await ImageManager.shared.downloadAndCacheProfilePicture(
                url: avatarUrl,
                userId: userId
            )
            
            await MainActor.run {
                self.image = downloadedImage
                self.isLoading = false
            }
        } catch {
            // Failed to load - show placeholder
            print("⚠️ Failed to load profile picture: \(error.localizedDescription)")
            await MainActor.run {
                self.loadFailed = true
                self.isLoading = false
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

