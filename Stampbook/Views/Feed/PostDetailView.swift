import SwiftUI

/// Full-screen view for displaying a single post (used for notifications, deep links)
struct PostDetailView: View {
    let postId: String // Format: "userId-stampId"
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var followManager: FollowManager
    @EnvironmentObject var likeManager: LikeManager
    @EnvironmentObject var commentManager: CommentManager
    @StateObject private var feedManager = FeedManager()
    
    @State private var post: FeedManager.FeedPost? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showNotesEditor = false
    @State private var showLikes = false
    @State private var editingNotes = ""
    @State private var navigateToStampDetail = false
    @State private var stamp: Stamp? = nil
    @State private var selectedUserId: IdentifiableString? // For navigation to user profile from comments
    @Environment(\.dismiss) var dismiss
    
    // Computed properties for real-time updates
    private var isLiked: Bool {
        likeManager.isLiked(postId: postId)
    }
    
    private var currentLikeCount: Int {
        likeManager.getLikeCount(postId: postId)
    }
    
    private var currentCommentCount: Int {
        commentManager.getCommentCount(postId: postId)
    }
    
    // Read notes dynamically from userCollection
    private var currentNote: String? {
        guard let post = post else { return nil }
        let notes = stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == post.stampId })?
            .userNotes ?? ""
        return notes.isEmpty ? nil : notes
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading post...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let errorMessage = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        
                        Text("Post Not Found")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else if let post = post {
                    VStack(spacing: 0) {
                        // Post content
                        postContentView(post: post)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        
                        Divider()
                            .padding(.vertical, 24)
                        
                        // Comments section (without input)
                        commentsListSection
                            .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 16)
                }
            }
            
            // Fixed comment input at bottom
            if authManager.isSignedIn, let post = post {
                Divider()
                
                CommentInputView(
                    postId: postId,
                    postOwnerId: post.userId,
                    stampId: post.stampId,
                    commentManager: commentManager
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            loadPost()
        }
        .sheet(isPresented: $showNotesEditor) {
            if let post = post {
                NotesEditorView(notes: $editingNotes) { savedNotes in
                    stampsManager.userCollection.updateNotes(for: post.stampId, notes: savedNotes)
                }
            }
        }
        .sheet(isPresented: $showLikes) {
            if let post = post {
                LikeListView(
                    postId: postId,
                    postOwnerId: post.userId
                )
                .environmentObject(authManager)
                .environmentObject(followManager)
                .environmentObject(profileManager)
            }
        }
        .navigationDestination(isPresented: $navigateToStampDetail) {
            if let stamp = stamp {
                StampDetailView(
                    stamp: stamp,
                    isCollected: stampsManager.isCollected(stamp),
                    userLocation: nil,
                    showBackButton: true
                )
            }
        }
        // ✅ FIXED: Navigation destination for comment profile taps (moved from PostCommentRow)
        // Prevents "navigationDestination inside lazy container" warning
        .navigationDestination(item: $selectedUserId) { identifiableUser in
            UserProfileView(
                userId: identifiableUser.value,
                username: identifiableUser.username,
                displayName: identifiableUser.displayName
            )
        }
    }
    
    // MARK: - Post Content View
    
    @ViewBuilder
    private func postContentView(post: FeedManager.FeedPost) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with profile image and user info
            HStack(alignment: .top, spacing: 12) {
                // Profile Image
                NavigationLink(destination: UserProfileView(
                    userId: post.userId,
                    username: post.userName,
                    displayName: post.displayName
                )) {
                    ProfileImageView(
                        avatarUrl: post.avatarUrl,
                        userId: post.userId,
                        size: 40
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    // First line: "Username collected Stamp Name" - username and stamp separately tappable with AttributedString
                    Text(buildAttributedText(displayName: post.displayName, stampName: post.stampName, userId: post.userId, stampId: post.stampId))
                        .font(.body)
                        .foregroundColor(.primary)
                        .tint(.primary)
                        .environment(\.openURL, OpenURLAction { url in
                            handlePostTap(url: url, post: post)
                            return .handled
                        })
                    
                    // Second line: Location
                    if post.location != "Location not included" {
                        Text(post.location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Third line: Date
                    Text(post.date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Photos section - stamp + user photos
            PhotoGalleryView(
                stampId: post.stampId,
                maxPhotos: 5,
                showStampImage: true,
                stampImageName: post.stampImageName,
                onStampImageTap: {
                    loadStampAndNavigate()
                },
                userId: post.isCurrentUser ? nil : post.userId,
                userPhotos: post.isCurrentUser ? nil : post.userPhotos,
                userPhotoPaths: post.isCurrentUser ? nil : post.userImagePaths
            )
            .environmentObject(stampsManager)
            .environmentObject(authManager)
            
            // Note section
            if let note = currentNote, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if post.isCurrentUser {
                // Add Notes button (only for current user)
                Button(action: {
                    editingNotes = currentNote ?? ""
                    showNotesEditor = true
                }) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "note.text")
                            .font(.body)
                            .foregroundColor(.primary)
                        Text("Add Notes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Like button only
            HStack(spacing: 16) {
                // Like button
                HStack(spacing: 4) {
                    // Heart icon - toggles like
                    Button(action: {
                        guard let currentUserId = authManager.userId else { return }
                        likeManager.toggleLike(
                            postId: postId,
                            stampId: post.stampId,
                            userId: currentUserId,
                            postOwnerId: post.userId
                        )
                    }) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(isLiked ? .red : .primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Count - shows likes list
                    Button(action: {
                        showLikes = true
                    }) {
                        Text("\(currentLikeCount)")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Comments Section
    
    @ViewBuilder
    private var commentsListSection: some View {
        let comments = commentManager.getComments(postId: postId)
        
        if comments.isEmpty {
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
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 36)
        } else {
            // Comment list
            VStack(alignment: .leading, spacing: 16) {
                ForEach(comments) { comment in
                    CommentRowView(
                        comment: comment,
                        postId: postId,
                        postOwnerId: post?.userId ?? "",
                        commentManager: commentManager,
                        onProfileTap: { userId, username, displayName in
                            selectedUserId = IdentifiableString(value: userId, username: username, displayName: displayName)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadPost() {
        Task {
            isLoading = true
            errorMessage = nil
            
            do {
                // Fetch single post from FeedManager
                var fetchedPost = try await feedManager.fetchSinglePost(
                    postId: postId,
                    stampsManager: stampsManager
                )
                
                // Update isCurrentUser flag based on current user
                if let currentUserId = await MainActor.run(body: { authManager.userId }) {
                    fetchedPost.isCurrentUser = (fetchedPost.userId == currentUserId)
                }
                
                await MainActor.run {
                    self.post = fetchedPost
                    self.isLoading = false
                    
                    // Initialize counts in managers
                    likeManager.updateLikeCount(postId: postId, count: fetchedPost.likeCount)
                    commentManager.updateCommentCount(postId: postId, count: fetchedPost.commentCount)
                    
                    // Fetch like status and comments
                    Task {
                        if let userId = authManager.userId {
                            await likeManager.fetchLikeStatus(postIds: [postId], userId: userId)
                        }
                        await commentManager.fetchComments(postId: postId)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
                print("❌ Failed to load post: \(error.localizedDescription)")
            }
        }
    }
    
    private func loadStampAndNavigate() {
        guard let post = post else { return }
        
        Task {
            // Fast path: check cache first
            if let cached = stampsManager.getCachedStamp(id: post.stampId) {
                await MainActor.run {
                    stamp = cached
                    navigateToStampDetail = true
                }
                return
            }
            
            // Slow path: fetch from network
            let stamps = await stampsManager.fetchStamps(ids: [post.stampId], includeRemoved: true)
            
            await MainActor.run {
                if let fetchedStamp = stamps.first {
                    stamp = fetchedStamp
                    navigateToStampDetail = true
                }
            }
        }
    }
    
    // Build attributed string with tappable links for username and stamp name
    private func buildAttributedText(displayName: String, stampName: String, userId: String, stampId: String) -> AttributedString {
        var result = AttributedString()
        
        // Username (bold, tappable, no underline)
        var userText = AttributedString(displayName)
        userText.font = .body.weight(.bold)
        userText.foregroundColor = .primary
        userText.underlineStyle = nil
        userText.link = URL(string: "stampbook://profile/\(userId)")
        
        // Middle text (regular)
        var middleText = AttributedString(" collected ")
        middleText.font = .body
        middleText.foregroundColor = .primary
        
        // Stamp name (bold, tappable, no underline)
        var stampText = AttributedString(stampName)
        stampText.font = .body.weight(.bold)
        stampText.foregroundColor = .primary
        stampText.underlineStyle = nil
        stampText.link = URL(string: "stampbook://stamp/\(stampId)")
        
        result.append(userText)
        result.append(middleText)
        result.append(stampText)
        
        return result
    }
    
    // Handle URL taps from attributed string
    private func handlePostTap(url: URL, post: FeedManager.FeedPost) {
        if url.scheme == "stampbook" {
            if url.host == "profile" {
                selectedUserId = IdentifiableString(value: post.userId, username: post.userName, displayName: post.displayName)
            } else if url.host == "stamp" {
                loadStampAndNavigate()
            }
        }
    }
}

// MARK: - Supporting Views

/// Reusable comment row view
private struct CommentRowView: View {
    let comment: Comment
    let postId: String
    let postOwnerId: String
    @ObservedObject var commentManager: CommentManager
    let onProfileTap: (String, String, String) -> Void // (userId, username, displayName)
    
    @EnvironmentObject var authManager: AuthManager
    @State private var showDeleteAlert = false
    
    private var isOwnComment: Bool {
        comment.userId == authManager.userId
    }
    
    private var isOwnPost: Bool {
        postOwnerId == authManager.userId
    }
    
    private var canDelete: Bool {
        isOwnComment || isOwnPost
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Profile picture
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
                
                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(comment.createdAt.timeAgoDisplay())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Delete button (only if can delete)
            if canDelete {
                Menu {
                    Button(role: .destructive, action: {
                        showDeleteAlert = true
                    }) {
                        Label(isOwnComment ? "Delete comment" : "Remove comment", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert(isOwnComment ? "Delete Comment" : "Remove Comment", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button(isOwnComment ? "Delete" : "Remove", role: .destructive) {
                commentManager.deleteComment(
                    commentId: comment.id ?? "",
                    postId: postId,
                    postOwnerId: postOwnerId,
                    stampId: comment.stampId
                )
            }
        } message: {
            Text(isOwnComment ? "Are you sure you want to delete this comment?" : "Are you sure you want to remove this comment?")
        }
    }
}

/// Comment input field
private struct CommentInputView: View {
    let postId: String
    let postOwnerId: String
    let stampId: String
    @ObservedObject var commentManager: CommentManager
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    
    @State private var commentText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            ProfileImageView(
                avatarUrl: profileManager.currentUserProfile?.avatarUrl,
                userId: authManager.userId ?? "",
                size: 36
            )
            
            // Text field
            TextField("Add a comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .lineLimit(1...5)
            
            // Send button
            Button(action: {
                sendComment()
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, 8)
    }
    
    private func sendComment() {
        let trimmedText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              let userId = authManager.userId,
              let userProfile = profileManager.currentUserProfile else {
            return
        }
        
        commentManager.addComment(
            postId: postId,
            stampId: stampId,
            postOwnerId: postOwnerId,
            userId: userId,
            text: trimmedText,
            userProfile: userProfile
        )
        
        commentText = ""
        isTextFieldFocused = false
    }
}

// MARK: - Helper Types

/// Wrapper to make String identifiable for navigation (PostDetailView version)
private struct IdentifiableString: Identifiable, Hashable {
    let id = UUID()
    let value: String
    let username: String
    let displayName: String
}

