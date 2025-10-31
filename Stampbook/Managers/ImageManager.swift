import Foundation
import UIKit
import FirebaseStorage

class ImageManager {
    static let shared = ImageManager()
    
    private let storage = Storage.storage()
    
    // MARK: - Request Deduplication
    
    /// Track in-flight profile picture downloads to prevent duplicate requests
    private var inFlightProfilePictures: [String: Task<UIImage, Error>] = [:]
    private let profilePictureQueue = DispatchQueue(label: "com.stampbook.profilePictureQueue")
    
    private init() {}
    
    // MARK: - Local Storage
    
    /// Save image to local documents directory
    /// Automatically resizes to max 2400px and generates thumbnail
    /// Compresses to max 800KB to reduce storage costs
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
        
        // Compress image (reduced from 2MB to 0.8MB for cost savings)
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.8) else {
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
    /// Checks in-memory cache first for 5-10x speedup
    func loadImage(named filename: String) -> UIImage? {
        // Check memory cache first (fastest)
        if let cached = ImageCacheManager.shared.getFullImage(key: filename) {
            return cached
        }
        
        // Load from disk
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            // Store in cache for next time
            ImageCacheManager.shared.setFullImage(image, key: filename)
            return image
        }
        
        return nil
    }
    
    /// Load thumbnail image from local documents directory
    /// Checks in-memory cache first for 5-10x speedup
    /// Falls back to full-res if thumbnail doesn't exist
    func loadThumbnail(named filename: String) -> UIImage? {
        // Check memory cache first (fastest)
        let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
        if let cached = ImageCacheManager.shared.getThumbnail(key: thumbnailFilename) {
            return cached
        }
        
        // Try loading thumbnail from disk
        let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
        
        if let thumbnailData = try? Data(contentsOf: thumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            // Store in cache for next time
            ImageCacheManager.shared.setThumbnail(thumbnail, key: thumbnailFilename)
            return thumbnail
        }
        
        // Fallback to full-res (for old images without thumbnails)
        return loadImage(named: filename)
    }
    
    /// Delete image from local documents directory
    /// Also deletes the associated thumbnail and clears from memory cache
    func deleteImage(named filename: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("✅ Image deleted locally: \(filename)")
            
            // Remove from memory cache
            ImageCacheManager.shared.removeFullImage(key: filename)
            
            // Also delete thumbnail if it exists
            let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
            let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
            
            if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                try FileManager.default.removeItem(at: thumbnailURL)
                print("✅ Thumbnail deleted: \(thumbnailFilename)")
                // Remove thumbnail from memory cache
                ImageCacheManager.shared.removeThumbnail(key: thumbnailFilename)
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
    /// Compresses to max 800KB to reduce storage and bandwidth costs
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
        
        // Compress image (reduced from 2MB to 0.8MB for cost savings)
        // This reduces storage costs by ~60% and upload bandwidth costs significantly
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.8) else {
            throw ImageError.compressionFailed
        }
        
        // Storage path: users/{userId}/stamps/{stampId}/{filename}
        let storagePath = "users/\(userId)/stamps/\(stampId)/\(filename)"
        let storageRef = storage.reference().child(storagePath)
        
        // Upload with metadata including cache control for CDN efficiency
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        // Cache for 7 days (604800 seconds) to reduce repeated downloads
        metadata.cacheControl = "public, max-age=604800"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        
        print("✅ Image uploaded to Firebase: \(storagePath)")
        return storagePath
    }
    
    /// Download image from Firebase Storage and cache locally
    /// Returns cached image if already exists (checks memory and disk)
    func downloadAndCacheImage(storagePath: String, stampId: String) async throws -> UIImage {
        // Extract filename from path (e.g., "users/123/stamps/abc/photo.jpg" → "photo.jpg")
        let filename = (storagePath as NSString).lastPathComponent
        
        // Check memory cache first (fastest)
        if let cachedImage = ImageCacheManager.shared.getFullImage(key: filename) {
            print("✅ Image loaded from memory cache: \(filename)")
            return cachedImage
        }
        
        // Check if already cached on disk
        if let cachedImage = loadImage(named: filename) {
            print("✅ Image loaded from disk cache: \(filename)")
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
            
            // Also store in memory cache
            ImageCacheManager.shared.setFullImage(image, key: filename)
            
            // Also generate and cache thumbnail
            if let thumbnail = generateThumbnail(image, size: CGSize(width: 160, height: 160)) {
                let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                
                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbnailData.write(to: thumbnailURL)
                    print("✅ Thumbnail cached: \(thumbnailFilename)")
                    // Store thumbnail in memory cache
                    ImageCacheManager.shared.setThumbnail(thumbnail, key: thumbnailFilename)
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
        // Validate path is not empty
        guard !path.isEmpty else {
            print("⚠️ Cannot delete: empty storage path provided")
            throw ImageError.invalidPath
        }
        
        // Ensure path doesn't contain any invalid characters
        guard path.contains("/") else {
            print("⚠️ Cannot delete: invalid storage path format: \(path)")
            throw ImageError.invalidPath
        }
        
        let storageRef = storage.reference().child(path)
        
        do {
            try await storageRef.delete()
            print("✅ Image deleted from Firebase: \(path)")
        } catch let error as NSError {
            // Check specific Firebase Storage error codes
            if error.domain == "FIRStorageErrorDomain" {
                switch error.code {
                case -13010: // Object not found
                    print("⚠️ Image already deleted or doesn't exist in Firebase: \(path)")
                    // Don't throw - image is already gone, which is the desired state
                    return
                case -13020: // Unauthorized
                    print("❌ Permission denied deleting from Firebase Storage: \(path)")
                    throw ImageError.deleteUnauthorized
                case -13030: // Canceled
                    print("⚠️ Deletion canceled: \(path)")
                    throw ImageError.deletionCanceled
                default:
                    print("❌ Firebase Storage error (\(error.code)): \(error.localizedDescription)")
                    throw error
                }
            } else {
                // Network or other errors
                print("❌ Network/other error deleting from Firebase: \(error.localizedDescription)")
                throw error
            }
        }
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
    
    // MARK: - Cleanup Utilities
    
    /// List all images in Firebase Storage for a user's stamp
    /// Useful for debugging and cleanup
    func listImagesInFirebase(userId: String, stampId: String) async throws -> [String] {
        let path = "users/\(userId)/stamps/\(stampId)/"
        let storageRef = storage.reference().child(path)
        
        do {
            let result = try await storageRef.listAll()
            let paths = result.items.map { $0.fullPath }
            print("📋 Found \(paths.count) images in Firebase for stamp \(stampId)")
            return paths
        } catch {
            print("⚠️ Failed to list Firebase images: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Clean up orphaned images in Firebase Storage
    /// Deletes images that exist in Firebase but not in the user's collected stamps
    /// USE WITH CAUTION - this permanently deletes files
    func cleanupOrphanedImages(userId: String, stampId: String, validImagePaths: [String]) async throws -> Int {
        // Get all images in Firebase for this stamp
        let allFirebasePaths = try await listImagesInFirebase(userId: userId, stampId: stampId)
        
        // Find orphaned images (in Firebase but not in validImagePaths)
        let validPathsSet = Set(validImagePaths)
        let orphanedPaths = allFirebasePaths.filter { !validPathsSet.contains($0) }
        
        guard !orphanedPaths.isEmpty else {
            print("✅ No orphaned images found for stamp \(stampId)")
            return 0
        }
        
        print("🗑️ Found \(orphanedPaths.count) orphaned images to delete:")
        for path in orphanedPaths {
            print("  - \(path)")
        }
        
        // Delete each orphaned image
        var deletedCount = 0
        for path in orphanedPaths {
            do {
                try await deleteImageFromFirebase(path: path)
                deletedCount += 1
            } catch {
                print("⚠️ Failed to delete orphaned image \(path): \(error.localizedDescription)")
                // Continue with other deletions
            }
        }
        
        print("✅ Cleaned up \(deletedCount) orphaned images for stamp \(stampId)")
        return deletedCount
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
    /// Uses aspectFill to crop (not squish) the image to fill the square
    /// Forces scale = 1.0 so that points = pixels (no retina scaling)
    func generateThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 160, height: 160)) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        
        // Calculate aspect fill rect (crop to fill square, maintaining aspect ratio)
        let imageAspect = image.size.width / image.size.height
        let targetAspect = size.width / size.height
        
        let drawRect: CGRect
        if imageAspect > targetAspect {
            // Image is wider - crop sides
            let drawHeight = size.height
            let drawWidth = drawHeight * imageAspect
            let xOffset = (size.width - drawWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        } else {
            // Image is taller - crop top/bottom
            let drawWidth = size.width
            let drawHeight = drawWidth / imageAspect
            let yOffset = (size.height - drawHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        }
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // Clip to bounds so we only see the center portion
            UIRectClip(CGRect(origin: .zero, size: size))
            image.draw(in: drawRect)
        }
    }
    
    // MARK: - Photo Upload Workflow
    
    /// Complete photo upload workflow: save images locally → upload to Firebase
    /// - Parameters:
    ///   - images: UIImages to save and upload
    ///   - stampId: ID of the stamp these photos belong to
    ///   - userId: User ID for Firebase upload (nil if not signed in)
    ///   - onPhotosAdded: Callback when photos are added to local storage (returns filenames)
    ///   - onUploadComplete: Callback when each photo finishes uploading (returns filename and storage path)
    func uploadPhotos(
        _ images: [UIImage],
        stampId: String,
        userId: String?,
        onPhotosAdded: @escaping ([String]) -> Void,
        onUploadComplete: @escaping (String, String?) -> Void
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
            // No user - just notify completion for all (no storage paths)
            for photo in photosToUpload {
                await MainActor.run {
                    onUploadComplete(photo.filename, nil)
                }
            }
            return
        }
        
        for photo in photosToUpload {
            do {
                // 🔧 FIX: Capture the storage path instead of throwing it away
                let storagePath = try await uploadImage(
                    photo.image,
                    stampId: stampId,
                    userId: userId,
                    filename: photo.filename
                )
                
                // Upload complete - pass back the storage path
                await MainActor.run {
                    onUploadComplete(photo.filename, storagePath)
                }
                
            } catch {
                print("⚠️ Failed to upload to Firebase: \(error.localizedDescription)")
                // Photo is still saved locally, just notify completion without storage path
                await MainActor.run {
                    onUploadComplete(photo.filename, nil)
                }
            }
        }
    }
    
    // MARK: - Profile Picture Management
    
    /// Save profile picture locally
    /// Resizes to 400x400px for efficient storage
    /// Returns filename if successful
    func saveProfilePicture(_ image: UIImage, userId: String) -> String? {
        // Resize to 400x400px (square crop, aspect fill)
        guard let resizedImage = resizeProfilePicture(image, size: 400) else {
            print("⚠️ Failed to resize profile picture")
            return nil
        }
        
        // Compress image
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.5) else {
            print("⚠️ Failed to compress profile picture")
            return nil
        }
        
        // Generate filename based on user ID and timestamp
        let timestamp = Date().timeIntervalSince1970
        let filename = "profile_\(userId)_\(Int(timestamp)).jpg"
        
        // Save to documents directory
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            print("✅ Profile picture saved locally: \(filename)")
            return filename
        } catch {
            print("⚠️ Failed to save profile picture: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load profile picture from local cache
    /// Checks in-memory cache first for 5-10x speedup
    func loadProfilePicture(named filename: String) -> UIImage? {
        // Check memory cache first (fastest)
        if let cached = ImageCacheManager.shared.getFullImage(key: filename) {
            return cached
        }
        
        // Load from disk
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            // Store in cache for next time
            ImageCacheManager.shared.setFullImage(image, key: filename)
            return image
        }
        
        return nil
    }
    
    /// Delete profile picture from local cache and memory
    func deleteProfilePicture(named filename: String) {
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("✅ Profile picture deleted locally: \(filename)")
            // Remove from memory cache
            ImageCacheManager.shared.removeFullImage(key: filename)
        } catch {
            print("⚠️ Failed to delete profile picture: \(error.localizedDescription)")
        }
    }
    
    /// Download and cache profile picture from Firebase Storage URL
    /// Returns cached image if already exists (checks memory and disk)
    /// OPTIMIZED: Deduplicates concurrent requests for same URL
    func downloadAndCacheProfilePicture(url: String, userId: String) async throws -> UIImage {
        // Generate cache filename from URL hash
        let filename = profilePictureCacheFilename(url: url, userId: userId)
        
        // Check memory cache first (fastest)
        if let cachedImage = ImageCacheManager.shared.getFullImage(key: filename) {
            return cachedImage
        }
        
        // Check if already cached on disk
        if let cachedImage = loadProfilePicture(named: filename) {
            return cachedImage
        }
        
        // ATOMIC: Check for existing task AND create new task if needed
        // This prevents race condition where multiple callers create duplicate tasks
        let downloadTask: Task<UIImage, Error> = profilePictureQueue.sync {
            // Check if there's already a download in progress
            if let existingTask = inFlightProfilePictures[url] {
                return existingTask
            }
            
            // Create and store new task atomically
            let newTask = Task<UIImage, Error> {
                // Download from URL
                print("⬇️ Downloading profile picture from: \(url)")
                guard let imageUrl = URL(string: url) else {
                    throw ImageError.invalidImageData
                }
                
                let (data, _) = try await URLSession.shared.data(from: imageUrl)
                
                guard let image = UIImage(data: data) else {
                    throw ImageError.invalidImageData
                }
                
                // Cache to disk for future use
                let fileURL = self.getDocumentsDirectory().appendingPathComponent(filename)
                do {
                    try data.write(to: fileURL)
                    print("✅ Profile picture cached locally: \(filename)")
                    // Also store in memory cache
                    ImageCacheManager.shared.setFullImage(image, key: filename)
                } catch {
                    print("⚠️ Failed to cache profile picture: \(error.localizedDescription)")
                    // Still return the image even if caching failed
                }
                
                return image
            }
            
            inFlightProfilePictures[url] = newTask
            return newTask
        }
        
        // Wait for download to complete
        do {
            let image = try await downloadTask.value
            
            // Clean up the in-flight task
            _ = profilePictureQueue.sync {
                inFlightProfilePictures.removeValue(forKey: url)
            }
            
            return image
        } catch {
            // Clean up the in-flight task on error too
            _ = profilePictureQueue.sync {
                inFlightProfilePictures.removeValue(forKey: url)
            }
            throw error
        }
    }
    
    /// Resize profile picture to square (crop with aspect fill)
    /// Used for consistent profile picture sizing
    private func resizeProfilePicture(_ image: UIImage, size: CGFloat) -> UIImage? {
        let targetSize = CGSize(width: size, height: size)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        
        // Calculate aspect fill rect (crop to fill square, maintaining aspect ratio)
        let imageAspect = image.size.width / image.size.height
        
        let drawRect: CGRect
        if imageAspect > 1.0 {
            // Image is wider - crop sides
            let drawHeight = size
            let drawWidth = drawHeight * imageAspect
            let xOffset = (size - drawWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        } else {
            // Image is taller - crop top/bottom
            let drawWidth = size
            let drawHeight = drawWidth / imageAspect
            let yOffset = (size - drawHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            // Clip to bounds so we only see the center portion
            UIRectClip(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
    }
    
    /// Generate cache filename for profile picture based on URL hash only
    /// Using only URL hash ensures prefetched images are reused (no userId dependency)
    private func profilePictureCacheFilename(url: String, userId: String) -> String {
        // Use URL hash to create consistent filename
        let urlHash = url.hashValue
        return "profile_\(abs(urlHash)).jpg"
    }
    
    /// Prepare profile picture for upload (resize and compress)
    /// Returns JPEG data ready for Firebase Storage
    func prepareProfilePictureForUpload(_ image: UIImage) -> Data? {
        // Resize to 400x400px
        guard let resizedImage = resizeProfilePicture(image, size: 400) else {
            print("⚠️ Failed to resize profile picture for upload")
            return nil
        }
        
        // Compress to reasonable size (max 500KB)
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.5) else {
            print("⚠️ Failed to compress profile picture for upload")
            return nil
        }
        
        let sizeInKB = Double(imageData.count) / 1024.0
        print("✅ Profile picture prepared for upload: \(Int(sizeInKB))KB")
        
        return imageData
    }
    
    /// Clear old cached profile pictures for a user
    /// Useful when user updates their profile picture
    func clearCachedProfilePictures(userId: String) {
        let documentsURL = getDocumentsDirectory()
        let fileManager = FileManager.default
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let profilePictures = fileURLs.filter { $0.lastPathComponent.hasPrefix("profile_\(userId)_") }
            
            for fileURL in profilePictures {
                try fileManager.removeItem(at: fileURL)
                print("🗑️ Cleared cached profile picture: \(fileURL.lastPathComponent)")
            }
            
            print("✅ Cleared \(profilePictures.count) cached profile pictures for user \(userId)")
        } catch {
            print("⚠️ Failed to clear cached profile pictures: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum ImageError: LocalizedError {
    case compressionFailed
    case invalidImageData
    case uploadFailed
    case downloadFailed
    case invalidPath
    case deleteUnauthorized
    case deletionCanceled
    
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
        case .invalidPath:
            return "Invalid storage path"
        case .deleteUnauthorized:
            return "Permission denied - unable to delete image from cloud storage"
        case .deletionCanceled:
            return "Deletion was canceled"
        }
    }
}

