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
    
    // Simple init - no complex pre-loading
    init(imageType: ImageType, shape: Shape, size: CGSize, useFullResolution: Bool = false) {
        self.imageType = imageType
        self.shape = shape
        self.size = size
        self.useFullResolution = useFullResolution
    }
    
    var body: some View {
        ZStack {
            if let image = image {
                renderImage(image)
            } else {
                // Show placeholder with flexible height for detail view stamps
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
        // Use .fit for stamps (shows full image within frame), .fill for profile pictures (fills circle)
        let contentMode: ContentMode = {
            switch imageType {
            case .stampPhoto:
                return .fit  // Shows entire stamp, smaller if needed, no cropping
            case .profilePicture:
                return .fill  // Fills entire circle, may crop
            }
        }()
        
        let imageView = Image(uiImage: uiImage)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: contentMode)
        
        // Simple frame logic:
        // - Detail view stamps: flexible height based on actual image aspect ratio
        // - Grid/feed stamps and profile pics: fixed frame
        let framedImageView: some View = {
            if case .stampPhoto = imageType, useFullResolution {
                // Detail view: Let image determine its own height (allows tall stamps to be tall)
                return AnyView(imageView.frame(width: size.width))
            } else {
                // Grid/feed view or profile: fixed frame
                return AnyView(imageView.frame(width: size.width, height: contentMode == .fill ? size.height : nil))
            }
        }()
        
        // Only clip for profile pictures (.fill needs clipping), not for stamps (.fit doesn't)
        let clippedIfNeeded: some View = {
            switch imageType {
            case .stampPhoto:
                return AnyView(framedImageView)  // No clipping for stamps
            case .profilePicture:
                return AnyView(framedImageView.clipped())  // Clip for profile pictures
            }
        }()
        
        switch shape {
        case .rectangle(let cornerRadius):
            clippedIfNeeded.cornerRadius(cornerRadius)
        case .circle:
            clippedIfNeeded.clipShape(Circle())
        }
    }
    
    @ViewBuilder
    private func renderPlaceholder() -> some View {
        switch shape {
        case .rectangle(let cornerRadius):
            // Simple square placeholder (will shift slightly when image loads if not square)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(isLoading ? Color.clear : Color.gray.opacity(0.1))
                .frame(width: size.width, height: size.width)  // Square estimate
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
        // For detail view with full resolution, skip thumbnail entirely to avoid aspect ratio jump
        if useFullResolution, let storagePath = storagePath {
            await loadFullResolution(storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
            return
        }
        
        // For grid/feed view, try loading thumbnail from local cache first (instant if exists)
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
        
        // Download thumbnail
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

