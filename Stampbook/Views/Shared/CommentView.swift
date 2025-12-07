import SwiftUI

/// View for displaying and adding comments on a post
struct CommentView: View {
    let postId: String
    let postOwnerId: String
    let stampId: String
    @ObservedObject var commentManager: CommentManager
    @ObservedObject var commentLikeManager: CommentLikeManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) var dismiss
    
    @State private var newCommentText: String = ""
    @State private var showingDeleteAlert = false
    @State private var commentToDelete: Comment?
    @State private var selectedUserId: IdentifiableString? // For navigation to user profile
    @State private var showCommentLikes = false
    @State private var selectedCommentId: String? // For showing likes
    @FocusState private var isTextFieldFocused: Bool
    
    // Reply state
    @State private var replyingTo: Comment? = nil
    
    // @mention autocomplete states
    @State private var mentionQuery: String = ""  // Current @mention being typed (e.g., "hir")
    @State private var mentionSuggestions: [UserProfile] = []  // Search results
    @State private var showMentionSuggestions: Bool = false
    @State private var mentionSearchTask: Task<Void, Never>?  // For debouncing
    
    // Changed to directly observe the published property to trigger view updates
    private var comments: [Comment] {
        commentManager.getComments(postId: postId)
    }
    
    private var isLoading: Bool {
        commentManager.isLoading[postId] ?? false
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Comments list
                if comments.isEmpty && isLoading {
                    // Loading state (only show spinner on initial load when no comments cached)
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading comments...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comments.isEmpty {
                    // Empty state
                    VStack {
                        Spacer()
                        
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
                        
                        Spacer()
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Comments list
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments, id: \.computedId) { comment in
                                CommentRow(
                                    comment: comment,
                                    currentUserId: authManager.userId,
                                    postOwnerId: postOwnerId,
                                    onDelete: {
                                        commentToDelete = comment
                                        showingDeleteAlert = true
                                    },
                                    onProfileTap: { userId, username, displayName in
                                        selectedUserId = IdentifiableString(value: userId, username: username, displayName: displayName)
                                    },
                                    onReply: { replyingComment in
                                        replyingTo = replyingComment
                                        newCommentText = "@\(replyingComment.userUsername) "
                                        isTextFieldFocused = true
                                    },
                                    onShowLikes: { commentId in
                                        selectedCommentId = commentId
                                        showCommentLikes = true
                                    },
                                    commentLikeManager: commentLikeManager
                                )
                                .padding(.leading, comment.parentCommentId != nil ? 40 : 0) // Single indent for all replies
                            }
                            
                            // Load More button (if there are more comments)
                            if commentManager.hasMoreComments[postId] == true {
                                Button(action: {
                                    Task {
                                        await commentManager.fetchComments(postId: postId, loadMore: true)
                                        
                                        // Fetch like status for newly loaded comments
                                        if let userId = authManager.userId {
                                            let commentIds = comments.compactMap { $0.id }
                                            await commentLikeManager.fetchLikeStatus(commentIds: commentIds, userId: userId)
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isLoading {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 16))
                                        }
                                        Text(isLoading ? "Loading..." : "Load More Comments")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                                .disabled(isLoading)
                                .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                
                Divider()
                
                // Comment input with mention autocomplete
                if authManager.isSignedIn {
                    ZStack(alignment: .bottom) {
                        // Mention suggestions (appears above TextField)
                        if showMentionSuggestions && !mentionSuggestions.isEmpty {
                            MentionSuggestionsView(
                                suggestions: mentionSuggestions,
                                onSelect: { selectedProfile in
                                    insertMention(selectedProfile.username)
                                }
                            )
                            .padding(.bottom, 60)  // Offset above TextField
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                        // Comment input
                        HStack(spacing: 12) {
                            // Profile picture
                            ProfileImageView(
                                avatarUrl: profileManager.currentUserProfile?.avatarUrl,
                                userId: authManager.userId ?? "",
                                size: 36
                            )
                            
                            // Text field (simple, no overlay)
                            TextField("Add a comment...", text: $newCommentText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .focused($isTextFieldFocused)
                                .lineLimit(1...5)
                                .onChange(of: newCommentText) { oldValue, newValue in
                                    detectMention(in: newValue)
                                }
                            
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
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
            // ✅ FIXED: Navigation destination moved outside LazyVStack (was causing SwiftUI warning)
            // Placed on NavigationStack content (VStack) to prevent "navigationDestination inside lazy container" warning
            .navigationDestination(item: $selectedUserId) { identifiableUser in
                UserProfileView(
                    userId: identifiableUser.value,
                    username: identifiableUser.username,
                    displayName: identifiableUser.displayName
                )
            }
            .onAppear {
                // Fetch comments when view appears (initial load)
                Task {
                    await commentManager.fetchComments(postId: postId, loadMore: false)
                    
                    // Fetch like status for all comments
                    if let userId = authManager.userId {
                        let commentIds = comments.compactMap { $0.id }
                        await commentLikeManager.fetchLikeStatus(commentIds: commentIds, userId: userId)
                    }
                }
            }
            .alert(commentToDelete?.userId == authManager.userId ? "Delete Comment" : "Remove Comment", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button(commentToDelete?.userId == authManager.userId ? "Delete" : "Remove", role: .destructive) {
                    if let comment = commentToDelete {
                        deleteComment(comment)
                    }
                }
            } message: {
                Text(commentToDelete?.userId == authManager.userId ? "Are you sure you want to delete this comment?" : "Are you sure you want to remove this comment?")
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
            .toolbar(.visible, for: .tabBar)
        }
        .sheet(isPresented: $showCommentLikes) {
            if let commentId = selectedCommentId {
                CommentLikesView(commentId: commentId)
                    .environmentObject(authManager)
                    .environmentObject(profileManager)
            }
        }
    }
    
    private func sendComment() {
        let trimmedText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let userId = authManager.userId else { return }
        
        // ✅ OPTIMIZATION: Use cached profile from ProfileManager (saves 1 Firebase read per comment)
        // ProfileManager already has current user's profile loaded - no need to fetch again
        guard let userProfile = profileManager.currentUserProfile else {
            print("⚠️ Cannot post comment - current user profile not loaded")
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
            return
        }
        
                    // Add comment with optimistic update
                    commentManager.addComment(
                        postId: postId,
                        stampId: stampId,
                        postOwnerId: postOwnerId,
                        userId: userId,
                        text: trimmedText,
                        userProfile: userProfile,
                        parentCommentId: replyingTo?.id
                    )
                    
                    // Clear input and reply state
                    newCommentText = ""
                    replyingTo = nil
                    isTextFieldFocused = false
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
    
    // MARK: - @Mention Autocomplete
    
    /// Detects if user is typing an @mention and triggers search
    private func detectMention(in text: String) {
        // Find the last @ symbol in the text
        guard let lastAtIndex = text.lastIndex(of: "@") else {
            // No @ symbol - hide suggestions
            showMentionSuggestions = false
            mentionQuery = ""
            mentionSearchTask?.cancel()
            return
        }
        
        // Get text after the last @
        let afterAt = String(text[text.index(after: lastAtIndex)...])
        
        // Check if there's a space after @ (means mention is complete)
        if afterAt.contains(" ") {
            showMentionSuggestions = false
            mentionQuery = ""
            mentionSearchTask?.cancel()
            return
        }
        
        // Valid mention query (no spaces, still typing)
        let query = afterAt.trimmingCharacters(in: .whitespacesAndNewlines)
        mentionQuery = query
        
        // Cancel previous search
        mentionSearchTask?.cancel()
        
        // Debounce search (wait 300ms after user stops typing)
        mentionSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
            
            if !Task.isCancelled {
                await searchUsers(query: query)
            }
        }
    }
    
    /// Search for users matching the mention query
    private func searchUsers(query: String) async {
        // If query is empty, search all users (show recent/popular)
        // If query has text, search by username or displayName
        
        do {
            let results = try await FirebaseService.shared.searchUsers(
                query: query,
                limit: 5
            )
            
            await MainActor.run {
                mentionSuggestions = results
                showMentionSuggestions = !results.isEmpty
            }
        } catch {
            print("⚠️ Failed to search users for mention: \(error.localizedDescription)")
            await MainActor.run {
                mentionSuggestions = []
                showMentionSuggestions = false
            }
        }
    }
    
    /// Insert selected username into comment text
    private func insertMention(_ username: String) {
        // Find the last @ symbol
        guard let lastAtIndex = newCommentText.lastIndex(of: "@") else {
            return
        }
        
        // Replace from @ to cursor with @username + space
        let beforeAt = String(newCommentText[..<lastAtIndex])
        newCommentText = beforeAt + "@\(username) "
        
        // Hide suggestions
        showMentionSuggestions = false
        mentionQuery = ""
        mentionSearchTask?.cancel()
        
        // Keep keyboard focused
        isTextFieldFocused = true
    }
}

/// Row view for a single comment
struct CommentRow: View {
    let comment: Comment
    let currentUserId: String?
    let postOwnerId: String
    let onDelete: () -> Void
    let onProfileTap: (String, String, String) -> Void // (userId, username, displayName)
    let onReply: (Comment) -> Void // Callback for reply button
    let onShowLikes: (String) -> Void // Show likes sheet for this comment
    @ObservedObject var commentLikeManager: CommentLikeManager
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
    
    // ✅ FIX: Disable delete for optimistic comments (not yet saved to Firebase)
    private var isOptimisticComment: Bool {
        return comment.id == nil
    }
    
    // Like state
    private var isLiked: Bool {
        guard let commentId = comment.id else { return false }
        return commentLikeManager.isLiked(commentId: commentId)
    }
    
    private var currentLikeCount: Int {
        guard let commentId = comment.id else { return 0 }
        if commentLikeManager.hasCountData(commentId: commentId) {
            return commentLikeManager.getLikeCount(commentId: commentId)
        } else {
            return comment.likeCount
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile picture - tappable to navigate to profile
            Button(action: {
                onProfileTap(comment.userId, comment.userUsername, comment.userDisplayName)
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
                
                // Display comment text with @mentions highlighted in blue
                Text(formatCommentWithMentions(comment.text))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Timestamp • Likes • Reply
                HStack(spacing: 4) {
                    Text(comment.createdAt.timeAgoDisplay())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !isOptimisticComment {
                        // Show likes if count > 0
                        if currentLikeCount > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                if let commentId = comment.id {
                                    onShowLikes(commentId)
                                }
                            }) {
                                Text("\(currentLikeCount) \(currentLikeCount == 1 ? "like" : "likes")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            onReply(comment)
                        }) {
                            Text("Reply")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            Spacer()
            
            // Show loading indicator for optimistic comments, heart + menu for saved comments
            if isOptimisticComment {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 24, height: 24)
            } else {
                HStack(spacing: 12) {
                    // Like button (heart icon)
                    Button(action: {
                        guard let commentId = comment.id,
                              let userId = currentUserId else { return }
                        commentLikeManager.toggleLike(
                            commentId: commentId,
                            postId: comment.postId,
                            stampId: comment.stampId,
                            userId: userId,
                            commentOwnerId: comment.userId
                        )
                    }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(isLiked ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Triple dot menu for saved comments
                    Menu {
                        // Delete option (for own comments OR own post)
                        if canDelete {
                            Button(role: .destructive, action: onDelete) {
                                Label(isOwnComment ? "Delete comment" : "Remove comment", systemImage: "trash")
                            }
                        }
                        
                        // Report option (only for OTHER people's comments)
                        if !isOwnComment {
                            Button(role: .destructive, action: { showingReportSheet = true }) {
                                Label("Report comment", systemImage: "exclamationmark.triangle")
                            }
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

/// Wrapper to make String identifiable for navigation (CommentView version)
private struct IdentifiableString: Identifiable, Hashable {
    let id = UUID()
    let value: String
    let username: String
    let displayName: String
}

// MARK: - @Mention Formatting

/// Helper function to format comment text with @mentions highlighted
/// 
/// Parses comment text and highlights @username patterns in blue
/// Pattern matches: @[a-z0-9_]{3,20} (consistent with backend validation)
/// 
/// Example: "Hey @hiroo check this!" 
/// → "Hey " (black) + "@hiroo" (blue) + " check this!" (black)
/// 
/// Future enhancement: Add autocomplete dropdown when typing @ in comment box
/// (Similar to Instagram/Twitter) - would require username search as user types
fileprivate func formatCommentWithMentions(_ text: String) -> AttributedString {
    var attributedString = AttributedString(text)
    
    // Pattern matches @username (3-20 chars, alphanumeric + underscore)
    // \b word boundary prevents matching email addresses
    let mentionPattern = "@[a-z0-9_]{3,20}\\b"
    
    // Find all @mention ranges in the text
    let nsString = text as NSString
    let regex = try? NSRegularExpression(pattern: mentionPattern, options: [.caseInsensitive])
    let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    
    // Highlight each @mention in blue with semibold weight
    for match in matches {
        if let range = Range(match.range, in: text) {
            if let attrRange = Range(range, in: attributedString) {
                attributedString[attrRange].foregroundColor = .blue
                attributedString[attrRange].font = .system(size: 15, weight: .semibold)  // Explicit size to match .subheadline
            }
        }
    }
    
    return attributedString
}

// MARK: - Mention Suggestions View

/// Popup view showing username suggestions for @mentions
/// Appears above TextField when user types @
struct MentionSuggestionsView: View {
    let suggestions: [UserProfile]
    let onSelect: (UserProfile) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { profile in
                Button(action: {
                    onSelect(profile)
                }) {
                    HStack(spacing: 12) {
                        // Profile image (aligned with comment panel profile pic)
                        ProfileImageView(
                            avatarUrl: profile.avatarUrl,
                            userId: profile.id,
                            size: 36
                        )
                        
                        // User info (username on top, display name as subtitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(profile.username)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(profile.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                if profile.id != suggestions.last?.id {
                    Divider()
                        .padding(.leading, 64)  // Align with text, not profile pic
                }
            }
        }
        .padding(.horizontal, 16)  // Match comment input padding
        .background(Color(.systemBackground))
        .cornerRadius(12)
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
            .toolbar(.visible, for: .tabBar)
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

