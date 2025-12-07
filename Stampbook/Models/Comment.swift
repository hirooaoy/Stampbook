import Foundation
import FirebaseFirestore

/// Represents a comment on a collected stamp post
struct Comment: Codable, Identifiable, Equatable {
    var id: String?  // ✅ BEST PRACTICE: We manage the ID ourselves (not @DocumentID)
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
    
    // Like count for this comment
    let likeCount: Int
    
    // Temporary ID for optimistic UI updates (not stored in Firebase)
    private let tempId: String
    
    // Coding keys to exclude tempId from Firebase encoding
    enum CodingKeys: String, CodingKey {
        case id, userId, postId, stampId, postOwnerId, text, createdAt
        case userDisplayName, userUsername, userAvatarUrl, mentionedUserIds, parentCommentId, likeCount
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
         likeCount: Int = 0,
         createdAt: Date = Date(), 
         id: String? = nil,  // ✅ BEST PRACTICE: Pass Firebase ID directly
         tempId: String = UUID().uuidString) {
        // ✅ BEST PRACTICE: Set ID directly (no @DocumentID annotation)
        self.id = id
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
        self.likeCount = likeCount
        self.createdAt = createdAt
        self.tempId = tempId
    }
    
    // Custom decoder to handle tempId (not stored in Firebase)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // ✅ BEST PRACTICE: Decode ID as regular field (no @DocumentID magic)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        
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
        self.likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0 // Default to 0 for backwards compatibility
        
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
               lhs.parentCommentId == rhs.parentCommentId &&
               lhs.likeCount == rhs.likeCount
    }
}

