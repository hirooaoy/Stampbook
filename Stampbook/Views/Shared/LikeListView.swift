import SwiftUI

/// View for displaying list of users who liked a post
/// TODO: POST-MVP - Add pagination for scalability (load more as user scrolls)
/// TODO: POST-MVP - Add search bar when posts regularly get 50+ likes
struct LikeListView: View {
    let postId: String
    let postOwnerId: String
    
    @EnvironmentObject var followManager: FollowManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var users: [UserProfile] = []
    @State private var isLoading = true  // Start loading immediately to show spinner
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // List of users
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if users.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "heart")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No likes yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Be the first to like!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(users) { user in
                                NavigationLink(destination: UserProfileView(userId: user.id, username: user.username, displayName: user.displayName)) {
                                    LikeUserRow(user: user)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Likes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadLikes()
            }
        }
    }
    
    private func loadLikes() {
        isLoading = true
        Task {
            do {
                // Fetch all users who liked this post (no limit for MVP scale)
                // At 100-user MVP scale, posts will typically have 0-20 likes
                let fetchedUsers = try await FirebaseService.shared.fetchPostLikes(postId: postId)
                
                await MainActor.run {
                    users = fetchedUsers
                    isLoading = false
                }
                
                // Batch check follow statuses for all users who liked this post
                if let currentUserId = authManager.userId {
                    let userIds = fetchedUsers.map { $0.id }
                    await followManager.checkFollowStatuses(currentUserId: currentUserId, targetUserIds: userIds)
                }
            } catch {
                print("⚠️ Failed to fetch likes: \(error.localizedDescription)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

/// Row view for a user in the likes list
struct LikeUserRow: View {
    let user: UserProfile
    @EnvironmentObject var followManager: FollowManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var showUnfollowConfirmation = false
    
    var isCurrentUser: Bool {
        authManager.userId == user.id
    }
    
    var isFollowing: Bool {
        followManager.isFollowing[user.id] ?? false
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture with caching
            ProfileImageView(
                avatarUrl: user.avatarUrl,
                userId: user.id,
                size: 48
            )
            
            // Name and username
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Follow button (don't show for current user)
            if !isCurrentUser {
                Button(action: {
                    guard let currentUserId = authManager.userId else { return }
                    if isFollowing {
                        // Show confirmation for unfollow
                        showUnfollowConfirmation = true
                    } else {
                        // Follow immediately without confirmation
                        followManager.toggleFollow(currentUserId: currentUserId, targetUserId: user.id, profileManager: profileManager)
                    }
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(isFollowing ? .primary : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(isFollowing ? Color(.systemGray5) : Color.blue)
                        .cornerRadius(8)
                }
                .alert("Unfollow \(user.displayName)?", isPresented: $showUnfollowConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Unfollow", role: .destructive) {
                        guard let currentUserId = authManager.userId else { return }
                        followManager.toggleFollow(currentUserId: currentUserId, targetUserId: user.id, profileManager: profileManager)
                    }
                } message: {
                    Text("Are you sure you want to unfollow @\(user.username)?")
                }
            }
        }
        // Removed onAppear check - follow statuses are now batch loaded when fetching the list
    }
}

#Preview {
    NavigationStack {
        LikeListView(postId: "testUserId-testStampId", postOwnerId: "testUserId")
            .environmentObject(AuthManager())
            .environmentObject(FollowManager())
            .environmentObject(ProfileManager())
    }
}

