import Foundation
import Combine

/// Manages deep linking from push notifications and other external sources
/// Centralizes navigation logic to handle notification banner taps
class DeepLinkManager: ObservableObject {
    @Published var pendingDeepLink: DeepLink?
    
    enum DeepLink: Identifiable, Equatable {
        case post(postId: String, commentId: String?)
        case profile(userId: String)
        
        var id: String {
            switch self {
            case .post(let postId, _):
                return "post_\(postId)"
            case .profile(let userId):
                return "profile_\(userId)"
            }
        }
        
        static func == (lhs: DeepLink, rhs: DeepLink) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    /// Handle notification tap for post (like, comment, mention, commentLike)
    func handlePostNotification(postId: String, commentId: String? = nil) {
        Logger.info("🔗 [DeepLink] Handling post notification: postId=\(postId), commentId=\(commentId ?? "nil")", category: "DeepLinkManager")
        pendingDeepLink = .post(postId: postId, commentId: commentId)
    }
    
    /// Handle notification tap for profile (follow)
    func handleProfileNotification(userId: String) {
        Logger.info("🔗 [DeepLink] Handling profile notification: userId=\(userId)", category: "DeepLinkManager")
        pendingDeepLink = .profile(userId: userId)
    }
    
    /// Clear the pending deep link after it's been handled
    func clearPendingDeepLink() {
        Logger.debug("🔗 [DeepLink] Clearing pending deep link")
        pendingDeepLink = nil
    }
}

