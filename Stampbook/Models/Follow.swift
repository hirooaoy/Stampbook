import Foundation
import FirebaseFirestore

/// Represents a follow relationship between two users
/// Stored in subcollections: users/{userId}/followers and users/{userId}/following
struct Follow: Codable, Identifiable {
    var id: String // The userId of the other person (followerId or followingId)
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
    }
    
    init(id: String, createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        // Handle Timestamp conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
    }
}

