import Foundation
import FirebaseFirestore

/// Represents a notification for user actions (follow, like, comment)
struct AppNotification: Codable, Identifiable, Hashable {
    @DocumentID var id: String?
    let recipientId: String       // Who receives this notification
    let actorId: String           // Who performed the action
    let type: NotificationType    // Type of notification
    let postId: String?           // For like/comment (nil for follow)
    let stampId: String?          // For like/comment (nil for follow)
    let commentPreview: String?   // Preview text for comments (truncated to 100 chars)
    let createdAt: Date
    var isRead: Bool
    
    init(recipientId: String,
         actorId: String,
         type: NotificationType,
         postId: String? = nil,
         stampId: String? = nil,
         commentPreview: String? = nil,
         createdAt: Date = Date(),
         isRead: Bool = false) {
        // Note: @DocumentID is managed by Firebase - it will be nil until document is saved
        self.recipientId = recipientId
        self.actorId = actorId
        self.type = type
        self.postId = postId
        self.stampId = stampId
        self.commentPreview = commentPreview
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

/// Types of notifications
enum NotificationType: String, Codable, Hashable {
    case follow = "follow"
    case like = "like"
    case comment = "comment"
    // Future types can be added here:
    // case adminMessage = "admin_message"
    // case nearbyStamp = "nearby_stamp"
}

