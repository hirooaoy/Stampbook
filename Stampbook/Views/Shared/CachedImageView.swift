import SwiftUI

/// Generic cached image view that handles both profile pictures and stamp photos
/// Consolidates duplicate logic from AsyncImageView and ProfileImageView
struct CachedImageView: View {
    enum ImageType {
        case stampPhoto(imageName: String?, storagePath: String?, stampId: String, imageUrl: String?)
        case profilePicture(avatarUrl: String?, userId: String)
    }
    
    enum Shape: Equatable {
        case rectangle(cornerRadius: CGFloat)
        case circle
    }
    
    let imageType: ImageType
    let shape: Shape
    let size: CGSize
    let useFullResolution: Bool // If true, loads full-res image for stamp photos (detail view)
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let image = image {
                renderImage(image)
            } else {
                renderPlaceholder()
            }
        }
        .task {
            await loadImage()
        }
    }
    
    // MARK: - Rendering
    
    @ViewBuilder
    private func renderImage(_ uiImage: UIImage) -> some View {
        let imageView = Image(uiImage: uiImage)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .clipped()
        
        switch shape {
        case .rectangle(let cornerRadius):
            imageView.cornerRadius(cornerRadius)
        case .circle:
            imageView.clipShape(Circle())
        }
    }
    
    @ViewBuilder
    private func renderPlaceholder() -> some View {
        switch shape {
        case .rectangle(let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius)
                // Show transparent while loading (gray box underneath visible)
                // Show gray background if failed (matches feed/everywhere else)
                .fill(isLoading ? Color.clear : Color.gray.opacity(0.1))
                .frame(width: size.width, height: size.height)
                .overlay(placeholderContent())
        case .circle:
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size.width, height: size.height)
                .overlay(placeholderContent())
        }
    }
    
    @ViewBuilder
    private func placeholderContent() -> some View {
        if isLoading {
            ProgressView()
                .tint(.gray)
                .scaleEffect(shape == .circle ? 0.8 : 1.0)
        } else {
            placeholderIcon()
        }
    }
    
    @ViewBuilder
    private func placeholderIcon() -> some View {
        switch imageType {
        case .stampPhoto:
            Image(systemName: "photo")
                .foregroundColor(.gray)
        case .profilePicture:
            Image(systemName: "person.fill")
                .font(.system(size: size.width * 0.5))
                .foregroundColor(.gray)
        }
    }
    
    // MARK: - Loading
    
    private func loadImage() async {
        switch imageType {
        case .stampPhoto(let imageName, let storagePath, let stampId, let imageUrl):
            await loadStampPhoto(imageName: imageName, storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
        case .profilePicture(let avatarUrl, let userId):
            await loadProfilePicture(avatarUrl: avatarUrl, userId: userId)
        }
    }
    
    private func loadStampPhoto(imageName: String?, storagePath: String?, stampId: String, imageUrl: String?) async {
        // Try loading from local cache first (instant if exists)
        if let imageName = imageName,
           let cachedImage = ImageManager.shared.loadThumbnail(named: imageName) {
            await MainActor.run {
                self.image = cachedImage
            }
            
            // If full resolution is needed, continue to load full-res in background
            if useFullResolution, let storagePath = storagePath {
                await loadFullResolution(storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
            }
            return
        }
        
        // If we have a storage path, download from Firebase
        guard let storagePath = storagePath else {
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Progressive loading: Load thumbnail first, then full-res if needed
        if useFullResolution {
            // Load thumbnail first (fast)
            do {
                let thumbnail = try await ImageManager.shared.downloadAndCacheThumbnail(
                    storagePath: storagePath,
                    stampId: stampId,
                    imageUrl: imageUrl
                )
                
                await MainActor.run {
                    self.image = thumbnail
                    // Keep loading indicator while full-res loads
                }
                
                // Then load full-res (upgrade)
                await loadFullResolution(storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
            } catch {
                print("⚠️ Failed to download thumbnail: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                }
            }
        } else {
            // Just load thumbnail
            do {
                let downloadedImage = try await ImageManager.shared.downloadAndCacheThumbnail(
                    storagePath: storagePath,
                    stampId: stampId,
                    imageUrl: imageUrl
                )
                
                await MainActor.run {
                    self.image = downloadedImage
                    isLoading = false
                }
            } catch {
                print("⚠️ Failed to download image: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func loadFullResolution(storagePath: String, stampId: String, imageUrl: String?) async {
        do {
            let fullResImage = try await ImageManager.shared.downloadAndCacheImage(
                storagePath: storagePath,
                stampId: stampId,
                imageUrl: imageUrl
            )
            
            await MainActor.run {
                // Smoothly transition to full-res
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.image = fullResImage
                    self.isLoading = false
                }
            }
        } catch {
            print("⚠️ Failed to download full-res image: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadProfilePicture(avatarUrl: String?, userId: String) async {
        guard let avatarUrl = avatarUrl, !avatarUrl.isEmpty else {
            // No avatar URL - show placeholder
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let downloadedImage = try await ImageManager.shared.downloadAndCacheProfilePicture(
                url: avatarUrl,
                userId: userId
            )
            
            await MainActor.run {
                self.image = downloadedImage
                isLoading = false
            }
        } catch {
            print("⚠️ Failed to load profile picture: \(error.localizedDescription)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Helper Extension

extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}

// MARK: - Convenience Initializers

extension CachedImageView {
    /// Create view for stamp photos (rectangular with corner radius)
    static func stampPhoto(
        imageName: String?,
        storagePath: String?,
        stampId: String,
        size: CGSize,
        cornerRadius: CGFloat,
        useFullResolution: Bool = false,
        imageUrl: String? = nil
    ) -> CachedImageView {
        CachedImageView(
            imageType: .stampPhoto(imageName: imageName, storagePath: storagePath, stampId: stampId, imageUrl: imageUrl),
            shape: .rectangle(cornerRadius: cornerRadius),
            size: size,
            useFullResolution: useFullResolution
        )
    }
    
    /// Create view for profile pictures (circular)
    static func profilePicture(
        avatarUrl: String?,
        userId: String,
        size: CGFloat
    ) -> CachedImageView {
        CachedImageView(
            imageType: .profilePicture(avatarUrl: avatarUrl, userId: userId),
            shape: .circle,
            size: CGSize(width: size, height: size),
            useFullResolution: false
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        // Profile picture examples
        CachedImageView.profilePicture(
            avatarUrl: nil,
            userId: "preview",
            size: 100
        )
        
        CachedImageView.profilePicture(
            avatarUrl: nil,
            userId: "preview",
            size: 64
        )
        
        // Stamp photo example
        CachedImageView.stampPhoto(
            imageName: nil,
            storagePath: nil,
            stampId: "preview",
            size: CGSize(width: 160, height: 160),
            cornerRadius: 8
        )
    }
    .padding()
}

