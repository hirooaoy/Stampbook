import SwiftUI

/// Async image view that loads from local cache or downloads from Firebase Storage
/// Optimized for thumbnails with loading states
struct AsyncImageView: View {
    let imageName: String?
    let storagePath: String?
    let stampId: String
    let size: CGSize
    let cornerRadius: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = false
    // TODO: Add error state with retry button (Error Handling - Phase B)
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(cornerRadius)
            } else {
                // Placeholder while loading
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.gray)
                            } else {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                            }
                        }
                    )
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
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
            // TODO: Show error state with retry button (Error Handling - Phase B)
            await MainActor.run {
                isLoading = false
            }
        }
    }
}


