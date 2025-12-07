import Foundation
import FirebaseFirestore

/// Represents a like on a comment
struct CommentLike: Codable, Identifiable {
    @DocumentID var id: String?
    let userId: String // User who liked the comment
    let commentId: String // ID of the comment being liked
    let postId: String // Format: "{userId}-{stampId}"
    let stampId: String
    let commentOwnerId: String // User who wrote the comment being liked
    let createdAt: Date
    
    init(userId: String, commentId: String, postId: String, stampId: String, commentOwnerId: String, createdAt: Date = Date()) {
        // Note: @DocumentID is managed by Firebase - it will be nil until document is saved
        self.userId = userId
        self.commentId = commentId
        self.postId = postId
        self.stampId = stampId
        self.commentOwnerId = commentOwnerId
        self.createdAt = createdAt
    }
}

