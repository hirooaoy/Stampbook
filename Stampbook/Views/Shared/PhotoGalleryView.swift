import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var imageManager = ImageManager.shared
    
    let stampId: String
    let maxPhotos: Int
    
    // Optional: Show stamp image as first item (for Feed)
    let showStampImage: Bool
    let stampImageName: String?
    let onStampImageTap: (() -> Void)?
    
    // Optional: For viewing other users' posts (Feed)
    // When provided, use these instead of fetching from stampsManager
    let userId: String?
    let userPhotos: [String]?
    let userPhotoPaths: [String]?
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedPhotoIndex: PhotoIndex?
    
    init(
        stampId: String,
        maxPhotos: Int = 5,
        showStampImage: Bool = false,
        stampImageName: String? = nil,
        onStampImageTap: (() -> Void)? = nil,
        userId: String? = nil,
        userPhotos: [String]? = nil,
        userPhotoPaths: [String]? = nil
    ) {
        self.stampId = stampId
        self.maxPhotos = maxPhotos
        self.showStampImage = showStampImage
        self.stampImageName = stampImageName
        self.onStampImageTap = onStampImageTap
        self.userId = userId
        self.userPhotos = userPhotos
        self.userPhotoPaths = userPhotoPaths
    }
    
    // Wrapper to make Int Identifiable
    struct PhotoIndex: Identifiable {
        let id: Int
        var index: Int { id }
    }
    
    // Compute imageNames dynamically
    // If viewing another user's post (userPhotos provided), use those
    // Otherwise fetch from current user's collection (stampsManager)
    private var imageNames: [String] {
        if let userPhotos = userPhotos {
            // Viewing another user's post - use provided photos
            return userPhotos
        } else {
            // Viewing own collection - fetch from stampsManager
            return stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == stampId })?
                .userImageNames ?? []
        }
    }
    
    // Get uploading photos from stampsManager (only for current user)
    private var uploadingPhotos: Set<String> {
        // Only show uploading state for current user's stamps
        if userPhotos != nil {
            return [] // Viewing someone else's post - no uploading state
        }
        return stampsManager.userCollection.getUploadingPhotos(for: stampId)
    }
    
    // Check if current user can add more photos
    // Only allow adding for current user's own stamps
    var canAddMore: Bool {
        userPhotos == nil && imageNames.count < maxPhotos
    }
    
    // Check if this is viewing another user's post (read-only mode)
    private var isViewingOtherUser: Bool {
        userPhotos != nil
    }
    
    var body: some View {
        // If no photos and not in Feed view, show "Add Photos" button
        if imageNames.isEmpty && !showStampImage {
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: maxPhotos,
                matching: .images
            ) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "photo")
                        .font(.body)
                        .foregroundColor(.primary)
                        .frame(width: 18, height: 18, alignment: .center)
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
            .sheet(item: $selectedPhotoIndex) { photoIndex in
                FullScreenPhotoView(
                    stampId: stampId,
                    imageNames: imageNames,
                    startIndex: photoIndex.index,
                    userId: userId,
                    userPhotos: userPhotos,
                    userPhotoPaths: userPhotoPaths
                )
                .environmentObject(stampsManager)
                .presentationBackground(.black)
                .presentationDragIndicator(.hidden)
                .edgesIgnoringSafeArea(.all)
            }
            .overlay(alignment: .top) {
                // Toast for photo upload errors
                if let errorMessage = imageManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
            }
        } else {
            // Show horizontal scroll gallery
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Optional: Show stamp image first (for Feed)
                if showStampImage {
                        Button(action: {
                            onStampImageTap?()
                        }) {
                        // Check if we have an actual stamp image URL
                        if let stampImageName = stampImageName, !stampImageName.isEmpty {
                            // We have a real stamp image - load optimized thumbnail
                            if stampImageName.starts(with: "http") {
                                // Extract storage path from Firebase URL and use cached thumbnail
                                let storagePath = extractStoragePath(from: stampImageName)
                                
                                CachedImageView.stampPhoto(
                                    imageName: nil, // Don't have imageName in feed, will fetch from Firebase
                                    storagePath: storagePath,
                                    stampId: stampId,
                                    size: CGSize(width: 106, height: 106),
                                    cornerRadius: 0,  // No rounded corners for stamps (prevents clipping edges)
                                    imageUrl: stampImageName
                                )
                            } else {
                                // Load from local assets (backward compatibility)
                                Image(stampImageName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 106, height: 106)
                            }
                        } else {
                            // No stamp image available - show "empty" placeholder (same as StampsView)
                            Image("empty")
                                .resizable()
                                .renderingMode(.original)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 106, height: 106)
                        }
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
                                .frame(width: 106, height: 106)
                                .cornerRadius(12)
                                .id(imageName) // 🔧 FIX: Force view recreation when imageName changes
                                
                                // Show loading spinner if this photo is uploading
                                if uploadingPhotos.contains(imageName) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 106, height: 106)
                                    
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
                            .frame(width: 106, height: 106)
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
                                .frame(width: 106, height: 106)
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
            .sheet(item: $selectedPhotoIndex) { photoIndex in
                FullScreenPhotoView(
                    stampId: stampId,
                    imageNames: imageNames,
                    startIndex: photoIndex.index,
                    userId: userId,
                    userPhotos: userPhotos,
                    userPhotoPaths: userPhotoPaths
                )
                .environmentObject(stampsManager)
                .presentationBackground(.black)
                .presentationDragIndicator(.hidden)
                .edgesIgnoringSafeArea(.all)
            }
            .overlay(alignment: .top) {
                // Toast for photo upload errors
                if let errorMessage = imageManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        
        // 🔄 PHOTO UPLOAD WORKFLOW (Optimized Nov 3, 2025)
        // This 3-step process provides instant UI feedback while uploading efficiently:
        // 1. Show spinners immediately (instant UX)
        // 2. Save locally & compress (~150ms/photo)
        // 3. Upload to Firebase in parallel (4x faster than sequential)
        // Result: 4 photos = 3 seconds instead of 12 seconds + 50% lower Firestore costs
        
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
        // ⚡ OPTIMIZED WORKFLOW (Nov 3, 2025):
        // - Photos upload in parallel (4x faster)
        // - Single Firestore write per photo (50% cost reduction)
        // - Spinners show immediately, then clear when upload completes
        await ImageManager.shared.uploadPhotos(
            loadedImages,
            stampId: stampId,
            userId: authManager.userId
        ) { filenames in
            // CALLBACK #1: Photos saved locally (fast, ~150ms per photo)
            // Replace placeholders with real filenames atomically
            for placeholder in placeholderFilenames {
                stampsManager.userCollection.removeUploadingPhoto(stampId: stampId, filename: placeholder)
            }
            
            // Add filenames to uploading state to show spinners
            // 💰 OPTIMIZATION: DON'T add to collection yet to avoid double Firestore write
            // OLD WAY: addImage() here (write #1) + updateImagePath() later (write #2) = 2 writes
            // NEW WAY: Only addImage() once when upload completes = 1 write
            for filename in filenames {
                stampsManager.userCollection.addUploadingPhoto(stampId: stampId, filename: filename)
            }
        } onUploadComplete: { filename, storagePath in
            // CALLBACK #2: Firebase upload complete (called per photo as they finish)
            // ✅ SINGLE FIRESTORE WRITE: Add image with complete data in one operation
            // This saves 50% Firestore costs by eliminating the second write
            if let storagePath = storagePath {
                // Add image to collection with complete data - single Firestore write
                stampsManager.userCollection.addImage(for: stampId, imageName: filename, storagePath: storagePath)
            } else {
                // Upload failed but image is saved locally - add without storage path
                stampsManager.userCollection.addImage(for: stampId, imageName: filename, storagePath: nil)
            }
            
            // Remove spinner to show photo is ready
            stampsManager.userCollection.removeUploadingPhoto(stampId: stampId, filename: filename)
        }
        
        // Clear selection
        selectedItems.removeAll()
    }
    
    /// Get the storage path for a given image name
    private func getStoragePath(for imageName: String) -> String? {
        // If viewing another user's post, use provided paths
        if let userPhotos = userPhotos,
           let userPhotoPaths = userPhotoPaths,
           let index = userPhotos.firstIndex(of: imageName),
           index < userPhotoPaths.count {
            let path = userPhotoPaths[index]
            return path.isEmpty ? nil : path
        }
        
        // Otherwise, fetch from current user's collection
        guard let collectedStamp = stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stampId }),
              let index = collectedStamp.userImageNames.firstIndex(of: imageName),
              index < collectedStamp.userImagePaths.count else {
            return nil
        }
        
        let path = collectedStamp.userImagePaths[index]
        return path.isEmpty ? nil : path
    }
    
    /// Extract storage path from Firebase Storage URL
    /// Converts: https://firebasestorage.googleapis.com/v0/b/bucket/o/stamps%2Ffile.jpg?alt=media
    /// To: stamps/file.jpg
    private func extractStoragePath(from firebaseUrl: String) -> String? {
        guard let url = URL(string: firebaseUrl),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.path.components(separatedBy: "/o/").last?.components(separatedBy: "?").first else {
            return nil
        }
        
        // URL decode the path (e.g., %2F -> /)
        return path.removingPercentEncoding
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
        #if DEBUG
        let loadStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // 🔧 FIX: Use thumbnail filename as key (consistent with ImageManager)
        let thumbnailKey = imageName.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
        
        // 🔧 FIX: Check memory cache first (fast!)
        if let cachedThumbnail = ImageCacheManager.shared.getThumbnail(key: thumbnailKey) {
            #if DEBUG
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            print("⏱️ [AsyncThumbnail] Memory cache hit: \(String(format: "%.3f", loadTime))s for \(imageName)")
            #endif
            
            await MainActor.run {
                self.thumbnail = cachedThumbnail
                self.isLoading = false
            }
            return
        }
        
        // Step 1: Try loading thumbnail from local disk cache
        if let cachedThumbnail = ImageManager.shared.loadThumbnail(named: imageName) {
            #if DEBUG
            let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
            print("⏱️ [AsyncThumbnail] Disk cache hit: \(String(format: "%.3f", loadTime))s for \(imageName)")
            #endif
            
            // Store in memory cache for faster access next time (use thumbnail key)
            ImageCacheManager.shared.setThumbnail(cachedThumbnail, key: thumbnailKey)
            
            await MainActor.run {
                self.thumbnail = cachedThumbnail
                self.isLoading = false
            }
            return
        }
        
        // Step 2: If not cached and we have a storage path, download from Firebase
        if let storagePath = storagePath, !storagePath.isEmpty {
            do {
                #if DEBUG
                print("⬇️ [AsyncThumbnail] Downloading from Firebase: \(imageName)")
                #endif
                
                let downloadedThumbnail = try await ImageManager.shared.downloadAndCacheThumbnail(
                    storagePath: storagePath,
                    stampId: stampId
                )
                
                #if DEBUG
                let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
                print("⏱️ [AsyncThumbnail] Firebase download: \(String(format: "%.3f", loadTime))s for \(imageName)")
                #endif
                
                // Store in memory cache (use thumbnail key for consistency)
                let thumbnailKey = imageName.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                ImageCacheManager.shared.setThumbnail(downloadedThumbnail, key: thumbnailKey)
                
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
        #if DEBUG
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        print("⏱️ [AsyncThumbnail] Load failed: \(String(format: "%.3f", loadTime))s for \(imageName)")
        #endif
        
        await MainActor.run {
            self.thumbnail = nil
            self.isLoading = false
        }
    }
}

