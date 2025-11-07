import Foundation
import CoreLocation

struct Stamp: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let imageName: String  // DEPRECATED: Use imageUrl instead
    let imageUrl: String?  // Firebase Storage URL for stamp image
    let collectionIds: [String]
    let about: String
    let thingsToDoFromEditors: [String]
    let geohash: String? // Optional for backward compatibility
    
    // ==================== VISIBILITY SYSTEM ====================
    // Fields for moderation and temporary stamps (all optional for backward compatibility)
    // - status: "active" (default), "hidden", or "removed"
    // - availableFrom/Until: For future event stamps (not used in MVP, but ready to scale)
    // - removalReason: Audit trail for moderation
    // ===========================================================
    
    /// Visibility status - defaults to "active" if nil
    let status: String?
    
    /// When stamp becomes visible (for future events) - nil means always visible
    let availableFrom: Date?
    
    /// When stamp expires (for temporary events) - nil means never expires
    let availableUntil: Date?
    
    /// Why stamp was removed (audit trail for moderation)
    let removalReason: String?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// Check if this stamp requires a location to claim
    var requiresLocation: Bool {
        return latitude != 0.0 || longitude != 0.0
    }
    
    /// Check if this is the special welcome stamp
    var isWelcomeStamp: Bool {
        return id == "your-first-stamp"
    }
    
    /// Check if stamp should be visible right now (respects status and date range)
    /// - Returns: true if stamp is currently available to collect
    /// - Note: This does NOT affect collected stamps - users keep what they collected
    var isCurrentlyAvailable: Bool {
        // Check status (default to "active" if nil for backward compatibility)
        let currentStatus = status ?? "active"
        guard currentStatus == "active" else {
            return false // Hidden or removed
        }
        
        // For MVP: Date checks are ready but optional (no event stamps yet)
        let now = Date()
        
        // Check if not yet available (future event)
        if let from = availableFrom, now < from {
            return false
        }
        
        // Check if expired (past event)
        if let until = availableUntil, now > until {
            return false
        }
        
        return true
    }
    
    /// Extract storage path from Firebase Storage URL
    /// Converts: https://firebasestorage.googleapis.com/v0/b/bucket/o/stamps%2Ffile.jpg?alt=media
    /// To: stamps/file.jpg
    var imageStoragePath: String? {
        guard let imageUrl = imageUrl,
              let url = URL(string: imageUrl),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = components.path.components(separatedBy: "/o/").last?.components(separatedBy: "?").first else {
            return nil
        }
        
        // URL decode the path (e.g., %2F -> /)
        return path.removingPercentEncoding
    }
    
    // Parse city and country from address
    var cityCountry: String {
        let lines = address.components(separatedBy: "\n")
        if lines.count >= 2 {
            // Second line typically has format: "San Francisco, CA, USA 94129"
            let secondLine = lines[1]
            // Split by comma to get parts
            let parts = secondLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3 {
                // Get city (first part) and country (third part before zip code)
                let city = parts[0]
                let countryPart = parts[2].components(separatedBy: " ").first ?? parts[2]
                return "\(city), \(countryPart)"
            } else if parts.count >= 2 {
                // Fallback to just city and state/country
                return "\(parts[0]), \(parts[1])"
            }
        }
        return "Location not included"
    }
    
    // For backward compatibility with JSON that uses collectionId
    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, address, imageName, imageUrl, about, thingsToDoFromEditors, geohash
        case collectionIds
        case collectionId
        // Visibility system
        case status, availableFrom, availableUntil, removalReason
    }
    
    init(id: String, name: String, latitude: Double, longitude: Double, address: String, 
         imageName: String = "", imageUrl: String? = nil, collectionIds: [String], 
         about: String, thingsToDoFromEditors: [String] = [], geohash: String? = nil,
         status: String? = nil, availableFrom: Date? = nil, 
         availableUntil: Date? = nil, removalReason: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.imageName = imageName
        self.imageUrl = imageUrl
        self.collectionIds = collectionIds
        self.about = about
        self.thingsToDoFromEditors = thingsToDoFromEditors
        self.geohash = geohash
        self.status = status
        self.availableFrom = availableFrom
        self.availableUntil = availableUntil
        self.removalReason = removalReason
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        address = try container.decode(String.self, forKey: .address)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName) ?? ""  // Optional for backward compatibility
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        about = try container.decode(String.self, forKey: .about)
        thingsToDoFromEditors = try container.decodeIfPresent([String].self, forKey: .thingsToDoFromEditors) ?? []
        geohash = try container.decodeIfPresent(String.self, forKey: .geohash)
        
        // Visibility system fields (optional for backward compatibility)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        availableFrom = try container.decodeIfPresent(Date.self, forKey: .availableFrom)
        availableUntil = try container.decodeIfPresent(Date.self, forKey: .availableUntil)
        removalReason = try container.decodeIfPresent(String.self, forKey: .removalReason)
        
        // Support both collectionIds (array) and collectionId (string) for backward compatibility
        if let ids = try? container.decode([String].self, forKey: .collectionIds) {
            collectionIds = ids
        } else if let id = try? container.decode(String.self, forKey: .collectionId) {
            collectionIds = [id]
        } else {
            collectionIds = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(address, forKey: .address)
        try container.encode(imageName, forKey: .imageName)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encode(collectionIds, forKey: .collectionIds)
        try container.encode(about, forKey: .about)
        try container.encode(thingsToDoFromEditors, forKey: .thingsToDoFromEditors)
        try container.encodeIfPresent(geohash, forKey: .geohash)
        
        // Visibility system fields
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(availableFrom, forKey: .availableFrom)
        try container.encodeIfPresent(availableUntil, forKey: .availableUntil)
        try container.encodeIfPresent(removalReason, forKey: .removalReason)
    }
}

