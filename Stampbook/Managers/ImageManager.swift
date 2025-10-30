import Foundation
import UIKit
import FirebaseStorage

class ImageManager {
    static let shared = ImageManager()
    
    private let storage = Storage.storage()
    
    private init() {}
    
    // MARK: - Local Storage
    
    /// Save image to local documents directory
    /// Automatically resizes to max 2400px and generates thumbnail
    /// Returns filename if successful
    func saveImage(_ image: UIImage, stampId: String) -> String? {
        // Resize to max 2400px for efficient storage and viewing
        let maxDimension: CGFloat = 2400
        let resizedImage: UIImage
        
        if image.size.width > maxDimension || image.size.height > maxDimension {
            resizedImage = resizeImageToFit(image, maxDimension: maxDimension) ?? image
            print("📐 Resized image from \(image.size) to \(resizedImage.size)")
        } else {
            resizedImage = image
            print("📐 Image already under 2400px: \(image.size)")
        }
        
        // Compress image
        guard let imageData = compressImage(resizedImage, maxSizeMB: 2.0) else {
            print("⚠️ Failed to compress image")
            return nil
        }
        
        // Generate unique filename
        let timestamp = Date().timeIntervalSince1970
        let uuid = UUID().uuidString.prefix(8)
        let filename = "\(stampId)_\(Int(timestamp))_\(uuid).jpg"
        
        // Save to documents directory
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            print("✅ Image saved locally: \(filename)")
            
            // Generate and save thumbnail (160x160 @2x for retina)
            if let thumbnail = generateThumbnail(resizedImage, size: CGSize(width: 160, height: 160)) {
                let thumbnailFilename = "\(stampId)_\(Int(timestamp))_\(uuid)_thumb.jpg"
                let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                
                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbnailData.write(to: thumbnailURL)
                    print("✅ Thumbnail saved: \(thumbnailFilename)")
                }
            }
            
