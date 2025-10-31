import SwiftUI

struct FullScreenPhotoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var stampsManager: StampsManager
    
    let stampId: String
    let startIndex: Int
    
    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var isDeleting = false
    
    // Computed property to get live image names from stampsManager
    private var imageNames: [String] {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stampId })?
            .userImageNames ?? []
    }
    
    init(stampId: String, imageNames: [String], startIndex: Int = 0) {
        self.stampId = stampId
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            if imageNames.isEmpty {
                // No images - show error
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No images to display")
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                // 🔧 FIX: Use lazy loading TabView - only loads images as you swipe to them
                TabView(selection: $currentIndex) {
                    ForEach(Array(imageNames.enumerated()), id: \.offset) { index, imageName in
                        LazyPhotoView(
                            imageName: imageName,
                            storagePath: getStoragePath(for: imageName),
                            stampId: stampId
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .id(imageNames) // Force TabView to refresh when imageNames array changes
            }
            
            // Top buttons overlay
            VStack {
                HStack {
                    // X button (always visible)
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Menu button
                    if !imageNames.isEmpty {
                        Menu {
                            Button(role: .destructive, action: {
                                showDeleteConfirmation = true
                            }) {
                                Label("Delete Photo", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .disabled(isDeleting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // Photo counter at bottom
                if imageNames.count > 1 {
                    Text("\(currentIndex + 1) of \(imageNames.count)")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        .padding(.bottom, 32)
                }
                
                // Deleting indicator
                if isDeleting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Deleting photo...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(16)
                }
            }
        }
        .alert("Delete Photo", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCurrentPhoto()
                }
            }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
        .alert("Deletion Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }
    
    private func deleteCurrentPhoto() async {
        guard currentIndex < imageNames.count else { return }
        
        let imageName = imageNames[currentIndex]
        let photoCountBeforeDeletion = imageNames.count
        
        print("🗑️ Deleting photo: \(imageName)")
        print("🗑️ Current index: \(currentIndex), Total photos: \(photoCountBeforeDeletion)")
        
        // If this is the last photo, dismiss immediately (no flash)
        if photoCountBeforeDeletion == 1 {
            print("🗑️ Last photo - dismissing immediately")
            await MainActor.run {
                dismiss()
            }
            
            // Delete in background after dismissal
            Task {
                do {
                    try await stampsManager.userCollection.removeImage(for: stampId, imageName: imageName)
                    print("✅ Photo deleted successfully from Firebase and local storage")
                } catch {
                    print("❌ Failed to delete photo: \(error.localizedDescription)")
                    // Note: User won't see error since view is dismissed, but deletion will be reflected in gallery
                }
            }
            return
        }
        
        // Multiple photos: Move to next photo FIRST, then delete (prevents flash)
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.25)) {
                // If we're deleting the last photo in the array, move back one
                if currentIndex >= photoCountBeforeDeletion - 1 {
                    currentIndex = max(0, photoCountBeforeDeletion - 2)
                    print("🗑️ Moving to index: \(currentIndex)")
                }
                // Otherwise stay at same index (next photo will shift into this position)
            }
        }
        
        // Small delay to let the transition start
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
        
        // Show loading state
        await MainActor.run {
            isDeleting = true
        }
        
        // Delete the image from data source (now async with proper error handling)
        do {
            try await stampsManager.userCollection.removeImage(for: stampId, imageName: imageName)
            print("✅ Photo deleted successfully from Firebase and local storage")
            
            // Hide loading state
            await MainActor.run {
                isDeleting = false
            }
            
            print("🗑️ After deletion - Total photos: \(imageNames.count)")
            
        } catch {
            // Deletion failed - show error to user
            print("❌ Failed to delete photo: \(error.localizedDescription)")
            
            await MainActor.run {
                isDeleting = false
                deleteErrorMessage = "Failed to delete photo from cloud storage. Please check your internet connection and try again.\n\nError: \(error.localizedDescription)"
                showDeleteError = true
            }
        }
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

// MARK: - Lazy Photo View

/// Loads a single photo on-demand when it appears in the TabView
/// This prevents loading all photos at once (memory optimization)
/// 🔧 FIX: Aggressively unloads images when off-screen to prevent memory leaks
struct LazyPhotoView: View {
    let imageName: String
    let storagePath: String?
    let stampId: String
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            if isLoading {
                // Show loading spinner while image loads
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            } else if let image = image {
                // Display the loaded image
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Failed to load - show error
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Failed to load image")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.subheadline)
                }
            }
        }
        .task {
            // Load image when this view appears
            loadTask = Task {
                await loadImage()
            }
        }
        .onDisappear {
            // 🔧 FIX: Cancel loading task and clear image when view disappears
            // This aggressively frees memory for off-screen images
            loadTask?.cancel()
            image = nil
            isLoading = true
        }
    }
    
    private func loadImage() async {
        // 🔧 FIX: Check memory cache first (fast!)
        if let cachedImage = ImageCacheManager.shared.getFullImage(key: imageName) {
            await MainActor.run {
                self.image = cachedImage
                self.isLoading = false
            }
            return
        }
        
        // Step 1: Try loading from local disk cache
        let documentsURL = ImageManager.shared.getDocumentsDirectory()
        let fileURL = documentsURL.appendingPathComponent(imageName)
        
        let localImage = await Task.detached(priority: .userInitiated) { @Sendable () -> UIImage? in
            guard let imageData = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: imageData) else {
                return nil
            }
            return image
        }.value
        
        if let localImage = localImage {
            // Found in local disk cache - store in memory cache
            ImageCacheManager.shared.setFullImage(localImage, key: imageName)
            
            await MainActor.run {
                self.image = localImage
                self.isLoading = false
            }
            return
        }
        
        // Step 2: If not in cache and we have a storage path, download from Firebase
        if let storagePath = storagePath, !storagePath.isEmpty {
            do {
                print("⬇️ Image not cached, downloading from Firebase: \(imageName)")
                let downloadedImage = try await ImageManager.shared.downloadAndCacheImage(
                    storagePath: storagePath,
                    stampId: stampId
                )
                
                // Store in memory cache
                ImageCacheManager.shared.setFullImage(downloadedImage, key: imageName)
                
                await MainActor.run {
                    self.image = downloadedImage
                    self.isLoading = false
                }
                return
            } catch {
                print("⚠️ Failed to download image from Firebase: \(error.localizedDescription)")
            }
        }
        
        // Step 3: Failed to load from both local and Firebase
        await MainActor.run {
            self.image = nil
            self.isLoading = false
        }
    }
}

