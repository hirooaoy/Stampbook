import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    
    let stampId: String
    let maxPhotos: Int
    
    // Optional: Show stamp image as first item (for Feed)
    let showStampImage: Bool
    let stampImageName: String?
    let onStampImageTap: (() -> Void)?
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedPhotoIndex: PhotoIndex?
    
    init(
        stampId: String,
        maxPhotos: Int = 5,
        showStampImage: Bool = false,
        stampImageName: String? = nil,
        onStampImageTap: (() -> Void)? = nil
    ) {
        self.stampId = stampId
        self.maxPhotos = maxPhotos
        self.showStampImage = showStampImage
        self.stampImageName = stampImageName
        self.onStampImageTap = onStampImageTap
    }
    
    // Wrapper to make Int Identifiable
    struct PhotoIndex: Identifiable {
        let id: Int
        var index: Int { id }
    }
    
    // Compute imageNames dynamically from stampsManager
    private var imageNames: [String] {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stampId })?
            .userImageNames ?? []
    }
    
    // Get uploading photos from stampsManager
    private var uploadingPhotos: Set<String> {
        stampsManager.userCollection.getUploadingPhotos(for: stampId)
    }
    
    var canAddMore: Bool {
        imageNames.count < maxPhotos
    }
    
    var body: some View {
        // If no photos and not in Feed view, show "Add Photos" button
        if imageNames.isEmpty && !showStampImage {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: maxPhotos,
                matching: .images
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 20, height: 20, alignment: .center)
                    Text("Add Photos")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await handlePhotoSelection(newItems)
                }
            }
            .fullScreenCover(item: $selectedPhotoIndex) { photoIndex in
                FullScreenPhotoView(
                    stampId: stampId,
                    imageNames: imageNames,
                    startIndex: photoIndex.index
                )
                .environmentObject(stampsManager)
            }
        } else {
            // Show horizontal scroll gallery
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Optional: Show stamp image first (for Feed)
                    if showStampImage, 
                       let stampImageName = stampImageName,
                       !stampImageName.isEmpty {
                        Button(action: {
                            onStampImageTap?()
                        }) {
                            Image(stampImageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipped()
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Display existing photos
                    ForEach(Array(imageNames.enumerated()), id: \.offset) { index, imageName in
                        Button(action: {
                            selectedPhotoIndex = PhotoIndex(id: index)
                        }) {
                            ZStack {
                                // Use AsyncThumbnailView to handle both local and Firebase loading
                                AsyncThumbnailView(
                                    imageName: imageName,
                                    storagePath: getStoragePath(for: imageName),
                                    stampId: stampId
                                )
                                .frame(width: 120, height: 120)
                                .cornerRadius(12)
                                
                                // Show loading spinner if this photo is uploading
                                if uploadingPhotos.contains(imageName) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 120, height: 120)
                                    
                                    ProgressView()
                                        .tint(.white)
                                }
                                // TODO: Add red warning badge for failed uploads (Error Handling - Phase A)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Show placeholder spinners for photos being processed (before thumbnails are ready)
                    ForEach(Array(uploadingPhotos.subtracting(Set(imageNames))), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                ProgressView()
                                    .tint(.gray)
                            )
                    }
                    
                    // Add photo button (if under limit)
                    if canAddMore {
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: maxPhotos - imageNames.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onChange(of: selectedItems) { _, newItems in
                            Task {
                                await handlePhotoSelection(newItems)
                            }
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedPhotoIndex) { photoIndex in
                FullScreenPhotoView(
                    stampId: stampId,
                    imageNames: imageNames,
                    startIndex: photoIndex.index
                )
                .environmentObject(stampsManager)
            }
        }
    }
    
    private func handlePhotoSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        // 1. IMMEDIATELY create placeholder filenames and show spinners
        let count = min(items.count, maxPhotos - imageNames.count)
        var placeholderFilenames: [String] = []
        for i in 0..<count {
            let placeholder = "uploading_\(stampId)_\(Date().timeIntervalSince1970)_\(i)"
            placeholderFilenames.append(placeholder)
            // Add to uploading state immediately for instant feedback
            stampsManager.userCollection.addUploadingPhoto(stampId: stampId, filename: placeholder)
        }
        
        // 2. Load images from PhotosPicker
        var loadedImages: [UIImage] = []
        for item in items {
            guard imageNames.count + loadedImages.count < maxPhotos else {
                break
            }
            
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    loadedImages.append(uiImage)
                }
            } catch {
                print("⚠️ Failed to load photo: \(error.localizedDescription)")
            }
        }
        
        // 3. Use shared upload workflow from ImageManager
        await ImageManager.shared.uploadPhotos(
            loadedImages,
            stampId: stampId,
            userId: authManager.userId
        ) { filenames in
            // Replace placeholders with real filenames atomically
            for placeholder in placeholderFilenames {
                stampsManager.userCollection.removeUploadingPhoto(stampId: stampId, filename: placeholder)
            }
            
            // All photos loaded and saved - add to UI at once
            for filename in filenames {
                stampsManager.userCollection.addUploadingPhoto(stampId: stampId, filename: filename)
                // Note: Storage path will be added later when upload completes
                stampsManager.userCollection.addImage(for: stampId, imageName: filename, storagePath: nil)
            }
        } onUploadComplete: { filename, storagePath in
            // Update the stamp with the Firebase storage path
            if let storagePath = storagePath {
                stampsManager.userCollection.updateImagePath(for: stampId, imageName: filename, storagePath: storagePath)
            }
            
            // Remove spinner
            stampsManager.userCollection.removeUploadingPhoto(stampId: stampId, filename: filename)
        }
        
        // Clear selection
        selectedItems.removeAll()
    }
    
    /// Get the storage path for a given image name
    private func getStoragePath(for imageName: String) -> String? {
        guard let collectedStamp = stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stampId }),
              let index = collectedStamp.userImageNames.firstIndex(of: imageName),
              index < collectedStamp.userImagePaths.count else {
            return nil
        }
        
        let path = collectedStamp.userImagePaths[index]
        return path.isEmpty ? nil : path
    }
}

