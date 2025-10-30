import SwiftUI
import PhotosUI

struct PhotoGalleryView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    
    let stampId: String
    let imageNames: [String]
    let maxPhotos: Int
    
    // Optional: Show stamp image as first item (for Feed)
    let showStampImage: Bool
    let stampImageName: String?
    let onStampImageTap: (() -> Void)?
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var uploadingPhotos: Set<String> = [] // Track which photos are uploading
    @State private var selectedPhotoIndex: PhotoIndex?
    
    init(
        stampId: String,
        imageNames: [String],
        maxPhotos: Int = 5,
        showStampImage: Bool = false,
        stampImageName: String? = nil,
        onStampImageTap: (() -> Void)? = nil
    ) {
        self.stampId = stampId
        self.imageNames = imageNames
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
    
    var canAddMore: Bool {
        imageNames.count < maxPhotos
    }
    
    var body: some View {
        let _ = print("🔍 PhotoGalleryView body - imageNames.count: \(imageNames.count), uploadingPhotos.count: \(uploadingPhotos.count), canAddMore: \(canAddMore)")
        let _ = print("🔍 imageNames: \(imageNames)")
        let _ = print("🔍 uploadingPhotos: \(uploadingPhotos)")
        
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
                    if showStampImage, let stampImageName = stampImageName {
                        Button(action: {
                            onStampImageTap?()
                        }) {
                            Image(stampImageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipped()
                                .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Display existing photos
                    ForEach(Array(imageNames.enumerated()), id: \.offset) { index, imageName in
                        Button(action: {
                            print("🖼️ Photo tapped - Index: \(index), Filename: \(imageName)")
                            print("🖼️ Stamp ID: \(stampId)")
                            print("🖼️ Total images in gallery: \(imageNames.count)")
                            selectedPhotoIndex = PhotoIndex(id: index)
                        }) {
                            ZStack {
                                // Use thumbnail for better performance
                                if let image = ImageManager.shared.loadThumbnail(named: imageName) {
                                    let _ = print("🔍 [\(index)] Loaded thumbnail for: \(imageName)")
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(12)
                                } else {
                                    let _ = print("🔍 [\(index)] NO thumbnail for: \(imageName)")
                                    // Placeholder if image fails to load
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                        )
                                }
                                
                                // Show loading spinner if this photo is uploading
                                if uploadingPhotos.contains(imageName) {
                                    let _ = print("🔍 [\(index)] Showing spinner for: \(imageName)")
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                    
                                    ProgressView()
                                        .tint(.white)
                                }
                                // TODO: Add red warning badge for failed uploads (Error Handling - Phase A)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Add photo button (if under limit)
                    if canAddMore {
                        let _ = print("🔍 Showing + button")
                        PhotosPicker(
                            selection: $selectedItems,
                            maxSelectionCount: maxPhotos - imageNames.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Image(systemName: "plus")
                                        .font(.system(size: 24))
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
        
        // Load images from PhotosPicker
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
        
        // Use shared upload workflow from ImageManager
        await ImageManager.shared.uploadPhotos(
            loadedImages,
            stampId: stampId,
            userId: authManager.userId
        ) { filenames in
            print("🔍 [PhotoGallery] onPhotosAdded callback - adding \(filenames.count) photos")
            // All photos loaded and saved - add to UI at once
            for filename in filenames {
                print("🔍 [PhotoGallery] Adding to uploadingPhotos: \(filename)")
                uploadingPhotos.insert(filename)
                print("🔍 [PhotoGallery] Adding to stampsManager: \(filename)")
                stampsManager.userCollection.addImage(for: stampId, imageName: filename)
            }
            print("🔍 [PhotoGallery] uploadingPhotos now has \(uploadingPhotos.count) items: \(uploadingPhotos)")
        } onUploadComplete: { filename in
            print("🔍 [PhotoGallery] onUploadComplete callback - removing spinner for: \(filename)")
            // Each photo uploaded - remove spinner
            uploadingPhotos.remove(filename)
            print("🔍 [PhotoGallery] uploadingPhotos now has \(uploadingPhotos.count) items: \(uploadingPhotos)")
        }
        
        // Clear selection
        selectedItems.removeAll()
    }
}

