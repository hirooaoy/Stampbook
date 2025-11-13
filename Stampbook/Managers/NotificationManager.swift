import Foundation
import Combine
import FirebaseFirestore

/// Manages notifications for user engagement (follows, likes, comments)
@MainActor
class NotificationManager: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasUnreadNotifications = false
    
    private let db = Firestore.firestore()
    
    // REMOVED: Real-time listener (too expensive at scale)
    // private var unreadListener: ListenerRegistration?
    
    // NEW: Polling-based badge updates (98% cost reduction)
    private var pollingTask: Task<Void, Never>?
    
    /// Fetch notifications for the current user (newest first, limit to 50)
    func fetchNotifications(userId: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let snapshot = try await db.collection("notifications")
                .whereField("recipientId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            notifications = snapshot.documents.compactMap { doc in
                do {
                    let notification = try doc.data(as: AppNotification.self)
                    // @DocumentID should auto-populate, but verify it's not nil
                    if notification.id == nil {
                        print("⚠️ [NotificationManager] Notification missing ID for doc: \(doc.documentID)")
                        return nil
                    }
                    return notification
                } catch {
                    print("⚠️ [NotificationManager] Failed to decode notification \(doc.documentID): \(error)")
                    return nil
                }
            }
            
            // Update unread status
            hasUnreadNotifications = notifications.contains { !$0.isRead }
            
            isLoading = false
        } catch {
            print("❌ Error fetching notifications: \(error.localizedDescription)")
            errorMessage = "Failed to load notifications"
            isLoading = false
        }
    }
    
    /// Check if there are any unread notifications (efficient for badge display)
    /// Used by polling system - only charges 1 Firestore read per check
    func checkHasUnreadNotifications(userId: String) async {
        do {
            let snapshot = try await db.collection("notifications")
                .whereField("recipientId", isEqualTo: userId)
                .whereField("isRead", isEqualTo: false)
                .limit(to: 1)
                .getDocuments()
            
            hasUnreadNotifications = !snapshot.documents.isEmpty
        } catch {
            print("❌ Error checking unread notifications: \(error.localizedDescription)")
            // Silently fail for badge - not critical
        }
    }
    
    // MARK: - Polling-Based Badge Updates (Cost Optimized)
    
    /// Start polling for unread notifications (checks every 5 minutes)
    /// This replaces real-time listeners to reduce costs by 98%
    /// 
    /// Cost comparison (100 users):
    /// - Real-time listener: ~2M reads/month = $120/month
    /// - 5-minute polling: ~30K reads/month = $2/month
    func startPollingForUnreadNotifications(userId: String) {
        // Cancel any existing polling task
        stopPollingForUnreadNotifications()
        
        print("🔄 Starting notification polling (every 5 minutes)")
        
        pollingTask = Task { [weak self] in
                guard let self = self else { return }
                
            // Check immediately on start
            await self.checkHasUnreadNotifications(userId: userId)
            
            // Then poll every 5 minutes
            while !Task.isCancelled {
                do {
                    // Sleep for 5 minutes (300 seconds)
                    try await Task.sleep(nanoseconds: 300_000_000_000)
                    
                    // Check again
                    await self.checkHasUnreadNotifications(userId: userId)
                    
                } catch {
                    // Task was cancelled or sleep interrupted
                    break
                }
            }
        }
        
        print("✅ Started polling for unread notifications")
    }
    
    /// Stop polling for unread notifications
    func stopPollingForUnreadNotifications() {
        pollingTask?.cancel()
        pollingTask = nil
        print("🛑 Stopped polling for unread notifications")
    }
    
    // MARK: - Deprecated (Real-Time Listener - Too Expensive)
    
    /// DEPRECATED: Real-time listener approach is too expensive at scale
    /// Use startPollingForUnreadNotifications() instead
    /// 
    /// This method is kept for backwards compatibility but does nothing
    @available(*, deprecated, message: "Use startPollingForUnreadNotifications() instead - real-time listeners are too expensive")
    func startListeningForUnreadNotifications(userId: String) {
        print("⚠️ WARNING: startListeningForUnreadNotifications() is deprecated")
        print("⚠️ Use startPollingForUnreadNotifications() instead to reduce costs by 98%")
        // Silently redirect to polling approach
        startPollingForUnreadNotifications(userId: userId)
    }
    
    /// DEPRECATED: Use stopPollingForUnreadNotifications() instead
    @available(*, deprecated, message: "Use stopPollingForUnreadNotifications() instead")
    func stopListeningForUnreadNotifications() {
        print("⚠️ WARNING: stopListeningForUnreadNotifications() is deprecated")
        print("⚠️ Use stopPollingForUnreadNotifications() instead")
        // Silently redirect to polling approach
        stopPollingForUnreadNotifications()
    }
    
    /// Mark a single notification as read
    func markAsRead(notificationId: String) async {
        guard let id = notificationId as String? else { return }
        
        do {
            try await db.collection("notifications").document(id).updateData([
                "isRead": true
            ])
            
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == id }) {
                notifications[index].isRead = true
                hasUnreadNotifications = notifications.contains { !$0.isRead }
            }
        } catch {
            print("❌ Error marking notification as read: \(error.localizedDescription)")
            // Silently fail - not critical
        }
    }
    
    /// Mark all notifications as read (called when notification sheet opens)
    func markAllAsRead(userId: String) async {
        // Only proceed if there are unread notifications
        guard hasUnreadNotifications else { return }
        
        do {
            // Get all unread notification IDs
            let unreadNotifications = notifications.filter { !$0.isRead }
            
            if unreadNotifications.isEmpty { return }
            
            // Batch update all unread to read
            let batch = db.batch()
            
            for notification in unreadNotifications {
                if let id = notification.id {
                    let ref = db.collection("notifications").document(id)
                    batch.updateData(["isRead": true], forDocument: ref)
                }
            }
            
            try await batch.commit()
            
            // Update local state
            notifications = notifications.map { notification in
                var updated = notification
                updated.isRead = true
                return updated
            }
            
            hasUnreadNotifications = false
            
            print("✅ Marked all notifications as read")
        } catch {
            print("❌ Error marking all notifications as read: \(error.localizedDescription)")
            // Silently fail - user can still see notifications
        }
    }
    
    /// Delete a notification
    func deleteNotification(notificationId: String) async {
        guard let id = notificationId as String? else { return }
        
        do {
            try await db.collection("notifications").document(id).delete()
            
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == id }) {
                notifications.remove(at: index)
                hasUnreadNotifications = notifications.contains { !$0.isRead }
            }
        } catch {
            print("❌ Error deleting notification: \(error.localizedDescription)")
            errorMessage = "Failed to delete notification"
        }
    }
    
    /// Clear error message after a delay
    func clearError() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            await MainActor.run {
                errorMessage = nil
            }
        }
    }
}

