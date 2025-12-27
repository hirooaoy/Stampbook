import SwiftUI

/// Full-screen view for displaying a single post (used for notifications, deep links)
struct PostDetailView: View {
    let postId: String // Format: "userId-stampId"
    let highlightCommentId: String? // Optional: Comment to scroll to (from notification)
    
    init(postId: String, highlightCommentId: String? = nil) {
        self.postId = postId
        self.highlightCommentId = highlightCommentId
        print("🔵 [PostDetailView] INIT - postId: \(postId), highlightCommentId: \(highlightCommentId ?? "NIL")")
    }
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var followManager: FollowManager
    @EnvironmentObject var likeManager: LikeManager
    @EnvironmentObject var commentManager: CommentManager
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @StateObject private var feedManager = FeedManager()
    @StateObject private var commentLikeManager = CommentLikeManager()
    
    @State private var post: FeedManager.FeedPost? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var showNotesEditor = false
    @State private var showLikes = false
    @State private var showCommentLikes = false
    @State private var selectedCommentId: String? // For showing comment likes
    @State private var editingNotes = ""
    @State private var navigateToStampDetail = false
    @State private var stamp: Stamp? = nil
    @State private var selectedUserId: IdentifiableString? // For navigation to user profile from comments
    @State private var replyingTo: Comment? = nil // For comment replies
    @State private var scrollToCommentId: String? // Dynamic target for scrolling (can change via deep link)
    @State private var highlightedCommentId: String? // Comment to highlight temporarily
    @State private var showReportSheet = false // For reporting posts
    @FocusState private var commentInputFocused: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
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
    
