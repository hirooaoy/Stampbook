import SwiftUI

/// View for displaying and adding comments on a post
struct CommentView: View {
    let postId: String
    let postOwnerId: String
    let stampId: String
    @ObservedObject var commentManager: CommentManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    
    @State private var newCommentText: String = ""
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @FocusState private var isTextFieldFocused: Bool
    
    // Changed to directly observe the published property to trigger view updates
    private var comments: [Comment] {
        commentManager.comments[postId] ?? []
    }
    
    private var isLoading: Bool {
        commentManager.isLoading[postId] ?? false
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                if isLoading && comments.isEmpty {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading comments...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comments.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "message")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No comments yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Be the first to comment!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Comments list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments) { comment in
                                CommentRow(
                                    comment: comment,
                                    currentUserId: authManager.userId,
                                    postOwnerId: postOwnerId,
                                    onDelete: {
                                        commentToDelete = comment
                                        showingDeleteAlert = true
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                
                Divider()
                
                // Comment input
                if authManager.isSignedIn {
                    HStack(spacing: 12) {
                        // Profile picture
                        ProfileImageView(
                            avatarUrl: profileManager.currentUserProfile?.avatarUrl,
                            userId: authManager.userId ?? "",
                            size: 36
                        )
                        
                        // Text field
                        TextField("Add a comment...", text: $newCommentText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .focused($isTextFieldFocused)
                            .lineLimit(1...5)
                        
                        // Send button
                        Button(action: {
                            sendComment()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Fetch comments when view appears
                Task {
                    await commentManager.fetchComments(postId: postId)
                }
            }
            .alert("Delete Comment", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let comment = commentToDelete {
                        deleteComment(comment)
                    }
                }
            } message: {
                Text("Are you sure you want to delete this comment?")
            }
        }
    }
    
    private func sendComment() {
        let trimmedText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let userId = authManager.userId else { return }
        
        // Get current user profile for comment metadata
        Task {
            do {
                let userProfile = try await FirebaseService.shared.fetchUserProfile(userId: userId)
                
                await MainActor.run {
                    // Add comment with optimistic update
                    commentManager.addComment(
                        postId: postId,
                        stampId: stampId,
                        postOwnerId: postOwnerId,
                        userId: userId,
                        text: trimmedText,
                        userProfile: userProfile
                    )
                    
                    // Clear input
                    newCommentText = ""
                    isTextFieldFocused = false
                }
            } catch {
                print("⚠️ Failed to fetch user profile for comment: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id else {
            print("❌ Cannot delete comment - commentId is nil")
            return
        }
        
        print("🗑️ CommentView: Deleting comment \(commentId)")
        print("   PostId: \(postId)")
        print("   PostOwnerId: \(postOwnerId)")
        print("   StampId: \(stampId)")
        
        commentManager.deleteComment(
            commentId: commentId,
            postId: postId,
            postOwnerId: postOwnerId,
            stampId: stampId
        )
    }
}

/// Row view for a single comment
struct CommentRow: View {
    let comment: Comment
    let currentUserId: String?
    let postOwnerId: String
    let onDelete: () -> Void
    
    private var canDelete: Bool {
        // User can delete their own comments or comments on their own post
        guard let currentUserId = currentUserId else { return false }
        return comment.userId == currentUserId || postOwnerId == currentUserId
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile picture
            ProfileImageView(
                avatarUrl: comment.userAvatarUrl,
                userId: comment.userId,
                size: 36
            )
            
            // Comment content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.userDisplayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    // Delete button (only for comment owner or post owner)
                    if canDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(comment.createdAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Date Extension for "time ago" display

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

