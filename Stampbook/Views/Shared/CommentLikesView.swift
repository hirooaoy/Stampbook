import SwiftUI

/// View for displaying list of users who liked a comment
struct CommentLikesView: View {
    let commentId: String
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    @State private var users: [UserProfile] = []
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss
    
    init(commentId: String) {
        self.commentId = commentId
        print("🏗️ [CommentLikesView] init() called for commentId: \(commentId)")
    }
    
    var body: some View {
        print("🎨 [CommentLikesView] body rendering - isLoading: \(isLoading), users count: \(users.count)")
        return content
    }
    
    private var content: some View {
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
                                    CommentLikeUserRow(user: user)
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
                    Button(action: {
                        print("👆 [CommentLikesView] Done button tapped")
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            .onAppear {
                print("✅ [CommentLikesView] onAppear fired")
                loadLikes()
            }
            .toolbar(.visible, for: .tabBar)
        }
    }
    
    private func loadLikes() {
        print("👆 [CommentLikesView] loadLikes() called for commentId: \(commentId)")
        isLoading = true
        Task {
            do {
                print("📡 [CommentLikesView] Fetching comment likes from Firebase...")
                let fetchedUsers = try await FirebaseService.shared.fetchCommentLikes(commentId: commentId)
                
                print("✅ [CommentLikesView] Fetched \(fetchedUsers.count) users who liked the comment")
                
                await MainActor.run {
                    users = fetchedUsers
                    isLoading = false
                    print("🎨 [CommentLikesView] Updated UI with \(fetchedUsers.count) users")
                }
            } catch {
                print("⚠️ [CommentLikesView] Failed to fetch comment likes: \(error.localizedDescription)")
                print("⚠️ [CommentLikesView] Error details: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

/// Row view for a user in the comment likes list (simplified, no follow button)
struct CommentLikeUserRow: View {
    let user: UserProfile
    @EnvironmentObject var authManager: AuthManager
    
    var isCurrentUser: Bool {
        authManager.userId == user.id
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
        }
    }
}

#Preview {
    NavigationStack {
        CommentLikesView(commentId: "testCommentId")
            .environmentObject(AuthManager())
            .environmentObject(ProfileManager())
    }
}

