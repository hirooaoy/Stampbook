import Foundation
import FirebaseFirestore

/// Represents a like on a collected stamp post
struct Like: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let postId: String // Format: "{userId}-{stampId}"
    let stampId: String
    let postOwnerId: String // User who owns the post being liked
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case postId
        case stampId
        case postOwnerId
        case createdAt
    }
    
    init(userId: String, postId: String, stampId: String, postOwnerId: String, createdAt: Date = Date()) {
        self.userId = userId
        self.postId = postId
        self.stampId = stampId
        self.postOwnerId = postOwnerId
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        postId = try container.decode(String.self, forKey: .postId)
        stampId = try container.decode(String.self, forKey: .stampId)
        postOwnerId = try container.decode(String.self, forKey: .postOwnerId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

