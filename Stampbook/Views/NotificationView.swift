import SwiftUI

/// View displaying user notifications (follows, likes, comments)
struct NotificationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var notificationManager: NotificationManager
    
    @State private var isInitialLoad = true
    @State private var hasFetchedProfiles = false
    @State private var selectedNotificationForProfile: AppNotification?
    @State private var selectedNotificationForPost: AppNotification?
    @State private var actorProfiles: [String: UserProfile] = [:]
    
    var body: some View {
        NavigationStack {
            ZStack {
                if notificationManager.isLoading && isInitialLoad {
                    loadingView
                } else if !hasFetchedProfiles {
                    profileLoadingView
                } else if notificationManager.notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedNotificationForProfile) { notification in
                UserProfileView(
                    userId: notification.actorId,
                    username: actorProfiles[notification.actorId]?.username ?? "",
                    displayName: actorProfiles[notification.actorId]?.displayName ?? ""
                )
            }
            .navigationDestination(item: $selectedNotificationForPost) { notification in
                if let postId = notification.postId {
                    PostDetailView(
                        postId: postId,
                        highlightCommentId: notification.commentId
                    )
                    .onAppear {
                        print("🔔 [NotificationView] Navigating to PostDetailView - postId: \(postId), commentId: \(notification.commentId ?? "NIL")")
                    }
                } else {
                    EmptyView()
                        .onAppear {
                            print("❌ [NotificationView] No postId in notification!")
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .task {
                await loadNotifications()
            }
            .onAppear {
                // ✅ FIX (Dec 5, 2025): Reset navigation state to always start at notification list
                // This prevents the bug where reopening the sheet sometimes starts at PostDetailView
                // instead of the notification list. Safe because:
                // - Doesn't interfere with feed refresh logic (happens in .onDisappear)
                // - Doesn't affect deep links (uses separate DeepLinkManager)
                // - Only clears navigation within this sheet session
                selectedNotificationForProfile = nil
                selectedNotificationForPost = nil
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading notifications...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var profileLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading profiles...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No notifications yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("New notifications will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notificationManager.notifications) { notification in
                    NotificationRow(
                        notification: notification,
                        preFetchedProfile: actorProfiles[notification.actorId],
                    onProfileTap: { selectedNotificationForProfile = notification },
                    onPostTap: { 
                        print("🔔 [NotificationView] Tapped notification - type: \(notification.type), postId: \(notification.postId ?? "NIL"), commentId: \(notification.commentId ?? "NIL")")
                        selectedNotificationForPost = notification 
                    }
                    )
                    .environmentObject(stampsManager)
                    .environmentObject(profileManager)
                    
                    if notification.id != notificationManager.notifications.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func loadNotifications() async {
        guard let userId = authManager.userId else { return }
        
        await notificationManager.fetchNotifications(userId: userId)
        isInitialLoad = false
        
        let uniqueActorIds = Array(Set(notificationManager.notifications.map { $0.actorId }))
        if !uniqueActorIds.isEmpty {
            do {
                let profiles = try await FirebaseService.shared.fetchProfilesBatched(userIds: uniqueActorIds)
                actorProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            } catch {
                print("⚠️ Failed to fetch profiles: \(error)")
            }
        }
        
        hasFetchedProfiles = true
        await notificationManager.markAllAsRead(userId: userId)
    }
}

/// Individual notification row
struct NotificationRow: View {
    let notification: AppNotification
    let preFetchedProfile: UserProfile?
    let onProfileTap: () -> Void
    let onPostTap: () -> Void
    
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var actorProfile: UserProfile?
    @State private var stamp: Stamp?
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onProfileTap) {
                ProfileImageView(
                    avatarUrl: actorProfile?.avatarUrl,
                    userId: notification.actorId,
                    size: 36
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: handleNotificationTap) {
                VStack(alignment: .leading, spacing: 4) {
                    notificationText
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    Text(timeAgoText(from: notification.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .task {
            if let preFetched = preFetchedProfile {
                actorProfile = preFetched
            } else {
                do {
                    actorProfile = try await FirebaseService.shared.fetchUserProfile(userId: notification.actorId)
                } catch {
                    print("❌ Error fetching profile: \(error)")
                }
            }
            
            if let stampId = notification.stampId {
                stamp = await stampsManager.fetchStamps(ids: [stampId], includeRemoved: true).first
            }
        }
    }
    
    @ViewBuilder
    private var notificationText: some View {
        let actorName = actorProfile?.displayName ?? "Someone"
        
        switch notification.type {
        case .follow:
            Text("\(Text(actorName).fontWeight(.semibold)) started following you")
                .font(.subheadline)
                .fontWeight(notification.isRead ? .regular : .medium)
            
        case .like:
            if let stampName = stamp?.name {
                Text("\(Text(actorName).fontWeight(.semibold)) liked your \(Text(stampName).fontWeight(.semibold))")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            } else {
                Text("\(Text(actorName).fontWeight(.semibold)) liked your stamp")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            }
            
        case .comment:
            if let stampName = stamp?.name {
                Text("\(Text(actorName).fontWeight(.semibold)) commented on your \(Text(stampName).fontWeight(.semibold))")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            } else {
                Text("\(Text(actorName).fontWeight(.semibold)) commented on your stamp")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            }
            
        case .mention:
            if let stampName = stamp?.name {
                Text("\(Text(actorName).fontWeight(.semibold)) tagged you in a comment on \(Text(stampName).fontWeight(.semibold))")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            } else {
                Text("\(Text(actorName).fontWeight(.semibold)) tagged you in a comment")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            }
            
        case .commentLike:
            if let stampName = stamp?.name {
                Text("\(Text(actorName).fontWeight(.semibold)) liked your comment on \(Text(stampName).fontWeight(.semibold))")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            } else {
                Text("\(Text(actorName).fontWeight(.semibold)) liked your comment")
                    .font(.subheadline)
                    .fontWeight(notification.isRead ? .regular : .medium)
            }
        }
    }
    
    private func handleNotificationTap() {
        switch notification.type {
        case .follow:
            onProfileTap()
        case .like, .comment, .mention, .commentLike:
            if notification.postId != nil {
                onPostTap()
            }
        }
    }
    
    private func timeAgoText(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        
        if let weeks = components.weekOfYear, weeks > 0 {
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        } else if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}
