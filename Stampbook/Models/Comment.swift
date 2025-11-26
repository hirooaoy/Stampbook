import Foundation
import FirebaseFirestore

/// Represents a comment on a collected stamp post
struct Comment: Codable, Identifiable, Equatable {
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
    
    // @mentions feature - stores userIds of users mentioned in comment
    // Format: ["userId1", "userId2"] - max 3 mentions per comment
    let mentionedUserIds: [String]?
    
    // Reply threading - stores parent comment ID for replies
    // nil = top-level comment, non-nil = reply to another comment
    let parentCommentId: String?
    
    // Temporary ID for optimistic UI updates (not stored in Firebase)
    private let tempId: String
    
    // Coding keys to exclude tempId from Firebase encoding
    enum CodingKeys: String, CodingKey {
        case id, userId, postId, stampId, postOwnerId, text, createdAt
        case userDisplayName, userUsername, userAvatarUrl, mentionedUserIds, parentCommentId
    }
    
    // Computed ID that uses tempId if Firebase ID is nil
    // This ensures ForEach always has unique IDs even for optimistic comments
    var computedId: String {
        return id ?? tempId
    }
    
    init(userId: String, postId: String, stampId: String, postOwnerId: String, text: String, 
         userDisplayName: String, userUsername: String, userAvatarUrl: String?, 
         mentionedUserIds: [String]? = nil,
         parentCommentId: String? = nil,
         createdAt: Date = Date(), tempId: String = UUID().uuidString) {
        // Note: @DocumentID is managed by Firebase - it will be nil until document is saved
        self.userId = userId
        self.postId = postId
        self.stampId = stampId
        self.postOwnerId = postOwnerId
        self.text = text
        self.userDisplayName = userDisplayName
        self.userUsername = userUsername
        self.userAvatarUrl = userAvatarUrl
        self.mentionedUserIds = mentionedUserIds
        self.parentCommentId = parentCommentId
        self.createdAt = createdAt
        self.tempId = tempId
    }
    
    // Custom decoder to handle tempId (not stored in Firebase)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ✅ FIX: Manually decode @DocumentID before decoding other fields
        // This ensures the id is populated from Firebase document
        self._id = try DocumentID<String>(from: decoder)
        
        // Decode all Firebase fields
        self.userId = try container.decode(String.self, forKey: .userId)
        self.postId = try container.decode(String.self, forKey: .postId)
        self.stampId = try container.decode(String.self, forKey: .stampId)
        self.postOwnerId = try container.decode(String.self, forKey: .postOwnerId)
        self.text = try container.decode(String.self, forKey: .text)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.userDisplayName = try container.decode(String.self, forKey: .userDisplayName)
        self.userUsername = try container.decode(String.self, forKey: .userUsername)
        self.userAvatarUrl = try container.decodeIfPresent(String.self, forKey: .userAvatarUrl)
        self.mentionedUserIds = try container.decodeIfPresent([String].self, forKey: .mentionedUserIds)
        self.parentCommentId = try container.decodeIfPresent(String.self, forKey: .parentCommentId)
        
        // Generate a temp ID (won't be used since Firebase comments have real IDs)
        self.tempId = UUID().uuidString
    }
    
    // MARK: - Equatable
    
    // Custom Equatable implementation to compare based on meaningful fields
    static func == (lhs: Comment, rhs: Comment) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userId == rhs.userId &&
               lhs.postId == rhs.postId &&
               lhs.text == rhs.text &&
               lhs.parentCommentId == rhs.parentCommentId
    }
}

