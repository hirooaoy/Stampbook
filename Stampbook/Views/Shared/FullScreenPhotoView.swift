import SwiftUI

struct FullScreenPhotoView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var stampsManager: StampsManager
    
    let stampId: String
    let startIndex: Int
    
    @State private var currentIndex: Int
    @State private var showDeleteConfirmation = false
    @State private var loadedImages: [UIImage] = []
    @State private var isLoading = true
    
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
            
            if isLoading {
                // Show loading indicator while images load
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            } else if loadedImages.isEmpty {
                // No images loaded - show error
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.5))
                    Text("Failed to load images")
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                // Photo viewer - simple TabView
                TabView(selection: $currentIndex) {
                    ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            
            // Top buttons overlay (always show, even while loading)
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
                    
                    // Menu button (only show when images are loaded)
                    if !isLoading && !loadedImages.isEmpty {
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
                
                // Photo counter at bottom
                if !isLoading && loadedImages.count > 1 {
                    Text("\(currentIndex + 1) of \(loadedImages.count)")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        .padding(.bottom, 32)
                }
            }
        }
        .task {
            // 🔍 DEBUG: Print what we're trying to load
            print("\n🔍 ========== FullScreenPhotoView LOADING ==========")
            print("🔍 Stamp ID: \(stampId)")
            print("🔍 Loading \(imageNames.count) images")
            print("🔍 Image names: \(imageNames)")
            print("🔍 Start index: \(startIndex)")
            
            // Check documents directory
            let documentsURL = ImageManager.shared.getDocumentsDirectory()
            print("🔍 Documents directory: \(documentsURL.path)")
            
            // List all files in documents directory
            if let files = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path) {
                print("🔍 Files in documents directory (\(files.count) total):")
                for file in files.prefix(10) {
                    print("   - \(file)")
                }
                if files.count > 10 {
                    print("   ... and \(files.count - 10) more files")
                }
            }
            
            // Validate inputs
            guard !imageNames.isEmpty else {
                print("❌ ERROR: imageNames array is EMPTY!")
                self.isLoading = false
                return
            }
            
            // Load images asynchronously on background thread
            let imageNamesCopy = imageNames // Capture immutable copy
            let documentsURLCopy = documentsURL // Capture documents URL
            let images = await Task.detached(priority: .userInitiated) { @Sendable () -> [UIImage] in
                var loadedImages: [UIImage] = []
                
                for (index, imageName) in imageNamesCopy.enumerated() {
                    print("🔍 Loading image \(index + 1)/\(imageNamesCopy.count): \(imageName)")
                    
                    // Check if file exists
                    let fileURL = documentsURLCopy.appendingPathComponent(imageName)
                    let exists = FileManager.default.fileExists(atPath: fileURL.path)
                    print("🔍 File exists: \(exists) at path: \(fileURL.path)")
                    
                    // Load image directly from file
                    if let imageData = try? Data(contentsOf: fileURL),
                       let image = UIImage(data: imageData) {
                        print("✅ Successfully loaded image: \(imageName) - size: \(image.size)")
                        loadedImages.append(image)
                    } else {
                        print("❌ Failed to load image: \(imageName)")
                        if !exists {
                            print("   Reason: File does not exist")
                        } else if let _ = try? Data(contentsOf: fileURL) {
                            print("   Reason: Data loaded but UIImage creation failed")
                        } else {
                            print("   Reason: Failed to load data from file")
                        }
                    }
                }
                
                print("🔍 Final result: Loaded \(loadedImages.count) out of \(imageNamesCopy.count) images")
                return loadedImages
            }.value
            
            // Update UI on main thread
            print("🔍 Updating UI with \(images.count) images")
            self.loadedImages = images
            self.isLoading = false
            print("🔍 ========== FullScreenPhotoView COMPLETE ==========\n")
        }
        .alert("Delete Photo", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentPhoto()
            }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
    }
    
    private func deleteCurrentPhoto() {
        guard currentIndex < imageNames.count else { return }
        guard currentIndex < loadedImages.count else { return }
        
        let imageName = imageNames[currentIndex]
        let photoCountBeforeDeletion = imageNames.count
        
        print("🗑️ Deleting photo: \(imageName)")
        print("🗑️ Current index: \(currentIndex), Total photos: \(photoCountBeforeDeletion)")
        
        // Delete the image from data source
        stampsManager.userCollection.removeImage(for: stampId, imageName: imageName)
        
        // If this was the last photo, dismiss the view
        if photoCountBeforeDeletion == 1 {
            print("🗑️ No photos left, dismissing view")
            dismiss()
            return
        }
        
        // Remove the image from loaded images array with fade animation
        withAnimation(.easeOut(duration: 0.25)) {
            loadedImages.remove(at: currentIndex)
            
            // Adjust current index if we deleted the last photo
            if currentIndex >= loadedImages.count {
                currentIndex = max(0, loadedImages.count - 1)
                print("🗑️ Adjusted index to: \(currentIndex) with fade")
            } else {
                print("🗑️ Staying at index: \(currentIndex) with fade")
            }
        }
        
        print("🗑️ After deletion - Total photos: \(loadedImages.count)")
    }
    
    private func reloadImages() async {
        let imageNamesCopy = imageNames
        let documentsURL = ImageManager.shared.getDocumentsDirectory()
        
        print("🔄 Reloading \(imageNamesCopy.count) images...")
        
        let images = await Task.detached(priority: .userInitiated) { @Sendable () -> [UIImage] in
            var loadedImages: [UIImage] = []
            
            for imageName in imageNamesCopy {
                let fileURL = documentsURL.appendingPathComponent(imageName)
                
                if let imageData = try? Data(contentsOf: fileURL),
                   let image = UIImage(data: imageData) {
                    loadedImages.append(image)
                }
            }
            
            return loadedImages
        }.value
        
        loadedImages = images
        print("🔄 Reloaded \(images.count) images")
    }
}