            return filename
        } catch {
            print("⚠️ Failed to save image: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load full-resolution image from local documents directory
    func loadImage(named filename: String) -> UIImage? {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            return image
        }
        
        return nil
    }
    
    /// Load thumbnail image from local documents directory
    /// Falls back to full-res if thumbnail doesn't exist
    func loadThumbnail(named filename: String) -> UIImage? {
        // Try loading thumbnail first
        let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
        let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
        
        if let thumbnailData = try? Data(contentsOf: thumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            return thumbnail
        }
        
        // Fallback to full-res (for old images without thumbnails)
        return loadImage(named: filename)
    }
    
    /// Delete image from local documents directory
    /// Also deletes the associated thumbnail
    func deleteImage(named filename: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("✅ Image deleted locally: \(filename)")
            
            // Also delete thumbnail if it exists
            let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
            let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
            
            if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                try FileManager.default.removeItem(at: thumbnailURL)
                print("✅ Thumbnail deleted: \(thumbnailFilename)")
            }
        } catch {
            print("⚠️ Failed to delete image: \(error.localizedDescription)")
        }
    }
    
    /// Get app's documents directory
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Firebase Storage
    
    /// Upload image to Firebase Storage
    /// Automatically resizes to max 2400px before upload
    /// Returns the storage path (not download URL for efficiency)
    func uploadImage(_ image: UIImage, stampId: String, userId: String, filename: String) async throws -> String {
        // Resize to max 2400px for efficient upload
        let maxDimension: CGFloat = 2400
        let resizedImage: UIImage
        
        if image.size.width > maxDimension || image.size.height > maxDimension {
            resizedImage = resizeImageToFit(image, maxDimension: maxDimension) ?? image
            print("📐 Resizing for upload from \(image.size) to \(resizedImage.size)")
        } else {
            resizedImage = image
        }
        
        // Compress image
        guard let imageData = compressImage(resizedImage, maxSizeMB: 2.0) else {
            throw ImageError.compressionFailed
        }
        
        // Storage path: users/{userId}/stamps/{stampId}/{filename}
        let storagePath = "users/\(userId)/stamps/\(stampId)/\(filename)"
        let storageRef = storage.reference().child(storagePath)
        
        // Upload with metadata
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        
        print("✅ Image uploaded to Firebase: \(storagePath)")
        return storagePath
    }
    
    /// Download image from Firebase Storage and cache locally
    /// Returns cached image if already exists
    func downloadAndCacheImage(storagePath: String, stampId: String) async throws -> UIImage {
        // Extract filename from path (e.g., "users/123/stamps/abc/photo.jpg" → "photo.jpg")
        let filename = (storagePath as NSString).lastPathComponent
        
        // Check if already cached locally
        if let cachedImage = loadImage(named: filename) {
            print("✅ Image loaded from cache: \(filename)")
            return cachedImage
        }
        
        // Download from Firebase Storage
        print("⬇️ Downloading image from Firebase: \(storagePath)")
        let storageRef = storage.reference().child(storagePath)
        let maxSize: Int64 = 10 * 1024 * 1024 // 10MB max
        
        let data = try await storageRef.data(maxSize: maxSize)
        
        guard let image = UIImage(data: data) else {
            throw ImageError.invalidImageData
        }
        
        // Cache to disk for future use
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            print("✅ Image cached locally: \(filename)")
            
            // Also generate and cache thumbnail
            if let thumbnail = generateThumbnail(image, size: CGSize(width: 160, height: 160)) {
                let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                
                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbnailData.write(to: thumbnailURL)
                    print("✅ Thumbnail cached: \(thumbnailFilename)")
                }
            }
        } catch {
            print("⚠️ Failed to cache image: \(error.localizedDescription)")
            // Still return the image even if caching failed
        }
        
        return image
    }
    
    /// Download thumbnail from Firebase Storage and cache locally
    /// Falls back to full image if needed
    func downloadAndCacheThumbnail(storagePath: String, stampId: String) async throws -> UIImage {
        let filename = (storagePath as NSString).lastPathComponent
        
        // Check if thumbnail already cached
        if let cachedThumbnail = loadThumbnail(named: filename) {
            return cachedThumbnail
        }
        
        // Download full image and generate thumbnail
        let fullImage = try await downloadAndCacheImage(storagePath: storagePath, stampId: stampId)
        
        // Return thumbnail (was generated during caching)
        if let thumbnail = loadThumbnail(named: filename) {
            return thumbnail
        }
        
        // Fallback to full image
        return fullImage
    }
    
    /// Delete image from Firebase Storage
    func deleteImageFromFirebase(path: String) async throws {
        let storageRef = storage.reference().child(path)
        try await storageRef.delete()
        print("✅ Image deleted from Firebase: \(path)")
    }
    
    /// Download image from Firebase Storage
    func downloadImage(path: String) async throws -> UIImage {
        let storageRef = storage.reference().child(path)
        let maxSize: Int64 = 10 * 1024 * 1024 // 10MB max
        
        let data = try await storageRef.data(maxSize: maxSize)
        
        guard let image = UIImage(data: data) else {
            throw ImageError.invalidImageData
        }
        
        return image
    }
    
    // MARK: - Utilities
    
    /// Compress image to target size
    /// Returns JPEG data if successful
    func compressImage(_ image: UIImage, maxSizeMB: Double) -> Data? {
        let maxBytes = maxSizeMB * 1024 * 1024
        
        // Start with high quality
        var compression: CGFloat = 0.9
        guard var imageData = image.jpegData(compressionQuality: compression) else {
            return nil
        }
        
        // Gradually reduce quality until under size limit
        while imageData.count > Int(maxBytes) && compression > 0.1 {
            compression -= 0.1
            guard let compressed = image.jpegData(compressionQuality: compression) else {
                break
            }
            imageData = compressed
        }
        
        // If still too large, resize the image
        if imageData.count > Int(maxBytes) {
            let ratio = sqrt(maxBytes / Double(imageData.count))
            let newSize = CGSize(
                width: image.size.width * ratio,
                height: image.size.height * ratio
            )
            
            if let resized = resizeImage(image, to: newSize) {
                imageData = resized.jpegData(compressionQuality: 0.8) ?? imageData
            }
        }
        
        return imageData
    }
    
    /// Resize image to target size
    /// Forces scale = 1.0 so that points = pixels (no retina scaling)
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    private func resizeImageToFit(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        let newSize: CGSize
        if size.width > size.height {
            // Landscape or square
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            // Portrait
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        return resizeImage(image, to: newSize)
    }
    
    /// Generate thumbnail for feed display
    /// Forces scale = 1.0 so that points = pixels (no retina scaling)
    func generateThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 160, height: 160)) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // MARK: - Photo Upload Workflow
    
    /// Complete photo upload workflow: save images locally → upload to Firebase
    /// - Parameters:
    ///   - images: UIImages to save and upload
    ///   - stampId: ID of the stamp these photos belong to
    ///   - userId: User ID for Firebase upload (nil if not signed in)
    ///   - onPhotosAdded: Callback when photos are added to local storage (returns filenames)
    ///   - onUploadComplete: Callback when each photo finishes uploading (returns filename)
    func uploadPhotos(
        _ images: [UIImage],
        stampId: String,
        userId: String?,
        onPhotosAdded: @escaping ([String]) -> Void,
        onUploadComplete: @escaping (String) -> Void
    ) async {
        guard !images.isEmpty else { return }
        
        // STEP 1: Save all images locally (fast)
        var photosToUpload: [(image: UIImage, filename: String)] = []
        
        for image in images {
            // Save locally first (fast)
            if let filename = saveImage(image, stampId: stampId) {
                photosToUpload.append((image: image, filename: filename))
            }
        }
        
        // STEP 2: Notify caller with all filenames at once (so all spinners appear together)
        print("🔍 ImageManager: Saved \(photosToUpload.count) photos locally, notifying caller")
        let filenames = photosToUpload.map { $0.filename }
        await MainActor.run {
            onPhotosAdded(filenames)
        }
        
        // STEP 3: Upload to Firebase sequentially in background (user doesn't notice)
        guard let userId = userId else {
            // No user - just notify completion for all
            for photo in photosToUpload {
                await MainActor.run {
                    onUploadComplete(photo.filename)
                }
            }
            return
        }
        
        for photo in photosToUpload {
            do {
                _ = try await uploadImage(
                    photo.image,
                    stampId: stampId,
                    userId: userId,
                    filename: photo.filename
                )
                
                // Upload complete
                await MainActor.run {
                    onUploadComplete(photo.filename)
                }
                
            } catch {
                print("⚠️ Failed to upload to Firebase: \(error.localizedDescription)")
                // Photo is still saved locally, just notify completion
                await MainActor.run {
                    onUploadComplete(photo.filename)
                }
            }
        }
    }
}

// MARK: - Errors

enum ImageError: LocalizedError {
    case compressionFailed
    case invalidImageData
    case uploadFailed
    case downloadFailed
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Failed to compress image"
        case .invalidImageData:
            return "Invalid image data"
        case .uploadFailed:
            return "Failed to upload image"
        case .downloadFailed:
            return "Failed to download image"
        }
    }
}

