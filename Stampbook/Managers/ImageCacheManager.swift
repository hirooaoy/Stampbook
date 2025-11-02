import Foundation
import UIKit

/// Manages in-memory image cache with automatic cleanup to prevent memory leaks
/// Limits cache size and removes least recently used images when memory pressure occurs
class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    // MARK: - Configuration
    
    /// Maximum number of full-resolution images to keep in memory
    /// MVP optimized: 50 images at ~30KB each (200x200) = ~1.5MB total
    private let maxFullImageCount: Int = 50
    
    /// Maximum number of thumbnails to keep in memory
    /// MVP optimized: 200 thumbnails at ~5KB each = ~1MB total
    private let maxThumbnailCount: Int = 200
    
    // MARK: - Cache Storage
    
    private var fullImageCache: [String: CachedImage] = [:]
    private var thumbnailCache: [String: CachedImage] = [:]
    
    // Thread-safe access
    private let queue = DispatchQueue(label: "com.stampbook.imagecache", attributes: .concurrent)
    
    // MARK: - Cached Image Model
    
    private struct CachedImage {
        let image: UIImage
        var lastAccessTime: Date
        let sizeInBytes: Int
        
        init(image: UIImage) {
            self.image = image
            self.lastAccessTime = Date()
            // Estimate size: width * height * 4 (RGBA)
            let pixelCount = Int(image.size.width * image.scale * image.size.height * image.scale)
            self.sizeInBytes = pixelCount * 4
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Listen for memory warnings and clear cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Listen for app going to background and trim cache
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
    
    // MARK: - Cache Operations
    
    /// Get full-resolution image from cache
    func getFullImage(key: String) -> UIImage? {
        queue.sync {
            guard var cached = fullImageCache[key] else { return nil }
            
            // Update last access time (LRU)
            cached.lastAccessTime = Date()
            queue.async(flags: .barrier) {
                self.fullImageCache[key] = cached
            }
            
            return cached.image
        }
    }
    
    /// Store full-resolution image in cache
    func setFullImage(_ image: UIImage, key: String) {
        queue.async(flags: .barrier) {
            let cached = CachedImage(image: image)
            self.fullImageCache[key] = cached
            
            // Trim cache if needed
            self.trimFullImageCacheIfNeeded()
        }
    }
    
    /// Get thumbnail from cache
    func getThumbnail(key: String) -> UIImage? {
        queue.sync {
            guard var cached = thumbnailCache[key] else { return nil }
            
            // Update last access time (LRU)
            cached.lastAccessTime = Date()
            queue.async(flags: .barrier) {
                self.thumbnailCache[key] = cached
            }
            
            return cached.image
        }
    }
    
    /// Store thumbnail in cache
    func setThumbnail(_ image: UIImage, key: String) {
        queue.async(flags: .barrier) {
            let cached = CachedImage(image: image)
            self.thumbnailCache[key] = cached
            
            // Trim cache if needed
            self.trimThumbnailCacheIfNeeded()
        }
    }
    
    /// Remove specific image from cache
    func removeFullImage(key: String) {
        queue.async(flags: .barrier) {
            self.fullImageCache.removeValue(forKey: key)
        }
    }
    
    /// Remove specific thumbnail from cache
    func removeThumbnail(key: String) {
        queue.async(flags: .barrier) {
            self.thumbnailCache.removeValue(forKey: key)
        }
    }
    
    // MARK: - Cache Management
    
    /// Trim full image cache to max count using LRU strategy
    private func trimFullImageCacheIfNeeded() {
        guard fullImageCache.count > maxFullImageCount else { return }
        
        // Sort by last access time (oldest first)
        let sortedKeys = fullImageCache.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
        
        // Remove oldest images until we're under the limit
        let keysToRemove = sortedKeys.prefix(fullImageCache.count - maxFullImageCount).map { $0.key }
        
        for key in keysToRemove {
            fullImageCache.removeValue(forKey: key)
        }
        
        print("🗑️ ImageCacheManager: Trimmed \(keysToRemove.count) full images from cache (now \(fullImageCache.count))")
    }
    
    /// Trim thumbnail cache to max count using LRU strategy
    private func trimThumbnailCacheIfNeeded() {
        guard thumbnailCache.count > maxThumbnailCount else { return }
        
        // Sort by last access time (oldest first)
        let sortedKeys = thumbnailCache.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
        
        // Remove oldest thumbnails until we're under the limit
        let keysToRemove = sortedKeys.prefix(thumbnailCache.count - maxThumbnailCount).map { $0.key }
        
        for key in keysToRemove {
            thumbnailCache.removeValue(forKey: key)
        }
        
        print("🗑️ ImageCacheManager: Trimmed \(keysToRemove.count) thumbnails from cache (now \(thumbnailCache.count))")
    }
    
    /// Clear all cached images
    func clearAll() {
        queue.async(flags: .barrier) {
            let fullCount = self.fullImageCache.count
            let thumbCount = self.thumbnailCache.count
            
            self.fullImageCache.removeAll()
            self.thumbnailCache.removeAll()
            
            print("🗑️ ImageCacheManager: Cleared all caches (\(fullCount) full images, \(thumbCount) thumbnails)")
        }
    }
    
    /// Clear only full-resolution images (keep thumbnails)
    func clearFullImages() {
        queue.async(flags: .barrier) {
            let count = self.fullImageCache.count
            self.fullImageCache.removeAll()
            print("🗑️ ImageCacheManager: Cleared full image cache (\(count) images)")
        }
    }
    
    /// Clear only thumbnails (keep full images)
    func clearThumbnails() {
        queue.async(flags: .barrier) {
            let count = self.thumbnailCache.count
            self.thumbnailCache.removeAll()
            print("🗑️ ImageCacheManager: Cleared thumbnail cache (\(count) thumbnails)")
        }
    }
    
    // MARK: - System Event Handlers
    
    @objc private func handleMemoryWarning() {
        print("⚠️ ImageCacheManager: Memory warning received - clearing full image cache")
        clearFullImages()
        
        // Also trim thumbnails aggressively
        queue.async(flags: .barrier) {
            let sortedKeys = self.thumbnailCache.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
            let keysToKeep = sortedKeys.suffix(self.maxThumbnailCount / 2).map { $0.key }
            
            let keysToRemove = self.thumbnailCache.keys.filter { !keysToKeep.contains($0) }
            for key in keysToRemove {
                self.thumbnailCache.removeValue(forKey: key)
            }
            
            print("🗑️ ImageCacheManager: Aggressively trimmed thumbnails to \(self.thumbnailCache.count)")
        }
    }
    
    @objc private func handleAppBackground() {
        print("🗑️ ImageCacheManager: App backgrounded - clearing full image cache")
        clearFullImages()
    }
    
    // MARK: - Debug Info
    
    func printCacheInfo() {
        queue.async {
            let fullSize = self.fullImageCache.values.reduce(0) { $0 + $1.sizeInBytes }
            let thumbSize = self.thumbnailCache.values.reduce(0) { $0 + $1.sizeInBytes }
            
            let fullSizeMB = Double(fullSize) / (1024 * 1024)
            let thumbSizeMB = Double(thumbSize) / (1024 * 1024)
            
            print("""
            📊 ImageCacheManager Status:
               Full Images: \(self.fullImageCache.count)/\(self.maxFullImageCount) (~\(String(format: "%.1f", fullSizeMB))MB)
               Thumbnails: \(self.thumbnailCache.count)/\(self.maxThumbnailCount) (~\(String(format: "%.1f", thumbSizeMB))MB)
               Total: ~\(String(format: "%.1f", fullSizeMB + thumbSizeMB))MB
            """)
        }
    }
}