    // Note from post owner (passed from FeedPost data)
    // For current user's posts, read from userCollection to get real-time updates after edits
    private var currentNote: String? {
        guard let post = post else { return nil }
        if post.isCurrentUser {
            let notes = stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == post.stampId })?
                .userNotes ?? ""
            return notes.isEmpty ? nil : notes
        } else {
            // For other users' posts, use the note passed from FeedPost
            return post.note
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content with scroll-to-comment capability
            ScrollViewReader { proxy in
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
             } // ScrollView
             .task(id: commentManager.getComments(postId: postId).count) {
                 print("📜 [PostDetailView] ==== SCROLL TASK STARTED ====")
                 print("📜 [PostDetailView] highlightCommentId: \(highlightCommentId ?? "NIL")")
                 print("📜 [PostDetailView] scrollToCommentId: \(scrollToCommentId ?? "NIL")")
                 
                 // Auto-scroll to target comment after comments load
                 let targetId = scrollToCommentId ?? highlightCommentId
                 
                 print("📜 [PostDetailView] targetId: \(targetId ?? "NIL")")
                 print("📜 [PostDetailView] Comment count: \(commentManager.getComments(postId: postId).count)")
                 
                 guard let targetId = targetId else { 
                     print("⚠️ [PostDetailView] No targetId, exiting scroll task")
                     return 
                 }
                 
                 let comments = commentManager.getComments(postId: postId)
                 guard !comments.isEmpty else { 
                     print("⚠️ [PostDetailView] No comments loaded yet")
                     return 
                 }
                 
                 print("📜 [PostDetailView] Checking if target exists in \(comments.count) comments")
                 print("📜 [PostDetailView] Comment IDs: \(comments.compactMap { $0.id })")
                 
                 // Check if target comment exists
                 if comments.contains(where: { $0.id == targetId }) {
                     print("✅ [PostDetailView] Found target comment! Scrolling...")
                     
                     // Small delay to ensure layout is complete
                     try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms
                     
                     await MainActor.run {
                         // Set highlight and scroll
                         highlightedCommentId = targetId
                         print("✨ [PostDetailView] Set highlightedCommentId: \(targetId)")
                         
                         withAnimation(.easeInOut(duration: 0.3)) {
                             proxy.scrollTo(targetId, anchor: .center)
                             print("🎯 [PostDetailView] Called scrollTo for: \(targetId)")
                         }
                         
                        // Remove highlight after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("✨ [PostDetailView] Removing highlight")
                            highlightedCommentId = nil
                        }
                     }
                 } else {
                     print("❌ [PostDetailView] Target comment NOT FOUND in loaded comments")
                 }
             }
            .onChange(of: deepLinkManager.pendingDeepLink) { _, newValue in
                // Handle deep link while already on PostDetailView
                guard let deepLink = newValue else { return }
                
                switch deepLink {
                case .post(let deepLinkPostId, let commentId):
                    // Only handle if it's for the same post we're viewing
                    guard deepLinkPostId == postId else { return }
                    
                    Logger.info("🔗 [PostDetailView] Refreshing for deep link to same post: commentId=\(commentId ?? "nil")", category: "DeepLink")
                    
                    // Refresh comments to get the new one
                    Task {
                        await commentManager.fetchComments(postId: postId)
                        
                        // Scroll to the new comment if specified
                        if let targetCommentId = commentId {
                            await MainActor.run {
                                scrollToCommentId = targetCommentId
                            }
                        }
                    }
                    
                    // Clear the deep link
                    deepLinkManager.clearPendingDeepLink()
                    
                case .profile:
                    // Profile links don't affect this view
                    break
                }
            }
            } // ScrollViewReader
            
            // Fixed comment input at bottom
            if authManager.isSignedIn, let post = post {
                Divider()
                
                CommentInputView(
                    postId: postId,
                    postOwnerId: post.userId,
                    stampId: post.stampId,
                    commentManager: commentManager,
                    replyingTo: $replyingTo
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let post = post, !post.isCurrentUser {
                    Menu {
                        Button(role: .destructive, action: { showReportSheet = true }) {
                            Label("Report post", systemImage: "exclamationmark.triangle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
        }
        // .toolbar(.hidden, for: .tabBar)
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
        .sheet(isPresented: $showCommentLikes) {
            if let commentId = selectedCommentId {
                CommentLikesView(commentId: commentId)
                    .environmentObject(authManager)
                    .environmentObject(profileManager)
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let post = post {
                NavigationStack {
                    SimplePostReportView(
                        postId: postId,
                        postAuthorUsername: post.userName,
                        postAuthorId: post.userId,
                        stampName: post.stampName
                    )
                    .environmentObject(authManager)
                }
            }
        }
        // ✅ FIX (Dec 2025): Pass viewingUserId and viewingDisplayName when navigating to StampDetailView
        // This ensures that when viewing someone else's stamp, StampDetailView shows THEIR notes/photos,
        // not the current user's notes. Without this, viewing Dylan's Oracle Park stamp would incorrectly
        // show Justin's notes instead of Dylan's (empty) notes.
        // Note: isCollected checks if CURRENT USER collected it (correct behavior - shows lock icon
        // if you haven't collected it yet, even if the post author collected it)
        .navigationDestination(isPresented: $navigateToStampDetail) {
            if let stamp = stamp, let post = post {
                // Construct CollectedStamp from FeedPost data for instant display
                let collectedStamp: CollectedStamp? = post.isCurrentUser ? nil : CollectedStamp(
                    stampId: post.stampId,
                    userId: post.userId,
                    collectedDate: post.actualDate,
                    userNotes: post.note ?? "",
                    userImageNames: post.userPhotos,
                    userImagePaths: post.userImagePaths,
                    likeCount: post.likeCount,
                    commentCount: post.commentCount,
                    userRank: nil // Will be fetched in background
                )
                
                StampDetailView(
                    stamp: stamp,
                    isCollected: stampsManager.isCollected(stamp),
                    userLocation: nil,
                    showBackButton: true,
                    viewingUserId: post.isCurrentUser ? nil : post.userId,  // Pass post author's userId when viewing their stamp
                    viewingDisplayName: post.isCurrentUser ? nil : post.displayName,  // Pass post author's displayName for "Dylan's Memory" heading
                    initialCollectedStamp: collectedStamp  // Pre-populated data from FeedPost
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
                if post.isCurrentUser {
                    // Current user's note - tappable to edit
                    Button(action: {
                        editingNotes = currentNote ?? ""
                        showNotesEditor = true
                    }) {
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    // Other user's note - read-only
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                ForEach(comments, id: \.computedId) { comment in
                    CommentRowView(
                        comment: comment,
                        postId: postId,
                        postOwnerId: post?.userId ?? "",
                        isHighlighted: comment.id == highlightedCommentId,
                        commentManager: commentManager,
                        commentLikeManager: commentLikeManager,
                        onProfileTap: { userId, username, displayName in
                            selectedUserId = IdentifiableString(value: userId, username: username, displayName: displayName)
                        },
                        onReply: { replyingComment in
                            replyingTo = replyingComment
                            commentInputFocused = true
                        },
                        onShowLikes: { commentId in
                            selectedCommentId = commentId
                            showCommentLikes = true
                        }
                    )
                    .id(comment.id)  // ✅ ADDED: Anchor for ScrollViewReader
                    .padding(.leading, comment.parentCommentId != nil ? 40 : 0) // Single indent for all replies
                    .background(
                        // Edge-to-edge highlight background
                        Group {
                            if comment.id == highlightedCommentId {
                                (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                    .padding(.horizontal, -16) // Extend to screen edges (compensate for parent padding)
                                    .padding(.leading, comment.parentCommentId != nil ? -40 : 0) // Extend past reply indent
                                    .padding(.vertical, -8) // Extend to cover entire row + 2pt breathing room
                            }
                        }
                    )
                    .animation(.easeInOut(duration: 0.3), value: highlightedCommentId)
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
                            if commentManager.isLoading[postId] == true {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 16))
                            }
                            Text(commentManager.isLoading[postId] == true ? "Loading..." : "Load More Comments")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .disabled(commentManager.isLoading[postId] == true)
                    .padding(.top, 8)
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
                        await commentManager.fetchComments(postId: postId, loadMore: false)
                        
                        print("📝 [PostDetailView] Fetched \(commentManager.getComments(postId: postId).count) comments")
                        
                        // Fetch like status for all comments
                        if let userId = authManager.userId {
                            let commentIds = commentManager.getComments(postId: postId).compactMap { $0.id }
                            await commentLikeManager.fetchLikeStatus(commentIds: commentIds, userId: userId)
                        }
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
    let isHighlighted: Bool
    @ObservedObject var commentManager: CommentManager
    @ObservedObject var commentLikeManager: CommentLikeManager
    let onProfileTap: (String, String, String) -> Void // (userId, username, displayName)
    let onReply: (Comment) -> Void // Callback for reply button
    let onShowLikes: (String) -> Void // Show likes sheet for this comment
    
    @EnvironmentObject var authManager: AuthManager
    @State private var showDeleteAlert = false
    @State private var showingReportSheet = false
    
    private var isOwnComment: Bool {
        comment.userId == authManager.userId
    }
    
    private var isOwnPost: Bool {
        postOwnerId == authManager.userId
    }
    
    private var canDelete: Bool {
        isOwnComment || isOwnPost
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
                              let userId = authManager.userId else { return }
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
                            Button(role: .destructive, action: {
                                showDeleteAlert = true
                            }) {
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
    
    // Reply state
    @Binding var replyingTo: Comment?
    
    // @mention autocomplete states
    @State private var mentionQuery: String = ""
    @State private var mentionSuggestions: [UserProfile] = []
    @State private var showMentionSuggestions: Bool = false
    @State private var mentionSearchTask: Task<Void, Never>?
    
    var body: some View {
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
                TextField("Add a comment...", text: $commentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .lineLimit(1...5)
                    .onChange(of: commentText) { oldValue, newValue in
                        detectMention(in: newValue)
                    }
                
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
        .onChange(of: replyingTo) { oldValue, newValue in
            if let replyComment = newValue {
                commentText = "@\(replyComment.userUsername) "
                isTextFieldFocused = true
            }
        }
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
            userProfile: userProfile,
            parentCommentId: replyingTo?.id
        )
        
        commentText = ""
        replyingTo = nil
        isTextFieldFocused = false
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
        guard let lastAtIndex = commentText.lastIndex(of: "@") else {
            return
        }
        
        // Replace from @ to cursor with @username + space
        let beforeAt = String(commentText[..<lastAtIndex])
        commentText = beforeAt + "@\(username) "
        
        // Hide suggestions
        showMentionSuggestions = false
        mentionQuery = ""
        mentionSearchTask?.cancel()
        
        // Keep keyboard focused
        isTextFieldFocused = true
    }
}

// MARK: - @Mention Formatting

/// Helper function to format comment text with @mentions highlighted
/// Used for both live TextField highlighting and comment display
fileprivate func formatCommentWithMentions(_ text: String) -> AttributedString {
    var attributedString = AttributedString(text)
    
    // Pattern matches @username (3-20 chars, alphanumeric + underscore)
    // \b word boundary prevents matching email addresses
    let mentionPattern = "@[a-z0-9_]{3,20}\\b"
    
    // Find all @mention ranges in the text
    let nsString = text as NSString
    let regex = try? NSRegularExpression(pattern: mentionPattern, options: [.caseInsensitive])
    let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
    
    // Highlight each @mention in blue
    for match in matches {
        if let range = Range(match.range, in: text) {
            if let attrRange = Range(range, in: attributedString) {
                attributedString[attrRange].foregroundColor = .blue
                attributedString[attrRange].font = .body.weight(.semibold)
            }
        }
    }
    
    return attributedString
}

// MARK: - Helper Types

/// Wrapper to make String identifiable for navigation (PostDetailView version)
private struct IdentifiableString: Identifiable, Hashable {
    let id = UUID()
    let value: String
    let username: String
    let displayName: String
}

// MARK: - Post Report View

struct SimplePostReportView: View {
    let postId: String
    let postAuthorUsername: String
    let postAuthorId: String
    let stampName: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    @State private var reportText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // TextEditor
            TextEditor(text: $reportText)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.top, 12)
            
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
        .navigationTitle("Report post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .disabled(isSending)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button("Send") {
                    sendReport()
                }
                .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .fontWeight(.semibold)
            }
        }
        .alert("Report Sent", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you. We'll review this report within 24 hours.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func sendReport() {
        let trimmedText = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit feedback to Firestore
                let userId = authManager.userId ?? "anonymous"
                let reportMessage = """
                Reported Post by @\(postAuthorUsername) (ID: \(postAuthorId))
                Post ID: \(postId)
                Stamp: \(stampName)
                
                Report:
                \(trimmedText)
                """
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Post Report",
                    message: reportMessage
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    showErrorAlert = true
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

