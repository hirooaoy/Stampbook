import SwiftUI

/// Generic cached image view that handles both profile pictures and stamp photos
/// Consolidates duplicate logic from AsyncImageView and ProfileImageView
struct CachedImageView: View {
    enum ImageType {
        case stampPhoto(imageName: String?, storagePath: String?, stampId: String)
        case profilePicture(avatarUrl: String?, userId: String)
    }
    
    enum Shape: Equatable {
        case rectangle(cornerRadius: CGFloat)
        case circle
    }
    
    let imageType: ImageType
    let shape: Shape
    let size: CGSize
    
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
                .fill(Color.gray.opacity(0.3))
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
        case .stampPhoto(let imageName, let storagePath, let stampId):
            await loadStampPhoto(imageName: imageName, storagePath: storagePath, stampId: stampId)
        case .profilePicture(let avatarUrl, let userId):
            await loadProfilePicture(avatarUrl: avatarUrl, userId: userId)
        }
    }
    
    private func loadStampPhoto(imageName: String?, storagePath: String?, stampId: String) async {
        // Try loading from local cache first (instant if exists)
        if let imageName = imageName,
           let cachedImage = ImageManager.shared.loadThumbnail(named: imageName) {
            await MainActor.run {
                self.image = cachedImage
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
        
        do {
            let downloadedImage = try await ImageManager.shared.downloadAndCacheThumbnail(
                storagePath: storagePath,
                stampId: stampId
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
        cornerRadius: CGFloat
    ) -> CachedImageView {
        CachedImageView(
            imageType: .stampPhoto(imageName: imageName, storagePath: storagePath, stampId: stampId),
            shape: .rectangle(cornerRadius: cornerRadius),
            size: size
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
            size: CGSize(width: size, height: size)
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

