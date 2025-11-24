import Foundation

/// Lightweight stamp data for widget display
/// Keeps only essential info to minimize memory usage (<30MB limit)
struct WidgetStamp: Codable, Identifiable {
    let id: String // stampId (format: country-state-city-place-name)
    let name: String
    let collectedDate: Date
    let imageFileName: String // Cached filename to load from shared container
    
    init(id: String, name: String, collectedDate: Date, imageFileName: String) {
        self.id = id
        self.name = name
        self.collectedDate = collectedDate
        self.imageFileName = imageFileName
    }
    
    /// Parse location from stamp ID
    /// Example: "us-ca-san-francisco-golden-gate-bridge" → "San Francisco, CA"
    var locationDisplay: String {
        let parts = id.split(separator: "-")
        guard parts.count >= 3 else { return "" }
        
        let state = String(parts[1]).uppercased()
        let cityParts = parts[2...]
        let cityName = cityParts.map { String($0).capitalized }.joined(separator: " ")
        
        return "\(cityName), \(state)"
    }
}

/// Manages shared data between app and widget using App Groups
class WidgetDataManager {
    static let shared = WidgetDataManager()
    
    // MARK: - App Group Configuration
    
    /// App Group identifier - must match in both app and widget targets
    /// Format: group.{bundle-id}
    static let appGroupIdentifier = "group.com.hiroo.Stampbook"
    
    private let widgetStampsKey = "widgetStamps"
    private let maxWidgetStamps = 30 // Only store last 30 stamps for widget
    
    /// Shared UserDefaults for App Group communication
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetDataManager.appGroupIdentifier)
    }
    
    /// Shared container URL for file storage (images)
    var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier)
    }
    
    // MARK: - Widget Data Management
    
    /// Save stamps for widget display
    /// Call this whenever user collects a new stamp or on app launch
    func saveStampsForWidget(_ stamps: [WidgetStamp]) {
        guard let defaults = sharedDefaults else {
            print("⚠️ Failed to access shared UserDefaults")
            return
        }
        
        // Only keep most recent stamps to minimize memory
        let recentStamps = Array(stamps.prefix(maxWidgetStamps))
        
        if let encoded = try? JSONEncoder().encode(recentStamps) {
            defaults.set(encoded, forKey: widgetStampsKey)
            print("✅ Saved \(recentStamps.count) stamps for widget")
        }
    }
    
    /// Load stamps for widget display
    /// Widget calls this to get random stamp
    func loadStampsForWidget() -> [WidgetStamp] {
        guard let defaults = sharedDefaults else {
            print("⚠️ Failed to access shared UserDefaults")
            return []
        }
        
        guard let data = defaults.data(forKey: widgetStampsKey) else {
            print("ℹ️ No widget stamps found")
            return []
        }
        
        guard let stamps = try? JSONDecoder().decode([WidgetStamp].self, from: data) else {
            print("⚠️ Failed to decode widget stamps")
            return []
        }
        
        return stamps
    }
    
    /// Get random stamp for widget display
    func getRandomStamp() -> WidgetStamp? {
        let stamps = loadStampsForWidget()
        return stamps.randomElement()
    }
    
    // MARK: - Image Cache Management
    
    /// Copy image from app's cache to shared container for widget access
    /// Returns the filename in shared container
    func copyImageToSharedContainer(from sourceURL: URL, stampId: String) -> String? {
        guard let sharedURL = sharedContainerURL else {
            print("⚠️ Shared container not available")
            return nil
        }
        
        // Create images directory in shared container
        let imagesDir = sharedURL.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        
        // Use stampId as filename to ensure uniqueness
        let fileExtension = sourceURL.pathExtension
        let sharedFileName = "\(stampId).\(fileExtension)"
        let destinationURL = imagesDir.appendingPathComponent(sharedFileName)
        
        // Copy image if it doesn't exist yet
        if !FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                print("✅ Copied image to shared container: \(sharedFileName)")
            } catch {
                print("⚠️ Failed to copy image: \(error.localizedDescription)")
                return nil
            }
        }
        
        return sharedFileName
    }
    
    /// Load image from shared container (for widget)
    func loadImageFromSharedContainer(fileName: String) -> URL? {
        guard let sharedURL = sharedContainerURL else { return nil }
        let imageURL = sharedURL.appendingPathComponent("Images").appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            return nil
        }
        
        return imageURL
    }
}

