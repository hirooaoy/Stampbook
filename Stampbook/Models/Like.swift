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
    
    init(userId: String, postId: String, stampId: String, postOwnerId: String, createdAt: Date = Date()) {
        // Note: @DocumentID is managed by Firebase - it will be nil until document is saved
        self.userId = userId
        self.postId = postId
        self.stampId = stampId
        self.postOwnerId = postOwnerId
        self.createdAt = createdAt
    }
}

