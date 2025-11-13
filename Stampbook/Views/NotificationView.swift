import SwiftUI

/// View displaying user notifications (follows, likes, comments)
struct NotificationView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var isInitialLoad = true
    @State private var hasFetchedProfiles = false // NEW: Block rendering until profiles are fetched
    @State private var selectedProfile: (userId: String, profile: UserProfile)?
    @State private var selectedPostId: String?
    @State private var selectedNotificationForProfile: AppNotification?
    @State private var selectedNotificationForPost: AppNotification?
    @State private var actorProfiles: [String: UserProfile] = [:] // Pre-fetched actor profiles (batch optimization)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Content
                if notificationManager.isLoading && isInitialLoad {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading notifications...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !hasFetchedProfiles {
                    // NEW: Loading profiles state (prevents race condition)
                    // This blocks rendering until batch profile fetch completes
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading profiles...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notificationManager.notifications.isEmpty {
                    // Empty state
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
                } else {
                    // Notifications list - only renders AFTER profiles are fetched
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notificationManager.notifications) { notification in
                                NotificationRow(
                                    notification: notification,
                                    preFetchedProfile: actorProfiles[notification.actorId],
                                    onProfileTap: { selectedNotificationForProfile = notification },
                                    onPostTap: { selectedNotificationForPost = notification }
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
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedNotificationForProfile) { notification in
                // Navigate to user profile (UserProfileView will fetch the profile data)
                UserProfileView(
                    userId: notification.actorId,
                    username: "",
                    displayName: ""
                )
            }
            .navigationDestination(item: $selectedNotificationForPost) { notification in
                // Navigate to post detail
                if let postId = notification.postId {
                    PostDetailView(postId: postId)
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
                // Initial load
                if let userId = authManager.userId {
                    await notificationManager.fetchNotifications(userId: userId)
                    isInitialLoad = false
                    
                    // ✅ OPTIMIZATION: Batch fetch all actor profiles
                    // Instead of each notification row fetching individually (50 reads),
                    // we fetch all unique actors in one batch query (~5 reads)
                    let uniqueActorIds = Array(Set(notificationManager.notifications.map { $0.actorId }))
                    
                    if !uniqueActorIds.isEmpty {
                        #if DEBUG
                        print("🔄 [NotificationView] Batch fetching \(uniqueActorIds.count) actor profiles...")
                        let batchStart = CFAbsoluteTimeGetCurrent()
                        #endif
                        
                        do {
                            let profiles = try await FirebaseService.shared.fetchProfilesBatched(userIds: uniqueActorIds)
                            
                            // Store in dictionary for O(1) lookup
                            actorProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
                            
                            #if DEBUG
                            let batchTime = CFAbsoluteTimeGetCurrent() - batchStart
                            
                            // ✅ FIXED: Calculate actual cost savings percentage
                            let oldReads = uniqueActorIds.count
                            let newReads = (uniqueActorIds.count + 9) / 10 // Batch size 10
                            let reduction = oldReads > 0 ? Int(((Double(oldReads - newReads) / Double(oldReads)) * 100)) : 0
                            
                            print("✅ [NotificationView] Batch fetched \(profiles.count) profiles in \(String(format: "%.3f", batchTime))s")
                            print("💰 [NotificationView] Cost savings: \(oldReads) reads → \(newReads) reads (\(reduction)% reduction)")
                            #endif
                        } catch {
                            print("⚠️ [NotificationView] Batch profile fetch failed: \(error.localizedDescription)")
                            // Fallback: Rows will fetch individually (slower but still works)
                        }
                    }
                    
                    // ✅ FIXED: Set flag AFTER batch fetch completes to prevent race condition
                    // This ensures NotificationRows render AFTER actorProfiles is populated
                    hasFetchedProfiles = true
                    
                    // Mark all as read when sheet appears
                    await notificationManager.markAllAsRead(userId: userId)
                }
            }
        }
    }
}

/// Individual notification row
struct NotificationRow: View {
    let notification: AppNotification
    let preFetchedProfile: UserProfile? // ✅ Pre-fetched profile for instant rendering
    let onProfileTap: () -> Void
    let onPostTap: () -> Void
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var actorProfile: UserProfile?
    @State private var stamp: Stamp?
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Actor profile image - always navigates to profile
            Button(action: {
                onProfileTap()
            }) {
                ProfileImageView(
                    avatarUrl: actorProfile?.avatarUrl,
                    userId: notification.actorId,
                    size: 36
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Notification content - navigates based on type
            Button(action: {
                handleNotificationTap()
            }) {
                VStack(alignment: .leading, spacing: 4) {
                    // Main text
                    notificationText
                        .foregroundColor(.primary)
                        .lineLimit(3)
                    
                    // Timestamp
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
            // ✅ OPTIMIZED: Use pre-fetched profile if available (instant rendering)
            if let preFetched = preFetchedProfile {
                actorProfile = preFetched
                #if DEBUG
                print("⚡️ [NotificationRow] Using pre-fetched profile for \(notification.actorId)")
                #endif
            } else {
                // Fallback: Fetch individually (only happens if batch fetch failed)
                #if DEBUG
                print("🐌 [NotificationRow] Fetching profile individually for \(notification.actorId)")
                #endif
            do {
                actorProfile = try await FirebaseService.shared.fetchUserProfile(userId: notification.actorId)
            } catch {
                print("❌ Error fetching actor profile: \(error.localizedDescription)")
                }
            }
            
            // Prefetch stamp data if applicable
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
        }
    }
    
    private func handleNotificationTap() {
        switch notification.type {
        case .follow:
            // Navigate to user profile
            onProfileTap()
            
        case .like, .comment:
            // Navigate to post detail
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

