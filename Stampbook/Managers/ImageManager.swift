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
    
    // MARK: - Disk Cache Management
    
    /// Maximum disk cache size for OTHER PEOPLE's content (user's own photos have no limit)
    private let maxDiskCacheSizeBytes: Int64 = 200 * 1024 * 1024 // 200MB
    
    /// Target size to trim down to when cleaning up (leaves headroom)
    private let targetDiskCacheSizeBytes: Int64 = 150 * 1024 * 1024 // 150MB
    
    /// Track file access times for LRU cleanup
    private let fileAccessQueue = DispatchQueue(label: "com.stampbook.fileAccessQueue")
    private let fileAccessTimesKey = "diskCacheFileAccessTimes"
    
    /// Track user's own uploaded files (NEVER delete these)
    private let userOwnedFilesKey = "userOwnedFiles"
    
    // MARK: - Request Deduplication
    
    /// Track in-flight profile picture downloads to prevent duplicate requests
    private var inFlightProfilePictures: [String: Task<UIImage, Error>] = [:]
    private let profilePictureQueue = DispatchQueue(label: "com.stampbook.profilePictureQueue")
    
    /// Track in-flight thumbnail downloads to prevent duplicate requests
    /// Same pattern as StampsManager to avoid race conditions
    private var inFlightThumbnails: [String: Task<UIImage, Error>] = [:]
    private let thumbnailQueue = DispatchQueue(label: "com.stampbook.thumbnailQueue")
    
    private init() {
        // Run migration to protect existing user photos and cleanup disk cache
        // This is safe for all installs (new users have no photos to migrate)
        Task {
            await migrateExistingUserPhotos()
            await cleanupDiskCacheIfNeeded()
        }
        
        // Listen for app going to background and cleanup
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppBackground() {
        Task {
            await cleanupDiskCacheIfNeeded()
        }
    }
    
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
            #if DEBUG
            print("📐 Resized image from \(image.size) to \(resizedImage.size)")
            #endif
        } else {
            resizedImage = image
            #if DEBUG
            print("📐 Image already under 2400px: \(image.size)")
            #endif
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
            #if DEBUG
            print("✅ Image saved locally: \(filename)")
            #endif
            
            // Track this as user's own file (NEVER delete during cleanup)
            markAsUserOwnedFile(filename)
            
            // Generate and save thumbnail for USER PHOTOS
            // Use aspect-FILL (cropped) so display can be simple .fit everywhere
            if let thumbnail = generateUserPhotoThumbnail(resizedImage, size: 512) {
                let thumbnailFilename = "\(stampId)_\(Int(timestamp))_\(uuid)_thumb.jpg"
                let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                
                if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try thumbnailData.write(to: thumbnailURL)
                    #if DEBUG
                    print("✅ Thumbnail saved (cropped): \(thumbnailFilename)")
                    #endif
                    // Track thumbnail as user's own file too
                    markAsUserOwnedFile(thumbnailFilename)
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
            recordFileAccess(filename) // Track access for LRU
            return cached
        }
        
        // Load from disk
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        
        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            // Store in cache for next time
            ImageCacheManager.shared.setFullImage(image, key: filename)
            recordFileAccess(filename) // Track access for LRU
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
            recordFileAccess(pngThumbnailFilename) // Track access for LRU
            return cached
        }
        
        // Try loading PNG thumbnail from disk
        let pngThumbnailURL = getDocumentsDirectory().appendingPathComponent(pngThumbnailFilename)
        if let thumbnailData = try? Data(contentsOf: pngThumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            // Store in cache for next time
            ImageCacheManager.shared.setThumbnail(thumbnail, key: pngThumbnailFilename)
            recordFileAccess(pngThumbnailFilename) // Track access for LRU
            return thumbnail
        }
        
        // Fallback to JPEG thumbnail (user photos, legacy images)
        let jpegThumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
            .replacingOccurrences(of: ".png", with: "_thumb.jpg")
        
        // Check memory cache for JPEG
        if let cached = ImageCacheManager.shared.getThumbnail(key: jpegThumbnailFilename) {
            recordFileAccess(jpegThumbnailFilename) // Track access for LRU
            return cached
        }
        
        // Try loading JPEG thumbnail from disk
        let jpegThumbnailURL = getDocumentsDirectory().appendingPathComponent(jpegThumbnailFilename)
        if let thumbnailData = try? Data(contentsOf: jpegThumbnailURL),
           let thumbnail = UIImage(data: thumbnailData) {
            // Store in cache for next time
            ImageCacheManager.shared.setThumbnail(thumbnail, key: jpegThumbnailFilename)
            recordFileAccess(jpegThumbnailFilename) // Track access for LRU
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
            #if DEBUG
            print("✅ Image deleted locally: \(filename)")
            #endif
            
            // Remove from memory cache
            ImageCacheManager.shared.removeFullImage(key: filename)
            
            // Unmark from user-owned tracking
            unmarkAsUserOwnedFile(filename)
            
            // Also delete thumbnail if it exists
            let thumbnailFilename = filename.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
            let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
            
            if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                try FileManager.default.removeItem(at: thumbnailURL)
                #if DEBUG
                print("✅ Thumbnail deleted: \(thumbnailFilename)")
                #endif
                // Remove thumbnail from memory cache
                ImageCacheManager.shared.removeThumbnail(key: thumbnailFilename)
                // Unmark thumbnail too
                unmarkAsUserOwnedFile(thumbnailFilename)
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
            #if DEBUG
            print("📐 Resizing for upload from \(image.size) to \(resizedImage.size)")
            #endif
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
        
        #if DEBUG
        print("✅ Image uploaded to Firebase: \(storagePath)")
        #endif
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
            #if DEBUG
            print("✅ Image loaded from memory cache: \(cacheKey)")
            #endif
            return cachedImage
        }
        
        // Check if already cached on disk
        if let cachedImage = loadImage(named: cacheKey) {
            #if DEBUG
            print("✅ Image loaded from disk cache: \(cacheKey)")
            #endif
            return cachedImage
        }
        
        // Download from Firebase Storage
        #if DEBUG
        print("⬇️ Downloading image from Firebase: \(storagePath)")
        #endif
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
            #if DEBUG
            print("✅ Image cached locally: \(cacheKey)")
            #endif
            
            // Also store in memory cache
            ImageCacheManager.shared.setFullImage(image, key: cacheKey)
            
            // Detect if this is a stamp image (from stamps/ path) vs user photo (from users/ path)
            // Stamp images stored at: stamps/us-ca-sf-dolores-park.png (starts with "stamps/")
            // User photos stored at: users/{userId}/stamps/{stampId}/photo.jpg (starts with "users/")
            let isStampImage = storagePath.hasPrefix("stamps/") || filename.hasSuffix(".png")
            
            // Notify widget that stamp image is now cached
            if isStampImage {
                NotificationCenter.default.post(name: Notification.Name("stampImageDownloaded"), object: nil, userInfo: ["stampId": stampId])
            }
            
            // Generate and cache thumbnail (512x512 for crisp @3x retina displays)
            // USER PHOTOS: Use aspect-fill (cropped) for square display
            // STAMP IMAGES: Use aspect-fit (with padding) to preserve full artwork
            let thumbnail: UIImage?
            if isStampImage {
                thumbnail = generateThumbnail(image, size: CGSize(width: 512, height: 512))
            } else {
                thumbnail = generateUserPhotoThumbnail(image, size: 512)
            }
            
            if let thumbnail = thumbnail {
                
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
                    #if DEBUG
                    print("✅ Thumbnail cached: \(thumbnailCacheKey) (\(isStampImage ? "PNG" : "JPEG"))")
                    #endif
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
    /// ✅ OPTIMIZED (Nov 17, 2025): In-flight request tracking prevents duplicate downloads
    func downloadAndCacheThumbnail(storagePath: String, stampId: String, imageUrl: String? = nil) async throws -> UIImage {
        let filename = (storagePath as NSString).lastPathComponent
        
        // Generate cache key for thumbnail lookup (same logic as downloadAndCacheImage)
        let baseCacheKey: String
        if let imageUrl = imageUrl, !imageUrl.isEmpty {
            baseCacheKey = generateCacheKey(from: imageUrl, stampId: stampId)
        } else {
            baseCacheKey = filename
        }
        
        #if DEBUG
        print("🔑 [ImageManager] Thumbnail cache key: \(baseCacheKey)_thumb.jpg")
        #endif
        
        // STEP 1: Check disk cache (fast path)
        if let cachedThumbnail = loadThumbnail(named: baseCacheKey) {
            #if DEBUG
            print("💾 [ImageManager] Thumbnail disk cache hit: \(baseCacheKey)_thumb.jpg")
            #endif
            return cachedThumbnail
        }
        
        // STEP 2: Check if already downloading (prevent duplicate Firebase requests)
        let thumbnailKey = "\(baseCacheKey)_thumb.jpg"
        let existingTask = thumbnailQueue.sync { () -> Task<UIImage, Error>? in
            return inFlightThumbnails[thumbnailKey]
        }
        
        if let existingTask = existingTask {
            #if DEBUG
            print("⏳ [ImageManager] Waiting for in-flight thumbnail download: \(thumbnailKey)")
            #endif
            return try await existingTask.value
        }
        
        // STEP 3: Start new download and register as in-flight
        let downloadTask = Task<UIImage, Error> {
            // Detect if this is a stamp image (PNG) vs user photo (JPEG)
            // Stamp images: stamps/us-ca-sf-dolores-park.png
            // User photos: users/{userId}/stamps/{stampId}/photo.jpg
            let filename = (storagePath as NSString).lastPathComponent
            let isStampImage = storagePath.hasPrefix("stamps/") || filename.hasSuffix(".png")
            
            // Try to download the _thumb file from Firebase Storage first
            let thumbnailStoragePath = storagePath.replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                .replacingOccurrences(of: ".png", with: "_thumb.png")
            let thumbnailRef = storage.reference().child(thumbnailStoragePath)
            
            do {
                #if DEBUG
                print("⬇️ [ImageManager] Starting thumbnail download: \(thumbnailKey)")
                #endif
                
                // Try downloading the thumbnail file
                let thumbnailData = try await thumbnailRef.data(maxSize: 10 * 1024 * 1024) // 10MB max
                
                if let thumbnailImage = UIImage(data: thumbnailData) {
                    // Cache it locally with proper extension matching
                    // CRITICAL: Must match loadThumbnail's key format!
                    let thumbnailFilename: String
                    let imageData: Data?
                    
                    if isStampImage {
                        // Stamp: Replace .png/.jpg with _thumb.png
                        thumbnailFilename = baseCacheKey
                            .replacingOccurrences(of: ".jpg", with: "_thumb.png")
                            .replacingOccurrences(of: ".png", with: "_thumb.png")
                        imageData = thumbnailImage.pngData()
                    } else {
                        // User photo: Replace .jpg/.png with _thumb.jpg
                        thumbnailFilename = baseCacheKey
                            .replacingOccurrences(of: ".jpg", with: "_thumb.jpg")
                            .replacingOccurrences(of: ".png", with: "_thumb.jpg")
                        imageData = thumbnailImage.jpegData(compressionQuality: 0.8)
                    }
                    
                    if let imageData = imageData {
                        let thumbnailURL = getDocumentsDirectory().appendingPathComponent(thumbnailFilename)
                        try imageData.write(to: thumbnailURL)
                        #if DEBUG
                        print("✅ Downloaded thumbnail from Firebase: \(thumbnailFilename)")
                        #endif
                        
                        // Store in memory cache for instant access
                        ImageCacheManager.shared.setThumbnail(thumbnailImage, key: thumbnailFilename)
                    }
                    
                    return thumbnailImage
                }
            } catch {
                // Thumbnail doesn't exist in Firebase, fall back to downloading full image
                #if DEBUG
                print("⚠️ Thumbnail not found in Firebase, downloading full image: \(error.localizedDescription)")
                #endif
            }
            
            // Fallback: Download full image and generate thumbnail locally
            let fullImage = try await downloadAndCacheImage(storagePath: storagePath, stampId: stampId, imageUrl: imageUrl)
            
            // Return thumbnail (was generated during caching)
            if let thumbnail = loadThumbnail(named: baseCacheKey) {
                return thumbnail
            }
            
            // Fallback to full image
            return fullImage
        }
        
        // Register task as in-flight
        thumbnailQueue.sync {
            inFlightThumbnails[thumbnailKey] = downloadTask
        }
        
        // Wait for download to complete
        do {
            let result = try await downloadTask.value
            
            // Clean up in-flight tracking
            _ = thumbnailQueue.sync {
                inFlightThumbnails.removeValue(forKey: thumbnailKey)
            }
            
            return result
        } catch {
            // Clean up in-flight tracking on error
            _ = thumbnailQueue.sync {
                inFlightThumbnails.removeValue(forKey: thumbnailKey)
            }
            throw error
        }
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
            #if DEBUG
            print("✅ Image deleted from Firebase: \(path)")
            #endif
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
            #if DEBUG
            print("📋 Found \(paths.count) images in Firebase for stamp \(stampId)")
            #endif
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
            #if DEBUG
            print("✅ No orphaned images found for stamp \(stampId)")
            #endif
            return 0
        }
        
        #if DEBUG
        print("🗑️ Found \(orphanedPaths.count) orphaned images to delete:")
        for path in orphanedPaths {
            print("  - \(path)")
        }
        #endif
        
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
        
        #if DEBUG
        print("✅ Cleaned up \(deletedCount) orphaned images for stamp \(stampId)")
        #endif
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
    
    /// Generate thumbnail for USER PHOTOS with aspect-fill (cropping)
    /// Returns a 512×512 square with the image FILLING the entire square (edges cropped)
    /// This is the opposite of generateThumbnail() which uses aspect-fit (with padding)
    func generateUserPhotoThumbnail(_ image: UIImage, size: CGFloat = 512) -> UIImage? {
        let squareSize = CGSize(width: size, height: size)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0  // 1x scale: points = pixels
        format.opaque = true  // User photos don't need transparency
        format.preferredRange = .standard
        
        // Calculate aspect-FILL (opposite of aspect-fit)
        // Scale to whichever dimension needs MORE scaling
        let scale = max(
            squareSize.width / image.size.width,
            squareSize.height / image.size.height
        )
        
        let scaledWidth = image.size.width * scale
        let scaledHeight = image.size.height * scale
        
        // Center the image (overflow will be clipped by canvas)
        let x = (squareSize.width - scaledWidth) / 2
        let y = (squareSize.height - scaledHeight) / 2
        
        let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        
        // Render - image fills entire square, edges get cropped
        let renderer = UIGraphicsImageRenderer(size: squareSize, format: format)
        return renderer.image { context in
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
        #if DEBUG
        print("🔍 ImageManager: Saved \(photosToUpload.count) photos locally, notifying caller")
        #endif
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
            #if DEBUG
            print("✅ Profile picture saved locally: \(filename)")
            #endif
            // Track as user's own file
            markAsUserOwnedFile(filename)
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
            #if DEBUG
            print("✅ Profile picture deleted locally: \(filename)")
            #endif
            // Remove from memory cache
            ImageCacheManager.shared.removeFullImage(key: filename)
        } catch {
            #if DEBUG
            print("⚠️ Failed to delete profile picture: \(error.localizedDescription)")
            #endif
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
                    #if DEBUG

                    print("⚠️ Failed to cache profile picture: \(error.localizedDescription)")
                    #endif
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
            #if DEBUG

            print("⚠️ Failed to resize profile picture for upload")
            #endif
            return nil
        }
        
        // Compress to reasonable size (max 200KB for faster uploads)
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.2) else {
            #if DEBUG

            print("⚠️ Failed to compress profile picture for upload")
            #endif
            return nil
        }
        
        let sizeInKB = Double(imageData.count) / 1024.0
        #if DEBUG

        print("✅ Profile picture prepared for upload: \(Int(sizeInKB))KB")
        #endif
        
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
                #if DEBUG

                print("🗑️ Cleared old profile picture from disk: \(oldFilename)")
                #endif
                clearedCount += 1
            } catch {
                // File might not exist, that's okay
                #if DEBUG

                print("ℹ️ Old profile picture not in disk cache: \(oldFilename)")
                #endif
            }
            
            // Clear from memory cache too
            ImageCacheManager.shared.removeFullImage(key: oldFilename)
            #if DEBUG

            print("🗑️ Cleared old profile picture from memory cache: \(oldFilename)")
            #endif
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
            
            #if DEBUG

            
            print("✅ Cleared \(clearedCount) cached profile pictures for user \(userId)")
            #endif
        } catch {
            #if DEBUG

            print("⚠️ Failed to enumerate cached profile pictures: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Pre-cache a newly uploaded profile picture to avoid network download
    /// Called after successful profile picture upload
    func precacheProfilePicture(image: UIImage, url: String, userId: String) {
        let filename = profilePictureCacheFilename(url: url, userId: userId)
        
        // Resize to cache size (200x200) - optimized for MVP
        guard let resizedImage = resizeProfilePicture(image, size: 200) else {
            #if DEBUG
            print("⚠️ Failed to resize profile picture for precaching")
            #endif
            return
        }
        
        // Compress
        guard let imageData = compressImage(resizedImage, maxSizeMB: 0.2) else {
            #if DEBUG
            print("⚠️ Failed to compress profile picture for precaching")
            #endif
            return
        }
        
        // Save to disk
        let fileURL = getDocumentsDirectory().appendingPathComponent(filename)
        do {
            try imageData.write(to: fileURL)
            #if DEBUG
            print("✅ Pre-cached new profile picture to disk: \(filename)")
            #endif
            
            // Also store in memory cache for immediate access
            ImageCacheManager.shared.setFullImage(resizedImage, key: filename)
            #if DEBUG
            print("✅ Pre-cached new profile picture to memory: \(filename)")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to pre-cache profile picture: \(error.localizedDescription)")
            #endif
        }
    }
    
    // MARK: - Disk Cache Cleanup
    
    /// ONE-TIME MIGRATION: Mark existing user photos as owned (prevents deletion on first cleanup)
    /// This should run once after deploying the tracking system to protect photos uploaded before tracking existed
    /// 
    /// TODO: Enable this after App Store launch by uncommenting in init()
    /// Once migration completes for all users, this code can be removed in a future version
    private func migrateExistingUserPhotos() async {
        let migrationKey = "photoTrackingMigrationComplete_v1"
        
        // Check if already migrated
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            #if DEBUG
            print("✅ [ImageManager] Photo migration already complete, skipping")
            #endif
            return
        }
        
        #if DEBUG
        print("🔄 [ImageManager] Starting one-time migration to protect existing user photos...")
        let migrationStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Get all files in documents directory
        let documentsURL = getDocumentsDirectory()
        let fileManager = FileManager.default
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            let filenames = fileURLs.map { $0.lastPathComponent }
            
            // Patterns that indicate user-owned files:
            // 1. User photos: {stampId}_{timestamp}_{uuid}.jpg
            // 2. User thumbnails: {stampId}_{timestamp}_{uuid}_thumb.jpg
            // 3. Profile pictures with timestamp: profile_{userId}_{timestamp}.jpg
            
            var migratedCount = 0
            
            for filename in filenames {
                // Check if it looks like a user-uploaded photo (has timestamp pattern)
                // Format: {id}_{timestamp}_{uuid}.jpg where timestamp is 10 digits
                let components = filename.components(separatedBy: "_")
                
                // User photo pattern: minimum 3 components, second component is numeric timestamp
                if components.count >= 3 {
                    let potentialTimestamp = components[1]
                    if potentialTimestamp.count == 10, Int(potentialTimestamp) != nil {
                        // This looks like a user-uploaded file - mark it as owned
                        fileAccessQueue.sync {
                            var userFiles = UserDefaults.standard.stringArray(forKey: userOwnedFilesKey) ?? []
                            if !userFiles.contains(filename) {
                                userFiles.append(filename)
                                UserDefaults.standard.set(userFiles, forKey: userOwnedFilesKey)
                                migratedCount += 1
                                #if DEBUG
                                print("📌 [Migration] Marked as user-owned: \(filename)")
                                #endif
                            }
                        }
                    }
                }
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: migrationKey)
            
            #if DEBUG
            let migrationTime = CFAbsoluteTimeGetCurrent() - migrationStart
            print("✅ [ImageManager] Migration complete: Protected \(migratedCount) existing user photos (\(String(format: "%.3f", migrationTime))s)")
            #endif
            
        } catch {
            print("⚠️ [ImageManager] Migration failed: \(error.localizedDescription)")
        }
    }
    
    /// Mark a file as owned by the user (will never be deleted during cleanup)
    private func markAsUserOwnedFile(_ filename: String) {
        fileAccessQueue.async {
            var userFiles = UserDefaults.standard.stringArray(forKey: self.userOwnedFilesKey) ?? []
            if !userFiles.contains(filename) {
                userFiles.append(filename)
                UserDefaults.standard.set(userFiles, forKey: self.userOwnedFilesKey)
                #if DEBUG
                print("📌 [ImageManager] Marked as user-owned: \(filename)")
                #endif
            }
        }
    }
    
    /// Remove a file from user-owned tracking (when user deletes their own photo)
    private func unmarkAsUserOwnedFile(_ filename: String) {
        fileAccessQueue.async {
            var userFiles = UserDefaults.standard.stringArray(forKey: self.userOwnedFilesKey) ?? []
            if let index = userFiles.firstIndex(of: filename) {
                userFiles.remove(at: index)
                UserDefaults.standard.set(userFiles, forKey: self.userOwnedFilesKey)
                #if DEBUG
                print("📌 [ImageManager] Unmarked as user-owned: \(filename)")
                #endif
            }
        }
    }
    
    /// Track when a file was accessed (for LRU cleanup)
    private func recordFileAccess(_ filename: String) {
        fileAccessQueue.async {
            var accessTimes = UserDefaults.standard.dictionary(forKey: self.fileAccessTimesKey) as? [String: TimeInterval] ?? [:]
            accessTimes[filename] = Date().timeIntervalSince1970
            UserDefaults.standard.set(accessTimes, forKey: self.fileAccessTimesKey)
        }
    }
    
    /// Get last access time for a file (returns epoch time, or 0 if never accessed)
    private func getFileAccessTime(_ filename: String) -> TimeInterval {
        fileAccessQueue.sync {
            let accessTimes = UserDefaults.standard.dictionary(forKey: fileAccessTimesKey) as? [String: TimeInterval] ?? [:]
            return accessTimes[filename] ?? 0
        }
    }
    
    /// Calculate total size of disk cache
    private func calculateDiskCacheSize() -> (totalBytes: Int64, fileList: [(filename: String, size: Int64, accessTime: TimeInterval)]) {
        let documentsURL = getDocumentsDirectory()
        let fileManager = FileManager.default
        
        var totalSize: Int64 = 0
        var fileList: [(filename: String, size: Int64, accessTime: TimeInterval)] = []
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.fileSizeKey])
            
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                
                // Get file size
                if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resources.fileSize {
                    totalSize += Int64(fileSize)
                    
                    // Get access time
                    let accessTime = getFileAccessTime(filename)
                    fileList.append((filename: filename, size: Int64(fileSize), accessTime: accessTime))
                }
            }
        } catch {
            print("⚠️ Failed to calculate disk cache size: \(error.localizedDescription)")
        }
        
        return (totalSize, fileList)
    }
    
    /// Check if a file belongs to the current user (NEVER delete these)
    private func isUserOwnedFile(_ filename: String, currentUserId: String?) -> Bool {
        // Check explicit tracking list (most reliable)
        let userFiles = UserDefaults.standard.stringArray(forKey: userOwnedFilesKey) ?? []
        if userFiles.contains(filename) {
            return true // Explicitly tracked as user's file
        }
        
        // Fallback: Profile pictures with userId in filename (backward compatibility)
        if filename.hasPrefix("profile_"), let userId = currentUserId, filename.contains(userId) {
            return true
        }
        
        // Everything else is deletable (cached content)
        return false
    }
    
    /// Clean up disk cache if over limit (LRU strategy)
    /// SAFETY: Never deletes user's own uploaded photos or current profile picture
    func cleanupDiskCacheIfNeeded(currentUserId: String? = nil) async {
        let cleanupStart = CFAbsoluteTimeGetCurrent()
        
        #if DEBUG
        print("🧹 [ImageManager] Starting disk cache cleanup check...")
        #endif
        
        // Calculate current cache size
        let (totalSize, fileList) = calculateDiskCacheSize()
        let totalSizeMB = Double(totalSize) / (1024 * 1024)
        
        #if DEBUG
        print("📊 [ImageManager] Total disk cache: \(String(format: "%.1f", totalSizeMB))MB (\(fileList.count) files)")
        #endif
        
        // Check if cleanup needed
        guard totalSize > maxDiskCacheSizeBytes else {
            #if DEBUG
            let cleanupTime = CFAbsoluteTimeGetCurrent() - cleanupStart
            print("✅ [ImageManager] Disk cache under limit, no cleanup needed (\(String(format: "%.3f", cleanupTime))s)")
            #endif
            return
        }
        
        #if DEBUG
        print("⚠️ [ImageManager] Disk cache over limit (\(String(format: "%.1f", totalSizeMB))MB > 200MB), cleaning up...")
        #endif
        
        // Separate files into owned vs deletable
        var deletableFiles: [(filename: String, size: Int64, accessTime: TimeInterval)] = []
        var ownedFilesSize: Int64 = 0
        
        for file in fileList {
            if isUserOwnedFile(file.filename, currentUserId: currentUserId) {
                ownedFilesSize += file.size
            } else {
                deletableFiles.append(file)
            }
        }
        
        #if DEBUG
        let ownedSizeMB = Double(ownedFilesSize) / (1024 * 1024)
        let deletableSizeMB = Double(deletableFiles.reduce(0) { $0 + $1.size }) / (1024 * 1024)
        print("📊 [ImageManager] User's files: \(String(format: "%.1f", ownedSizeMB))MB (protected)")
        print("📊 [ImageManager] Deletable files: \(String(format: "%.1f", deletableSizeMB))MB (\(deletableFiles.count) files)")
        #endif
        
        // Sort deletable files by access time (oldest first)
        deletableFiles.sort { $0.accessTime < $1.accessTime }
        
        // Delete oldest files until we're under target size
        var currentSize = totalSize
        var deletedCount = 0
        var deletedSize: Int64 = 0
        
        for file in deletableFiles {
            // Stop if we're under target
            if currentSize <= targetDiskCacheSizeBytes {
                break
            }
            
            // Delete the file
            let fileURL = getDocumentsDirectory().appendingPathComponent(file.filename)
            do {
                try FileManager.default.removeItem(at: fileURL)
                currentSize -= file.size
                deletedSize += file.size
                deletedCount += 1
                
                // Also remove from memory cache
                ImageCacheManager.shared.removeFullImage(key: file.filename)
                ImageCacheManager.shared.removeThumbnail(key: file.filename)
                
                #if DEBUG
                let lastAccess = Date(timeIntervalSince1970: file.accessTime)
                let daysSinceAccess = Date().timeIntervalSince(lastAccess) / (24 * 3600)
                print("🗑️ [ImageManager] Deleted: \(file.filename) (\(file.size / 1024)KB, last accessed \(String(format: "%.1f", daysSinceAccess)) days ago)")
                #endif
            } catch {
                print("⚠️ [ImageManager] Failed to delete \(file.filename): \(error.localizedDescription)")
            }
        }
        
        // Clean up access times for deleted files
        fileAccessQueue.async {
            var accessTimes = UserDefaults.standard.dictionary(forKey: self.fileAccessTimesKey) as? [String: TimeInterval] ?? [:]
            for file in deletableFiles.prefix(deletedCount) {
                accessTimes.removeValue(forKey: file.filename)
            }
            UserDefaults.standard.set(accessTimes, forKey: self.fileAccessTimesKey)
        }
        
        let finalSizeMB = Double(currentSize) / (1024 * 1024)
        let deletedSizeMB = Double(deletedSize) / (1024 * 1024)
        let cleanupTime = CFAbsoluteTimeGetCurrent() - cleanupStart
        
        #if DEBUG
        print("✅ [ImageManager] Cleanup complete: Deleted \(deletedCount) files (\(String(format: "%.1f", deletedSizeMB))MB)")
        print("📊 [ImageManager] Final cache size: \(String(format: "%.1f", finalSizeMB))MB")
        print("⏱️ [ImageManager] Cleanup took \(String(format: "%.3f", cleanupTime))s")
        #endif
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

