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
            .overlay(alignment: .top) {
                // Toast for comment errors
                if let errorMessage = commentManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
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
                
                // Show user-friendly error message
                await MainActor.run {
                    commentManager.errorMessage = "Couldn't post comment. Try again."
                    
                    // Clear message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            if commentManager.errorMessage == "Couldn't post comment. Try again." {
                                commentManager.errorMessage = nil
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func deleteComment(_ comment: Comment) {
        guard let commentId = comment.id else {
            print("⚠️ Cannot delete comment - commentId is nil")
            return
        }
        
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
    @State private var selectedUserId: IdentifiableString?
    @State private var showingMenu = false
    @State private var showingReportSheet = false
    
    private var isOwnComment: Bool {
        guard let currentUserId = currentUserId else { return false }
        return comment.userId == currentUserId
    }
    
    private var isOwnPost: Bool {
        guard let currentUserId = currentUserId else { return false }
        return postOwnerId == currentUserId
    }
    
    private var canDelete: Bool {
        // User can delete their own comments or comments on their own post
        return isOwnComment || isOwnPost
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Profile picture - tappable to navigate to profile
            Button(action: {
                selectedUserId = IdentifiableString(value: comment.userId)
            }) {
                ProfileImageView(
                    avatarUrl: comment.userAvatarUrl,
                    userId: comment.userId,
                    size: 36
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Comment content
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.userDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(comment.createdAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // For your own comments: show both delete icon AND triple dot
            if isOwnComment {
                HStack(spacing: 12) {
                    // Triple dot menu (just for consistency/future options)
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Direct delete button for quick access
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            // For other people's comments
            else {
                Menu {
                    // Delete option (only if it's your post)
                    if isOwnPost {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    
                    // Report option (always available for others' comments)
                    Button(action: { showingReportSheet = true }) {
                        Label("Report", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .sheet(item: $selectedUserId) { identifiableString in
            UserProfileView(userId: identifiableString.value, username: comment.userUsername, displayName: comment.userDisplayName)
        }
        .sheet(isPresented: $showingReportSheet) {
            SimpleCommentReportView(
                commentId: comment.id ?? "",
                commentText: comment.text,
                commentAuthorUsername: comment.userUsername,
                commentAuthorId: comment.userId
            )
        }
    }
}

// MARK: - Helper Types

/// Wrapper to make String identifiable for sheet presentation
struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - Date Extension for "time ago" display

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Comment Report View

/// Simple comment report view - For reporting comments (spam, inappropriate content, etc.)
struct SimpleCommentReportView: View {
    let commentId: String
    let commentText: String
    let commentAuthorUsername: String
    let commentAuthorId: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var reportText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reportText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if reportText.isEmpty {
                    Text("Tell us what's wrong (this is spam, inappropriate content, harassment, etc.).")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Report comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendCommentReport) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your report!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendCommentReport() {
        let trimmedText = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase with reported comment info (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                let reportMessage = """
                Reported Comment by @\(commentAuthorUsername) (ID: \(commentAuthorId))
                Comment ID: \(commentId)
                
                Comment Text:
                "\(commentText)"
                
                Report:
                \(trimmedText)
                """
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Comment Report",
                    message: reportMessage
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Failed to send report. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

