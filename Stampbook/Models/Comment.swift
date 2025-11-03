import Foundation
import FirebaseFirestore

/// Represents a comment on a collected stamp post
struct Comment: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String
    let postId: String // Format: "{userId}-{stampId}"
    let stampId: String
    let postOwnerId: String // User who owns the post being commented on
    let text: String
    let createdAt: Date
    
    // User info (denormalized for performance)
    let userDisplayName: String
    let userUsername: String
    let userAvatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case postId
        case stampId
        case postOwnerId
        case text
        case createdAt
        case userDisplayName
        case userUsername
        case userAvatarUrl
    }
    
    init(id: String? = nil, userId: String, postId: String, stampId: String, postOwnerId: String, text: String, 
         userDisplayName: String, userUsername: String, userAvatarUrl: String?, 
         createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.postId = postId
        self.stampId = stampId
        self.postOwnerId = postOwnerId
        self.text = text
        self.userDisplayName = userDisplayName
        self.userUsername = userUsername
        self.userAvatarUrl = userAvatarUrl
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        postId = try container.decode(String.self, forKey: .postId)
        stampId = try container.decode(String.self, forKey: .stampId)
        postOwnerId = try container.decode(String.self, forKey: .postOwnerId)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        userDisplayName = try container.decode(String.self, forKey: .userDisplayName)
        userUsername = try container.decode(String.self, forKey: .userUsername)
        userAvatarUrl = try container.decodeIfPresent(String.self, forKey: .userAvatarUrl)
    }
}

