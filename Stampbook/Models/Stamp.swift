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
    let notesFromOthers: [String]
    let thingsToDoFromEditors: [String]
    let geohash: String? // Optional for backward compatibility
    
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
        case id, name, latitude, longitude, address, imageName, imageUrl, about, notesFromOthers, thingsToDoFromEditors, geohash
        case collectionIds
        case collectionId
    }
    
    init(id: String, name: String, latitude: Double, longitude: Double, address: String, imageName: String = "", imageUrl: String? = nil, collectionIds: [String], about: String, notesFromOthers: [String], thingsToDoFromEditors: [String] = [], geohash: String? = nil) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.imageName = imageName
        self.imageUrl = imageUrl
        self.collectionIds = collectionIds
        self.about = about
        self.notesFromOthers = notesFromOthers
        self.thingsToDoFromEditors = thingsToDoFromEditors
        self.geohash = geohash
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
        notesFromOthers = try container.decode([String].self, forKey: .notesFromOthers)
        thingsToDoFromEditors = try container.decodeIfPresent([String].self, forKey: .thingsToDoFromEditors) ?? []
        geohash = try container.decodeIfPresent(String.self, forKey: .geohash)
        
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
        try container.encode(notesFromOthers, forKey: .notesFromOthers)
        try container.encode(thingsToDoFromEditors, forKey: .thingsToDoFromEditors)
        try container.encodeIfPresent(geohash, forKey: .geohash)
    }
}

