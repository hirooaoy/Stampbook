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
    
    init(userId: String, postId: String, stampId: String, postOwnerId: String, text: String, 
         userDisplayName: String, userUsername: String, userAvatarUrl: String?, 
         createdAt: Date = Date()) {
        // Note: @DocumentID is managed by Firebase - it will be nil until document is saved
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
}

