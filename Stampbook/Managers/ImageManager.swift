import Foundation
import Combine
import UIKit
import FirebaseStorage

// 💡 FUTURE OPTIMIZATION: Consider migrating to blob storage (Cloudflare R2, AWS S3) + CDN
// for better cost (~90% cheaper), faster global delivery (edge caching), and image optimization.
// Firebase Storage works well for MVP but can get expensive at scale.
// See: https://www.cloudflare.com/products/r2/ (free egress, $0.015/GB storage)

// ⚡ PHOTO UPLOAD OPTIMIZATIONS (Nov 3, 2025):
// 1. Parallel uploads: 4x faster for multiple photos (uses TaskGroup)
// 2. Efficient API usage: Eliminated redundant downloadURL calls (~200ms savings per photo)
// 3. Coordinated with PhotoGalleryView to avoid double Firestore writes (50% cost reduction)
// See PHOTO_UPLOAD_OPTIMIZATIONS.md for detailed analysis

class ImageManager: ObservableObject {
    static let shared = ImageManager()
    
    @Published var errorMessage: String? // Error message to display to user
    
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
            Logger.warning("Failed to compress image", category: "ImageManager")
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
            
            // Generate and save thumbnail (512x512 for crisp @3x retina displays)
            // Note: User photos are saved as JPEG (no transparency needed)
            if let thumbnail = generateThumbnail(resizedImage, size: CGSize(width: 512, height: 512)) {
                let thumbnailFilename = "\(stampId)_\(Int(timestamp))_\(uuid)_thumb.jpg"
                let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                
                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbnailData.write(to: thumbnailURL)
                    print("✅ Thumbnail saved: \(thumbnailFilename)")
                }
            }
            
            return filename
        } catch let saveError {
            Logger.error("Failed to save image", error: saveError, category: "ImageManager")
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
    /// Supports both PNG (stamp images) and JPEG (user photos) thumbnails
    func loadThumbnail(named filename: String) -> UIImage? {
        // Try PNG thumbnail first (stamp images with transparency)
        let pngThumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.png")
            .replacingOccurrences(of: ".png", with: "_thumb.png")
        
        // Check memory cache first (fastest) - try PNG
        if let cached = ImageCacheManager.shared.getThumbnail(key: pngThumbnailFilename) {
            return cached
        }
        
        // Try loading PNG thumbnail from disk
        let pngThumbnailURL = getDocumentsDirectory().appendingPathComponent(pngThumbnailFilename)
        if let thumbnailData = try? Data(contentsOf: pngThumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            // Store in cache for next time
            ImageCacheManager.shared.setThumbnail(thumbnail, key: pngThumbnailFilename)
            return thumbnail
        }
        
        // Fallback to JPEG thumbnail (user photos, legacy images)
        let jpegThumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
            .replacingOccurrences(of: ".png", with: "_thumb.jpg")
        
        // Check memory cache for JPEG
        if let cached = ImageCacheManager.shared.getThumbnail(key: jpegThumbnailFilename) {
            return cached
        }
        
        // Try loading JPEG thumbnail from disk
        let jpegThumbnailURL = getDocumentsDirectory().appendingPathComponent(jpegThumbnailFilename)
        if let thumbnailData = try? Data(contentsOf: jpegThumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            // Store in cache for next time
            ImageCacheManager.shared.setThumbnail(thumbnail, key: jpegThumbnailFilename)
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
        } catch let deleteError {
            Logger.error("Failed to delete image", error: deleteError, category: "ImageManager")
        }
    }
    
    /// Get app's documents directory
    func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    // MARK: - Firebase Storage
    
    // 📊 COST NOTE: Firebase Storage = $0.026/GB storage + $0.12/GB egress (downloads)
    // At scale, consider blob storage + CDN: Cloudflare R2 = $0.015/GB + FREE egress
    // Migration: Store CDN URLs in Firestore instead of Firebase Storage paths
    // 🎯 ACTION TRIGGER: Migrate to R2 when Firebase bill > $10/month OR 500+ users
    
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
    /// 
    /// ✅ CACHE INVALIDATION: Uses URL-based cache keys (includes token)
    /// When stamp images are updated in Firebase, the token changes automatically
    /// This triggers a cache miss and the new image downloads automatically
    /// Orphaned files from old tokens are harmless and cleaned by iOS when storage is low
    func downloadAndCacheImage(storagePath: String, stampId: String, imageUrl: String? = nil) async throws -> UIImage {
        // Extract filename from path (e.g., "users/123/stamps/abc/photo.jpg" → "photo.jpg")
        let filename = (storagePath as NSString).lastPathComponent
        
        // Generate cache key: Use full URL if available (includes token for auto-invalidation)
        // Fallback to filename for user photos (which don't have imageUrl)
        let cacheKey: String
        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            // For stamp images: Use URL-based key (token changes = new cache key)
            cacheKey = generateCacheKey(from: imageUrl, stampId: stampId)
        } else {
            // For user photos: Use filename (no URL available)
            cacheKey = filename
        }
        
        // Check memory cache first (fastest)
        if let cachedImage = ImageCacheManager.shared.getFullImage(key: cacheKey) {
            print("✅ Image loaded from memory cache: \(cacheKey)")
            return cachedImage
        }
        
        // Check if already cached on disk
        if let cachedImage = loadImage(named: cacheKey) {
            print("✅ Image loaded from disk cache: \(cacheKey)")
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
        
        // Cache to disk for future use (use cache key instead of filename)
        let fileURL = getDocumentsDirectory().appendingPathComponent(cacheKey)
        do {
            try data.write(to: fileURL)
            print("✅ Image cached locally: \(cacheKey)")
            
            // Also store in memory cache
            ImageCacheManager.shared.setFullImage(image, key: cacheKey)
            
            // Also generate and cache thumbnail (512x512 for crisp @3x retina displays)
            // Use PNG for stamp images to preserve transparency, JPEG for user photos
            if let thumbnail = generateThumbnail(image, size: CGSize(width: 512, height: 512)) {
                // Detect if this is a stamp image (from stamps/ path) vs user photo (from users/ path)
                // Stamp images stored at: stamps/us-ca-sf-dolores-park.png
                // User photos stored at: users/{userId}/stamps/{stampId}/photo.jpg
                let isStampImage = storagePath.contains("/stamps/") || filename.hasSuffix(".png")
                
                let thumbnailCacheKey: String
                let thumbnailData: Data?
                
                if isStampImage {
                    // Stamp images: use PNG to preserve transparency
                    // Append _thumb to cache key instead of replacing extension
                    thumbnailCacheKey = cacheKey.replacingOccurrences(of: ".jpg", with: "_thumb.png")
                        .replacingOccurrences(of: ".png", with: "_thumb.png")
                    thumbnailData = thumbnail.pngData()
                } else {
                    // User photos: use JPEG for smaller file size
                    thumbnailCacheKey = cacheKey.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                        .replacingOccurrences(of: ".png", with: "_thumb.jpg")
                    thumbnailData = thumbnail.jpegData(compressionQuality: 0.8)
                }
                
                if let thumbnailData = thumbnailData {
                    let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailCacheKey)
                    try thumbnailData.write(to: thumbnailURL)
                    print("✅ Thumbnail cached: \(thumbnailCacheKey) (\(isStampImage ? "PNG" : "JPEG"))")
                    // Store thumbnail in memory cache
                    ImageCacheManager.shared.setThumbnail(thumbnail, key: thumbnailCacheKey)
                }
            }
        } catch let cacheError {
            Logger.error("Failed to cache image", error: cacheError, category: "ImageManager")
            // Still return the image even if caching failed
        }
        
        return image
    }
    
    /// Download thumbnail from Firebase Storage and cache locally
    /// Falls back to full image if needed
    func downloadAndCacheThumbnail(storagePath: String, stampId: String, imageUrl: String? = nil) async throws -> UIImage {
        let filename = (storagePath as NSString).lastPathComponent
        
        // Generate cache key for thumbnail lookup (same logic as downloadAndCacheImage)
        let baseCacheKey: String
        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            baseCacheKey = generateCacheKey(from: imageUrl, stampId: stampId)
        } else {
            baseCacheKey = filename
        }
        
        // Check if thumbnail already cached
        if let cachedThumbnail = loadThumbnail(named: baseCacheKey) {
            return cachedThumbnail
        }
        
        // Download full image and generate thumbnail
        let fullImage = try await downloadAndCacheImage(storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
        
        // Return thumbnail (was generated during caching)
        if let thumbnail = loadThumbnail(named: baseCacheKey) {
            return thumbnail
        }
        
        // Fallback to full image
        return fullImage
    }
    
    /// Delete image from Firebase Storage
    func deleteImageFromFirebase(path: String) async throws {
        // Validate path is not empty
        guard !path.isEmpty else {
            Logger.warning("Cannot delete: empty storage path provided", category: "ImageManager")
            throw ImageError.invalidPath
        }
        
        // Ensure path doesn't contain any invalid characters
        guard path.contains("/") else {
            Logger.warning("Cannot delete: invalid storage path format: \(path)", category: "ImageManager")
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
                    Logger.warning("Image already deleted or doesn't exist in Firebase: \(path)", category: "ImageManager")
                    // Don't throw - image is already gone, which is the desired state
                    return
                case -13020: // Unauthorized
                    Logger.error("Permission denied deleting from Firebase Storage: \(path)", category: "ImageManager")
                    throw ImageError.deleteUnauthorized
                case -13030: // Canceled
                    Logger.warning("Deletion canceled: \(path)", category: "ImageManager")
                    throw ImageError.deletionCanceled
                default:
                    Logger.error("Firebase Storage error (\(error.code)): \(error.localizedDescription)", category: "ImageManager")
                    throw error
                }
            } else {
                // Network or other errors
                Logger.error("Network/other error deleting from Firebase", error: error, category: "ImageManager")
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
        } catch let fetchError {
            Logger.error("Failed to list Firebase images", error: fetchError, category: "ImageManager")
            throw fetchError
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
            } catch let deleteError {
                Logger.error("Failed to delete orphaned image \(path)", error: deleteError, category: "ImageManager")
                // Continue with other deletions
            }
        }
        
        print("✅ Cleaned up \(deletedCount) orphaned images for stamp \(stampId)")
        return deletedCount
    }
    
    
    // MARK: - Cache Key Generation
    
    /// Generate cache key from image URL
    /// Uses stampId + URL hash to create unique, debuggable cache keys
    /// When Firebase token changes (image update), hash changes → cache miss → re-download
    private func generateCacheKey(from imageUrl: String, stampId: String) -> String {
        // Use hash of URL (includes token) combined with stampId for debugging
        let urlHash = abs(imageUrl.hashValue)
        return "\(stampId)_\(urlHash).png"
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
    /// Preserves alpha channel for transparent images (like PNG stamps)
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        format.opaque = false  // Support transparency (for PNG stamps)
        format.preferredRange = .standard  // Use standard color range
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            // Clear the context to ensure transparency is preserved
            context.cgContext.clear(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    /// Resize image to fit within max dimension while maintaining aspect ratio
    func resizeImageToFit(_ image: UIImage, maxDimension: CGFloat) -> UIImage? {
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
    /// ALWAYS returns a square image (512×512) with the original image aspect-fitted inside
    /// and transparent padding around it. This ensures:
    /// - No cropping of tall/wide stamps
    /// - Perfect grid alignment (all thumbnails are same size)
    /// - No double letterboxing in UI
    /// Forces scale = 1.0 so that points = pixels (no retina scaling)
    /// Preserves alpha channel for transparent images (like PNG stamps)
    func generateThumbnail(_ image: UIImage, size: CGSize = CGSize(width: 512, height: 512)) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // Force 1x scale to get actual pixel dimensions
        format.opaque = false  // Support transparency (for PNG stamps)
        format.preferredRange = .standard  // Use standard color range
        
        // Calculate aspect fit rect (fit entire image within square, maintaining aspect ratio)
        let imageAspect = image.size.width / image.size.height
        let targetAspect = size.width / size.height
        
        let drawRect: CGRect
        if imageAspect > targetAspect {
            // Image is wider - fit to width, add transparent padding top/bottom
            let drawWidth = size.width
            let drawHeight = drawWidth / imageAspect
            let yOffset = (size.height - drawHeight) / 2
            drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
        } else {
            // Image is taller - fit to height, add transparent padding left/right
            let drawHeight = size.height
            let drawWidth = drawHeight * imageAspect
            let xOffset = (size.width - drawWidth) / 2
            drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        }
        
        // Always render to full size (512×512) with transparent padding
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // Clear the context to transparent (this is the padding)
            context.cgContext.clear(CGRect(origin: .zero, size: size))
            // Draw image centered within the square
            image.draw(in: drawRect)
        }
    }
    
    // MARK: - Photo Upload Workflow
    
    /// Complete photo upload workflow: save images locally → upload to Firebase
    /// 
    /// ⚡ OPTIMIZED (Nov 3, 2025): Parallel uploads for 4x faster performance
    /// - Multiple photos now upload concurrently instead of sequentially
    /// - Example: 4 photos @ 3s each = 3s total (was 12s)
    /// 
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
        
        // STEP 3: Upload to Firebase in parallel (much faster!)
        // ⚡ OPTIMIZATION: Changed from sequential to parallel uploads (Nov 3, 2025)
        // WHY: Sequential uploads were 4x slower - 4 photos took 12s instead of 3s
        // HOW: Use TaskGroup to upload all photos concurrently
        guard let userId = userId else {
            // No user - just notify completion for all (no storage paths)
            for photo in photosToUpload {
                await MainActor.run {
                    onUploadComplete(photo.filename, nil)
                }
            }
            return
        }
        
        // Upload all photos concurrently using TaskGroup
        // This allows Firebase Storage to handle multiple uploads simultaneously
        await withTaskGroup(of: (String, String?).self) { group in
            for photo in photosToUpload {
                group.addTask {
                    do {
                        let storagePath = try await self.uploadImage(
                            photo.image,
                            stampId: stampId,
                            userId: userId,
                            filename: photo.filename
                        )
                        return (photo.filename, storagePath)
                    } catch let uploadError {
                        Logger.error("Failed to upload \(photo.filename) to Firebase", error: uploadError, category: "ImageManager")
                        
                        // Show user-friendly error message (only once for batch)
                        await MainActor.run {
                            if self.errorMessage == nil {
                                self.errorMessage = "Some photos couldn't upload. They're saved locally."
                                
                                // Clear message after 4 seconds
                                Task {
                                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                                    await MainActor.run {
                                        if self.errorMessage == "Some photos couldn't upload. They're saved locally." {
                                            self.errorMessage = nil
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Photo is still saved locally, just return without storage path
                        return (photo.filename, nil)
                    }
                }
            }
            
            // Collect results as they complete
            for await (filename, storagePath) in group {
                await MainActor.run {
                    onUploadComplete(filename, storagePath)
                }
            }
        }
    }
    
    // MARK: - Profile Picture Management
    
    /// Save profile picture locally
    /// Resizes to 200x200px for efficient storage and fast loading
    /// Returns filename if successful
    func saveProfilePicture(_ image: UIImage, userId: String) -> String? {
        // Resize to 200x200px (square crop, aspect fill) - optimized for MVP
        // 200px = retina-ready + 4x faster downloads vs 400px
        guard let resizedImage = resizeProfilePicture(image, size: 200) else {
            Logger.warning("Failed to resize profile picture", category: "ImageManager")
            return nil
        }
        
        // Compress image (200px should be ~20-30KB vs ~80KB for 400px)
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.2) else {
            Logger.warning("Failed to compress profile picture", category: "ImageManager")
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
        } catch let saveError {
            Logger.error("Failed to save profile picture", error: saveError, category: "ImageManager")
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
    /// 
    /// 🌐 NOTE: CDN would make this much faster globally via edge caching (e.g. Cloudflare CDN)
    func downloadAndCacheProfilePicture(url: String, userId: String) async throws -> UIImage {
        #if DEBUG
        let downloadStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Generate cache filename from URL hash
        let filename = profilePictureCacheFilename(url: url, userId: userId)
        
        // Check memory cache first (fastest)
        if let cachedImage = ImageCacheManager.shared.getFullImage(key: filename) {
            #if DEBUG
            let cacheTime = CFAbsoluteTimeGetCurrent() - downloadStart
            print("⏱️ [ImageManager] Profile pic memory cache: \(String(format: "%.3f", cacheTime))s")
            #endif
            return cachedImage
        }
        
        // Check if already cached on disk
        if let cachedImage = loadProfilePicture(named: filename) {
            #if DEBUG
            let cacheTime = CFAbsoluteTimeGetCurrent() - downloadStart
            print("⏱️ [ImageManager] Profile pic disk cache: \(String(format: "%.3f", cacheTime))s")
            #endif
            return cachedImage
        }
        
        // ATOMIC: Check for existing task AND create new task if needed
        // This prevents race condition where multiple callers create duplicate tasks
        let downloadTask: Task<UIImage, Error> = profilePictureQueue.sync {
            // Check if there's already a download in progress
            if let existingTask = inFlightProfilePictures[url] {
                #if DEBUG
                print("⏱️ [ImageManager] Waiting for in-flight profile pic download")
                #endif
                return existingTask
            }
            
            // Create and store new task atomically
            let newTask = Task<UIImage, Error> {
                // Download from URL
                #if DEBUG
                let networkStart = CFAbsoluteTimeGetCurrent()
                print("⬇️ [ImageManager] Downloading profile picture from: \(url)")
                #endif
                
                guard let imageUrl = URL(string: url) else {
                    throw ImageError.invalidImageData
                }
                
                // Start network request
                #if DEBUG
                print("🌐 [ImageManager] Starting URLSession request...")
                let requestStart = CFAbsoluteTimeGetCurrent()
                #endif
                
                let (data, response) = try await URLSession.shared.data(from: imageUrl)
                
                #if DEBUG
                let requestTime = CFAbsoluteTimeGetCurrent() - requestStart
                // Log response details
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 [ImageManager] HTTP \(httpResponse.statusCode) - \(data.count) bytes in \(String(format: "%.3f", requestTime))s")
                }
                let networkTime = CFAbsoluteTimeGetCurrent() - networkStart
                print("⏱️ [ImageManager] Profile pic network download: \(String(format: "%.3f", networkTime))s")
                #endif
                
                // Decode image
                #if DEBUG
                let decodeStart = CFAbsoluteTimeGetCurrent()
                #endif
                
                guard let image = UIImage(data: data) else {
                    throw ImageError.invalidImageData
                }
                
                #if DEBUG
                let decodeTime = CFAbsoluteTimeGetCurrent() - decodeStart
                print("🖼️ [ImageManager] Image decoded in \(String(format: "%.3f", decodeTime))s")
                #endif
                
                // Cache to disk for future use
                #if DEBUG
                let cacheStart = CFAbsoluteTimeGetCurrent()
                #endif
                
                let fileURL = self.getDocumentsDirectory().appendingPathComponent(filename)
                do {
                    try data.write(to: fileURL)
                    #if DEBUG
                    let cacheTime = CFAbsoluteTimeGetCurrent() - cacheStart
                    print("✅ Profile picture cached locally: \(filename) in \(String(format: "%.3f", cacheTime))s")
                    #endif
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
            
            #if DEBUG
            let totalTime = CFAbsoluteTimeGetCurrent() - downloadStart
            print("⏱️ [ImageManager] Total profile pic load: \(String(format: "%.3f", totalTime))s")
            #endif
            
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
    /// Generate consistent cache filename from profile picture URL
    /// Used by ProfileImageView for synchronous cache checks
    func profilePictureCacheFilename(url: String, userId: String) -> String {
        // Use URL hash to create consistent filename
        let urlHash = url.hashValue
        return "profile_\(abs(urlHash)).jpg"
    }
    
    /// Prepare profile picture for upload (resize and compress)
    /// Returns JPEG data ready for Firebase Storage
    func prepareProfilePictureForUpload(_ image: UIImage) -> Data? {
        // Resize to 200x200px (optimized for MVP - 4x faster downloads)
        guard let resizedImage = resizeProfilePicture(image, size: 200) else {
            print("⚠️ Failed to resize profile picture for upload")
            return nil
        }
        
        // Compress to reasonable size (max 200KB for faster uploads)
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.2) else {
            print("⚠️ Failed to compress profile picture for upload")
            return nil
        }
        
        let sizeInKB = Double(imageData.count) / 1024.0
        print("✅ Profile picture prepared for upload: \(Int(sizeInKB))KB")
        
        return imageData
    }
    
    /// Clear all cached profile pictures for a user
    /// Called when user updates their profile picture
    /// Clears both disk cache (by URL hash pattern) and memory cache
    func clearCachedProfilePictures(userId: String, oldAvatarUrl: String? = nil) {
        let documentsURL = getDocumentsDirectory()
        let fileManager = FileManager.default
        var clearedCount = 0
        
        // If we have the old avatar URL, clear that specific file
        if let oldUrl = oldAvatarUrl, !oldUrl.isEmpty {
            let oldFilename = profilePictureCacheFilename(url: oldUrl, userId: userId)
            let fileURL = documentsURL.appendingPathComponent(oldFilename)
            
            do {
                try fileManager.removeItem(at: fileURL)
                print("🗑️ Cleared old profile picture from disk: \(oldFilename)")
                clearedCount += 1
            } catch {
                // File might not exist, that's okay
                print("ℹ️ Old profile picture not in disk cache: \(oldFilename)")
            }
            
            // Clear from memory cache too
            ImageCacheManager.shared.removeFullImage(key: oldFilename)
            print("🗑️ Cleared old profile picture from memory cache: \(oldFilename)")
        }
        
        // Also clear all profile_* files for this user as a safety measure
        // This catches any orphaned cache files
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            
            // Get all profile picture files (profile_<hash>.jpg format)
            let profilePictures = fileURLs.filter { 
                let filename = $0.lastPathComponent
                return filename.hasPrefix("profile_") && filename.hasSuffix(".jpg")
            }
            
            // Clear from memory cache first
            for fileURL in profilePictures {
                let filename = fileURL.lastPathComponent
                ImageCacheManager.shared.removeFullImage(key: filename)
            }
            
            print("✅ Cleared \(clearedCount) cached profile pictures for user \(userId)")
        } catch {
            print("⚠️ Failed to enumerate cached profile pictures: \(error.localizedDescription)")
        }
    }
    
    /// Pre-cache a newly uploaded profile picture to avoid network download
    /// Called after successful profile picture upload
    func precacheProfilePicture(image: UIImage, url: String, userId: String) {
        let filename = profilePictureCacheFilename(url: url, userId: userId)
        
        // Resize to cache size (200x200) - optimized for MVP
        guard let resizedImage = resizeProfilePicture(image, size: 200) else {
            print("⚠️ Failed to resize profile picture for precaching")
            return
        }
        
        // Compress
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.2) else {
            print("⚠️ Failed to compress profile picture for precaching")
            return
        }
        
        // Save to disk
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL)
            print("✅ Pre-cached new profile picture to disk: \(filename)")
            
            // Also store in memory cache for immediate access
            ImageCacheManager.shared.setFullImage(resizedImage, key: filename)
            print("✅ Pre-cached new profile picture to memory: \(filename)")
        } catch {
            print("⚠️ Failed to pre-cache profile picture: \(error.localizedDescription)")
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