// MARK: - Async Thumbnail View

/// Loads thumbnails with automatic fallback to Firebase Storage
/// 🔧 FIX: Uses memory cache and aggressively clears thumbnails when off-screen
struct AsyncThumbnailView: View {
    let imageName: String
    let storagePath: String?
    let stampId: String
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            if isLoading {
                // Show placeholder while loading
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(.gray)
                    )
            } else if let thumbnail = thumbnail {
                // Display the loaded thumbnail
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // Failed to load - show placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }
        }
        .task {
            loadTask = Task {
                await loadThumbnail()
            }
        }
        .onDisappear {
            // 🔧 FIX: Cancel loading task and clear thumbnail when off-screen
            // PhotoGalleryView scrolls horizontally, so off-screen thumbnails should be freed
            loadTask?.cancel()
            thumbnail = nil
            isLoading = true
        }
    }
    
    private func loadThumbnail() async {
        let loadStart = CFAbsoluteTimeGetCurrent()
        
        // 🔧 FIX: Check memory cache first (fast!)
        if let cachedThumbnail = ImageCacheManager.shared.getThumbnail(key: imageName) {
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            print("⏱️ [AsyncThumbnail] Memory cache hit: \(String(format: "%.3f", loadTime))s for \(imageName)")
            await MainActor.run {
                self.thumbnail = cachedThumbnail
                self.isLoading = false
            }
            return
        }
        
        // Step 1: Try loading thumbnail from local disk cache
        if let cachedThumbnail = ImageManager.shared.loadThumbnail(named: imageName) {
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            print("⏱️ [AsyncThumbnail] Disk cache hit: \(String(format: "%.3f", loadTime))s for \(imageName)")
            
            // Store in memory cache for faster access next time
            ImageCacheManager.shared.setThumbnail(cachedThumbnail, key: imageName)
            
            await MainActor.run {
                self.thumbnail = cachedThumbnail
                self.isLoading = false
            }
            return
        }
        
        // Step 2: If not cached and we have a storage path, download from Firebase
        if let storagePath = storagePath, !storagePath.isEmpty {
            do {
                print("⬇️ [AsyncThumbnail] Downloading from Firebase: \(imageName)")
                let downloadedThumbnail = try await ImageManager.shared.downloadAndCacheThumbnail(
                    storagePath: storagePath,
                    stampId: stampId
                )
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
                print("⏱️ [AsyncThumbnail] Firebase download: \(String(format: "%.3f", loadTime))s for \(imageName)")
                
                // Store in memory cache
                ImageCacheManager.shared.setThumbnail(downloadedThumbnail, key: imageName)
                
                await MainActor.run {
                    self.thumbnail = downloadedThumbnail
                    self.isLoading = false
                }
                return
            } catch {
                print("⚠️ Failed to download thumbnail from Firebase: \(error.localizedDescription)")
            }
        }
        
        // Step 3: Failed to load
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("⏱️ [AsyncThumbnail] Load failed: \(String(format: "%.3f", loadTime))s for \(imageName)")
        await MainActor.run {
            self.thumbnail = nil
            self.isLoading = false
        }
    }
}

