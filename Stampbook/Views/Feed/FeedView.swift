import SwiftUI
import AuthenticationServices
import PhotosUI
import MessageUI
import Combine

struct UserProfileNavigation: Hashable, Identifiable {
    let id = UUID()
    let userId: String
    let username: String
    let displayName: String
}

struct FeedView: View {
    // Debug flag - set to true to enable debug logging
    private let DEBUG_FEED = false
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var followManager: FollowManager // Shared instance from StampbookApp
    @EnvironmentObject var likeManager: LikeManager // Shared instance from StampbookApp
    @EnvironmentObject var commentManager: CommentManager // Shared instance from StampbookApp
    @EnvironmentObject var notificationManager: NotificationManager // Shared instance from StampbookApp
    @StateObject private var feedManager = FeedManager() // Persists across tab switches
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: Int
    @Binding var shouldResetStampsNavigation: Bool // Binding to reset StampsView navigation
    @State private var showNotifications = false
    @State private var selectedFeedTab: FeedTab = .all
    @State private var showUserSearch = false
    @State private var showSignOutConfirmation = false
    @State private var showFeedback = false
    @State private var showProblemReport = false
    @State private var showAboutStampbook = false
    @State private var showForLocalBusiness = false
    @State private var showForCreators = false
    @State private var showSuggestStamp = false
    @State private var showSuggestCollection = false
    @State private var showAppStoreUrlCopied = false // Show confirmation when App Store URL is copied
    @State private var profileUpdateListener: AnyCancellable? // Listen for profile updates
    @State private var cancellables = Set<AnyCancellable>() // Store all notification listeners
    @State private var showInviteCodeSheet = false // Show invite code sheet for new users
    @State private var showLikes = false // Show likes sheet for a post
    @State private var selectedPostForLikes: (postId: String, ownerId: String)? = nil // Track which post's likes to show
    
    // SHEET MANAGEMENT: This view has 13 sheet modifiers which triggers SwiftUI warnings
    // ("Currently, only presenting a single sheet is supported"). These warnings are COSMETIC
    // and can be safely IGNORED. The sheets work correctly - they queue properly and present
    // one at a time. The activeSheetCount pattern below is intentional and handles feed refresh
    // timing when sheets with follow buttons are open. Do NOT refactor to coordinator pattern
    // without careful consideration - it risks breaking the feed refresh logic. Decision made
    // Nov 2025 to defer this until post-launch. See: CROSS_REFERENCE_RISK_ANALYSIS.md
    @State private var activeSheetCount = 0 // Track number of sheets with follow buttons currently open
    @State private var hasPendingRefresh = false // Track if refresh should execute when sheets close
    @State private var justCompletedPendingRefresh = false // Prevent double-fetch after pending refresh
    
    enum FeedTab: String, CaseIterable {
        case all = "All"
        case onlyYou = "Only Yours"
    }
    
    /// Build the common menu items shared between signed-in and signed-out states
    @ViewBuilder
    private var menuContent: some View {
        Button(action: {
            showAboutStampbook = true
        }) {
            Label("About Stampbook", systemImage: "info.circle")
        }
        
        // TODO: Add back later
        // Button(action: {
        //     copyAppStoreUrl()
        // }) {
        //     Label("Share Stampbook", systemImage: "square.and.arrow.up")
        // }
        
        Divider()
        
        Button(action: {
            showForLocalBusiness = true
        }) {
            Label("For local business", systemImage: "storefront")
        }
        
        // TODO: Add back later
        // Button(action: {
        //     showForCreators = true
        // }) {
        //     Label("For creators", systemImage: "sparkles")
        // }
        
        Divider()
        
        // Only show suggestion options for signed-in users
        if authManager.isSignedIn {
            Button(action: {
                showSuggestStamp = true
            }) {
                Label("Suggest a stamp", systemImage: "plus.app")
            }
            
            Button(action: {
                showSuggestCollection = true
            }) {
                Label("Suggest a collection", systemImage: "rectangle.stack.badge.plus")
            }
            
            Divider()
        }
        
        Button(action: {
            showProblemReport = true
        }) {
            Label("Report a problem", systemImage: "exclamationmark.bubble")
        }
        
        Button(action: {
            showFeedback = true
        }) {
            Label("Send feedback", systemImage: "envelope")
        }
    }
    
    /// Refresh feed data without clearing cached statistics
    private func refreshFeedData() async {
        // Refresh based on currently selected tab
        guard let userId = authManager.userId else { return }
        
        if selectedFeedTab == .all {
            await feedManager.refresh(userId: userId, stampsManager: stampsManager)
        } else {
            await feedManager.loadMyPosts(userId: userId, stampsManager: stampsManager, forceRefresh: true)
        }
        
        // Initialize like counts from feed data (bulk operation, no race condition)
        let postsToSync = selectedFeedTab == .all ? feedManager.feedPosts : feedManager.myPosts
        let likeCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.likeCount) })
        likeManager.setLikeCounts(likeCounts)
        
        // Initialize comment counts from feed data (bulk operation, no race condition)
        let commentCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.commentCount) })
        commentManager.setCommentCounts(commentCounts)
        
        // Fetch like status for all posts to sync with cached state
        let postIds = postsToSync.map { $0.id }
        if !postIds.isEmpty {
            await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
        }
        
        // Also refresh notifications and badge indicator
        await notificationManager.fetchNotifications(userId: userId)
        await notificationManager.checkHasUnreadNotifications(userId: userId)
    }
    
    /// Execute pending refresh if one was queued while sheets were open
    private func executePendingRefresh() {
        guard hasPendingRefresh && activeSheetCount == 0 else { return }
        
        print("✅ [FeedView] Executing pending refresh after sheet closed")
        hasPendingRefresh = false
        justCompletedPendingRefresh = true // Prevent task-triggered double-fetch
        
        Task {
            await refreshFeedData()
            
            // Reset flag after a brief delay to allow .task to see it
            // This prevents the .task modifier from triggering an immediate reload
            // when it sees empty posts after the pending refresh completes
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            await MainActor.run {
                justCompletedPendingRefresh = false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            // Don't render content while auth is still being checked
            if authManager.isCheckingAuth {
                // Show minimal loading state during auth check
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    // Top bar with logo and icons
                    HStack {
                        // Logo on the left (app icon) - only show when signed in
                        if authManager.isSignedIn {
                            Image("AppLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                        }
                        
                        Spacer()
                        
                        if authManager.isSignedIn {
                        // Signed-in menu: Search, notifications, and ellipses
                            HStack(spacing: 8) {
                                Button(action: {
                                    showUserSearch = true
                                }) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 24))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)  // Larger tap target
                                        .contentShape(Rectangle())     // Make entire frame tappable
                                }
                                
                                // Notification bell with badge
                                Button(action: {
                                    showNotifications = true
                                }) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: "bell")
                                            .font(.system(size: 24))
                                            .foregroundColor(.primary)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                        
                                        // Unread badge indicator
                                        if notificationManager.hasUnreadNotifications {
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 10, height: 10)
                                                .offset(x: 0, y: 0)
                                        }
                                    }
                                }
                                
                                Menu {
                                    menuContent
                                    
                                    Divider()
                                    
                                    Button(role: .destructive, action: {
                                        showSignOutConfirmation = true
                                    }) {
                                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 24))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)  // Larger tap target
                                        .contentShape(Rectangle())     // Make entire frame tappable
                                }
                            }
                        } else {
                            // Signed-out menu: Just ellipsis with Menu
                            Menu {
                                menuContent
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)  // Larger tap target
                                    .contentShape(Rectangle())     // Make entire frame tappable
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    
                    // Scrollable content
                    if authManager.isSignedIn {
                        // Signed-in: Show feed with pull-to-refresh
                        ScrollView {
                            VStack(spacing: 0) {
                                // Segmented control
                                Picker("Feed Type", selection: $selectedFeedTab) {
                                    ForEach(FeedTab.allCases, id: \.self) { tab in
                                        Text(tab.rawValue)
                                            .font(.system(size: 24, weight: .medium))
                                            .tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.large)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 20)
                                
                                // Content based on selected tab
                                FeedContent(
                                    feedType: selectedFeedTab,
                                    selectedTab: $selectedTab,
                                    shouldResetStampsNavigation: $shouldResetStampsNavigation,
                                    activeSheetCount: $activeSheetCount,
                                    justCompletedPendingRefresh: $justCompletedPendingRefresh,
                                    onSheetDismiss: executePendingRefresh,
                                    onShowLikes: { postId, ownerId in
                                        selectedPostForLikes = (postId: postId, ownerId: ownerId)
                                        showLikes = true
                                    },
                                    feedManager: feedManager,
                                    likeManager: likeManager,
                                    commentManager: commentManager,
                                    debugEnabled: DEBUG_FEED
                                )
                            }
                        }
                        .refreshable {
                            await refreshFeedData()
                        }
                    } else {
                        // Signed-out: Show welcome screen without pull-to-refresh
                        ScrollView {
                            VStack(spacing: 24) {
                                Spacer()
                                    .frame(height: 60)
                                
                                // App logo
                                Image("AppLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(16)
                                
                                VStack(spacing: 12) {
                                    Text("Welcome to Stampbook")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                    
                                    Text("Sign in to start your stamp collection and follow your friends.")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                                
                                // Get Started button (replaced Sign in with Apple)
                                Button(action: {
                                    showInviteCodeSheet = true
                                }) {
                                    Text("Get Started")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                        .background(Color.blue)
                                    .cornerRadius(8)
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                                .padding(.bottom, 40)
                            }
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showNotifications) {
            NotificationView()
                .environmentObject(authManager)
                .environmentObject(stampsManager)
                .environmentObject(profileManager)
                .environmentObject(notificationManager)
                .onAppear {
                    activeSheetCount += 1
                }
                .onDisappear {
                    activeSheetCount -= 1
                    executePendingRefresh()
                }
        }
        .sheet(isPresented: $showUserSearch) {
            UserSearchView()
                .environmentObject(authManager)
                .onAppear {
                    activeSheetCount += 1
                }
                .onDisappear {
                    activeSheetCount -= 1
                    executePendingRefresh()
                }
        }
        .sheet(isPresented: $showFeedback) {
            SimpleFeedbackView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showProblemReport) {
            SimpleProblemReportView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showAboutStampbook) {
            AboutStampbookView()
        }
        .sheet(isPresented: $showForLocalBusiness) {
            ForLocalBusinessView()
        }
        .sheet(isPresented: $showForCreators) {
            ForCreatorsView()
        }
        .sheet(isPresented: $showSuggestStamp) {
            SuggestStampView()
                .environmentObject(authManager)
                .environmentObject(profileManager)
        }
        .sheet(isPresented: $showSuggestCollection) {
            SuggestCollectionView()
                .environmentObject(authManager)
                .environmentObject(profileManager)
        }
        .sheet(isPresented: $showInviteCodeSheet) {
            InviteCodeSheet(isAuthenticated: $authManager.isSignedIn)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showLikes) {
            if let selectedPost = selectedPostForLikes {
                LikeListView(
                    postId: selectedPost.postId,
                    postOwnerId: selectedPost.ownerId
                )
                .environmentObject(authManager)
                .environmentObject(followManager)
                .environmentObject(profileManager)
                .onAppear {
                    activeSheetCount += 1
                }
                .onDisappear {
                    activeSheetCount -= 1
                    executePendingRefresh()
                }
            }
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("App Store Link Copied", isPresented: $showAppStoreUrlCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The App Store link has been copied to your clipboard.")
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                // Feed error messages
                if let errorMessage = feedManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
                
                // Like error messages
                if let errorMessage = likeManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.top, feedManager.errorMessage == nil ? 8 : 0)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
            }
        }
        .onAppear {
            // Listen for profile updates to refresh feed immediately
            profileUpdateListener = NotificationCenter.default.publisher(for: .profileDidUpdate)
                .sink { _ in
                    print("🔔 [FeedView] Profile updated - refreshing feed now")
                    // ProfileManager has loaded/updated, now load feed with fresh profile data
                    if let userId = authManager.userId, authManager.isSignedIn {
                        Task {
                            await feedManager.loadFeed(userId: userId, stampsManager: stampsManager, forceRefresh: false)
                        }
                    }
                }
            
            // Listen for following list changes to refresh feed (queue if sheets are open)
            NotificationCenter.default.publisher(for: .followingListDidChange)
                .sink { _ in
                    print("🔔 [FeedView] Following list changed")
                    
                    // If sheets with follow buttons are currently open, queue the refresh
                    if activeSheetCount > 0 {
                        print("📋 [FeedView] Sheets are open, queuing refresh for later")
                        hasPendingRefresh = true
                    } else {
                        // No sheets open, refresh immediately
                        print("🔔 [FeedView] No sheets open, refreshing feed now")
                        if let _ = authManager.userId, authManager.isSignedIn {
                            Task {
                                await refreshFeedData()
                            }
                        }
                    }
                }
                .store(in: &cancellables)
            
            // Hook up comment count updates to feed
            commentManager.onCommentCountChanged = { [weak feedManager] postId, newCount in
                feedManager?.updatePostCommentCount(postId: postId, newCount: newCount)
            }
            
            // Hook up like count updates to feed
            likeManager.onLikeCountChanged = { [weak feedManager] postId, newCount in
                feedManager?.updatePostLikeCount(postId: postId, newCount: newCount)
            }
            
            // If user is already signed in when view appears (handles first launch + returning user)
            if let userId = authManager.userId, authManager.isSignedIn, profileManager.currentUserProfile != nil {
                Task {
                    await feedManager.loadFeed(userId: userId, stampsManager: stampsManager, forceRefresh: false)
                }
            }
        }
    }
    
    // MARK: - Unified Feed Content View
    struct FeedContent: View {
        let feedType: FeedTab
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool
        @Binding var activeSheetCount: Int // Track sheets with follow buttons
        @Binding var justCompletedPendingRefresh: Bool // Prevent double-fetch after pending refresh
        let onSheetDismiss: () -> Void // Execute pending refresh when sheets close
        let onShowLikes: (String, String) -> Void // Show likes sheet for a post (postId, ownerId)
        @ObservedObject var feedManager: FeedManager
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        let debugEnabled: Bool
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @State private var hasLoadedOnce = false
        @State private var selectedStampForDetail: Stamp?
        @State private var selectedPostForDetail: String?
        @State private var selectedUserForProfile: UserProfileNavigation?
        
        // Choose data source based on feed type
        // "All" = Instagram-style chronological feed from followed users
        // "Only Yours" = All YOUR stamps in chronological order
        private var posts: [FeedManager.FeedPost] {
            feedType == .all ? feedManager.feedPosts : feedManager.myPosts
        }
        
        // Empty state text based on feed type
        private var emptyStateIcon: String {
            feedType == .all ? "newspaper" : "book.closed.fill"
        }
        
        private var emptyStateTitle: String {
            feedType == .all ? "No posts yet" : "No stamps collected yet"
        }
        
        private var emptyStateMessage: String {
            feedType == .all ? "Follow others to see their stamp collections" : "Start exploring to collect your first stamp!"
        }
        
        var body: some View {
            VStack(spacing: 20) {
                // SIMPLE LOADING PATTERN: One consistent rule
                if !authManager.isSignedIn {
                    // Not signed in - show sign-in prompt (handled by parent)
                    EmptyView()
                } else if posts.isEmpty && feedManager.isLoading {
                    // Loading with no content - show skeleton posts
                    // Always show skeleton during loading to prevent jarring "No posts yet" flash
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonPostView()
                        
                        if index < 2 {
                            Divider()
                        }
                    }
                } else if posts.isEmpty {
                    // Empty state (no posts after loading)
                    VStack(spacing: 16) {
                        Image(systemName: emptyStateIcon)
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text(emptyStateTitle)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(emptyStateMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                } else {
                    // Show posts (from cache or fresh data)
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        FeedPostRow(
                            userId: post.userId,
                            userName: post.displayName,
                            avatarUrl: post.avatarUrl,
                            stampName: post.stampName,
                            stampImageName: post.stampImageName,
                            location: post.location,
                            date: post.date,
                            isCurrentUser: feedType == .onlyYou ? true : post.isCurrentUser,
                            stamp: post.stamp,
                            userPhotos: post.userPhotos,
                            userImagePaths: post.userImagePaths,
                            likeCount: post.likeCount,
                            commentCount: post.commentCount,
                            selectedTab: $selectedTab,
                            shouldResetStampsNavigation: $shouldResetStampsNavigation,
                            activeSheetCount: $activeSheetCount,
                            onSheetDismiss: onSheetDismiss,
                            onShowLikes: onShowLikes,
                            likeManager: likeManager,
                            commentManager: commentManager,
                            onStampTap: { stamp in selectedStampForDetail = stamp },
                            onPostTap: { postId in selectedPostForDetail = postId },
                            onUserTap: { userId, username, displayName in 
                                selectedUserForProfile = UserProfileNavigation(userId: userId, username: username, displayName: displayName)
                            }
                        )
                        .transition(.opacity)
                        .onAppear {
                            // Trigger pagination when user scrolls near the end
                            // Only trigger if we have more posts available AND we're near the bottom
                            if feedManager.hasMorePosts && 
                               posts.count >= 15 && 
                               index == posts.count - 5 {
                                loadMorePostsIfNeeded()
                            }
                        }
                        
                        if index < posts.count - 1 {
                            Divider()
                        }
                    }
                    
                    // Loading indicator at bottom (if loading more posts)
                    if feedManager.isLoadingMore {
                        ProgressView()
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                    }
                    
                    // Loading indicator at bottom (if refreshing existing content)
                    if feedManager.isLoading && hasLoadedOnce {
                        ProgressView()
                            .padding(.top, 16)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .navigationDestination(item: $selectedStampForDetail) { stamp in
                StampDetailView(
                    stamp: stamp,
                    userLocation: nil,
                    showBackButton: true
                )
            }
            .navigationDestination(item: $selectedPostForDetail) { postId in
                PostDetailView(postId: postId)
                    // Environment objects propagate automatically from parent
            }
            .navigationDestination(item: $selectedUserForProfile) { userInfo in
                UserProfileView(
                    userId: userInfo.userId,
                    username: userInfo.username,
                    displayName: userInfo.displayName
                )
            }
            .task(id: feedType) {
                // Load feed when tab is selected (runs when feedType changes)
                loadFeedIfNeeded()
            }
        }
        
        /// Load feed with smart caching
        private func loadFeedIfNeeded() {
            if debugEnabled {
                print("🔍 [DEBUG] FeedContent.loadFeedIfNeeded called for \(feedType.rawValue)")
            }
            guard let userId = authManager.userId else { return }
            guard authManager.isSignedIn else { return }
            
            // Skip if we just completed a pending refresh (prevents double-fetch)
            // The pending refresh already loaded the latest feed data
            if justCompletedPendingRefresh {
                if debugEnabled {
                    print("🔍 [DEBUG] FeedContent skipping load - pending refresh just completed")
                }
                return
            }
            
            // Check if we already have data for this tab (prevent duplicate loads)
            let currentPosts = feedType == .all ? feedManager.feedPosts : feedManager.myPosts
            if !currentPosts.isEmpty {
                if debugEnabled {
                    print("🔍 [DEBUG] FeedContent \(feedType.rawValue) already has data, skipping load")
                }
                return
            }
            
            if debugEnabled {
                print("🔍 [DEBUG] FeedContent calling feedManager.load\(feedType == .all ? "Feed" : "MyPosts")()")
            }
            Task {
                // Load appropriate feed based on selected tab
                if feedType == .all {
                    await feedManager.loadFeed(
                        userId: userId,
                        stampsManager: stampsManager,
                        forceRefresh: false
                    )
                } else {
                    await feedManager.loadMyPosts(
                        userId: userId,
                        stampsManager: stampsManager,
                        forceRefresh: false
                    )
                }
                
                // Initialize like counts from feed data (bulk operation, no race condition)
                let postsToSync = feedType == .all ? feedManager.feedPosts : feedManager.myPosts
                let likeCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.likeCount) })
                likeManager.setLikeCounts(likeCounts)
                
                // Initialize comment counts from feed data (bulk operation, no race condition)
                let commentCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.commentCount) })
                commentManager.setCommentCounts(commentCounts)
                
                // Fetch like status for all posts to sync with cached state
                let postIds = postsToSync.map { $0.id }
                if !postIds.isEmpty {
                    await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
                }
                
                // Mark that we've attempted to load at least once
                await MainActor.run {
                    hasLoadedOnce = true
                }
            }
        }
        
        /// Load more posts when scrolling near the end
        private func loadMorePostsIfNeeded() {
            guard let userId = authManager.userId else { return }
            guard authManager.isSignedIn else { return }
            guard feedManager.hasMorePosts && !feedManager.isLoadingMore else { return }
            
            if debugEnabled {
                print("🔍 [DEBUG] FeedContent triggering loadMore\(feedType == .all ? "Posts" : "MyPosts")")
            }
            
            Task {
                // Load more for appropriate tab
                if feedType == .all {
                    await feedManager.loadMorePosts(
                        userId: userId,
                        stampsManager: stampsManager
                    )
                } else {
                    await feedManager.loadMoreMyPosts(
                        userId: userId,
                        stampsManager: stampsManager
                    )
                }
                
                // Update like counts for new posts
                let postsToSync = feedType == .all ? feedManager.feedPosts : feedManager.myPosts
                let likeCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.likeCount) })
                likeManager.setLikeCounts(likeCounts)
                
                // Update comment counts for new posts
                let commentCounts = Dictionary(uniqueKeysWithValues: postsToSync.map { ($0.id, $0.commentCount) })
                commentManager.setCommentCounts(commentCounts)
                
                // Fetch like status for new posts
                let postIds = postsToSync.map { $0.id }
                if !postIds.isEmpty {
                    await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
                }
            }
        }
    }
    
    struct FeedPostRow: View {
        let userId: String
        let userName: String
        let avatarUrl: String?
        let stampName: String
        let stampImageName: String
        let location: String
        let date: String
        let isCurrentUser: Bool // true if this is the current user's post
        let stamp: Stamp // Full stamp object (no need to fetch)
        let userPhotos: [String] // Additional user photos (can be empty)
        let userImagePaths: [String] // Firebase Storage paths for user photos
        let likeCount: Int
        let commentCount: Int
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool // Binding to reset StampsView navigation
        @Binding var activeSheetCount: Int // Track sheets with follow buttons
        let onSheetDismiss: () -> Void // Execute pending refresh when sheets close
        let onShowLikes: (String, String) -> Void // Show likes sheet for this post (postId, ownerId)
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        let onStampTap: (Stamp) -> Void
        let onPostTap: (String) -> Void
        let onUserTap: (String, String, String) -> Void
        
        // NESTED SHEETS: This row has 2 sheet modifiers (NotesEditor, Comments).
        // Likes sheet has been moved to FeedView level to prevent dismissal on follow state changes.
        // Multiple FeedPostRow instances (one per post) trigger SwiftUI warnings about
        // multiple sheets. These warnings are COSMETIC - sheets work correctly. The
        // showComments sheet uses activeSheetCount tracking for feed refresh timing.
        // IGNORE warnings. See: CROSS_REFERENCE_RISK_ANALYSIS.md
        @State private var showNotesEditor: Bool = false
        @State private var showComments: Bool = false
        @State private var editingNotes: String = ""
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @EnvironmentObject var profileManager: ProfileManager
        @EnvironmentObject var followManager: FollowManager
        
        // Computed properties for real-time updates
        private var postId: String {
            "\(userId)-\(stamp.id)"
        }
        
        private var isLiked: Bool {
            likeManager.isLiked(postId: postId)
        }
        
        private var currentLikeCount: Int {
            likeManager.getLikeCount(postId: postId)
        }
        
        private var currentCommentCount: Int {
            commentManager.getCommentCount(postId: postId)
        }
        
        // Read notes dynamically from userCollection (same pattern as photos)
        // This ensures notes update instantly when edited, consistent with other features
        private var currentNote: String? {
            let notes = stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == stamp.id })?
                .userNotes ?? ""
            return notes.isEmpty ? nil : notes
        }
        
        // Avatar URL comes from feed data (already fetched from Firebase)
        // No need for special handling - feed includes current user's profile with avatarUrl
        private var computedAvatarUrl: String? {
            avatarUrl
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // Profile Image - inline to prevent recreation
                    if isCurrentUser {
                        // Current user - tapping should switch to Stamps tab
                        Button(action: {
                            shouldResetStampsNavigation = true
                            selectedTab = 2
                        }) {
                            ProfileImageView(
                                avatarUrl: computedAvatarUrl,
                                userId: userId,
                                size: 40
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Other user - navigate to their profile
                        Button(action: {
                            onUserTap(userId, "", userName)
                        }) {
                            ProfileImageView(
                                avatarUrl: computedAvatarUrl,
                                userId: userId,
                                size: 40
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Text content on the right (top-aligned)
                    VStack(alignment: .leading, spacing: 4) {
                        // First line: "Hiroo collected Golden Gate Park" - tappable to view stamp
                        Button(action: {
                            onStampTap(stamp)
                        }) {
                            Text("\(Text(userName).fontWeight(.bold)) collected \(Text(stampName).fontWeight(.bold))")
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Second line: Location (only show if not "Location not included")
                        if location != "Location not included" {
                            Text(location)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Third line: Date
                        Text(date)
                    .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Photos section - stamp + user photos using PhotoGalleryView
                PhotoGalleryView(
                    stampId: stamp.id,
                    maxPhotos: 5,
                    showStampImage: true,  // Always show stamp image section on feed (shows placeholder if empty)
                    stampImageName: stampImageName,
                    onStampImageTap: {
                        onStampTap(stamp)
                    },
                    userId: isCurrentUser ? nil : userId,  // Only pass userId for other users' posts
                    userPhotos: isCurrentUser ? nil : userPhotos,  // Only pass userPhotos for other users' posts
                    userPhotoPaths: isCurrentUser ? nil : userImagePaths  // Only pass paths for other users' posts
                )
                .environmentObject(stampsManager)
                .environmentObject(authManager)
                
                // Note section
                if let note = currentNote, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isCurrentUser {
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
                
                // Like and Comment row
                HStack(spacing: 16) {
                    // Like button (heart + count)
                    HStack(spacing: 4) {
                        // Heart icon - toggles like
                        Button(action: {
                            guard let currentUserId = authManager.userId else { return }
                            likeManager.toggleLike(
                                postId: postId,
                                stampId: stamp.id,
                                userId: currentUserId,
                                postOwnerId: userId
                            )
                        }) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(isLiked ? .red : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Count - shows likes list
                        Button(action: {
                            onShowLikes(postId, userId)
                        }) {
                            Text("\(currentLikeCount)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Comment button
                    Button(action: {
                        showComments = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "message")
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                            
                            Text("\(currentCommentCount)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Make entire area tappable for background tap
            .onTapGesture {
                // Background tap - open PostView
                // Specific buttons (profile, stamp, like, comment) will override this
                onPostTap(postId)
            }
            .sheet(isPresented: $showNotesEditor) {
                NotesEditorView(notes: $editingNotes) { savedNotes in
                    stampsManager.userCollection.updateNotes(for: stamp.id, notes: savedNotes)
                }
            }
            .sheet(isPresented: $showComments) {
                CommentView(
                    postId: postId,
                    postOwnerId: userId,
                    stampId: stamp.id,
                    commentManager: commentManager
                )
                .environmentObject(authManager)
                .environmentObject(profileManager)
                .onAppear {
                    activeSheetCount += 1
                }
                .onDisappear {
                    activeSheetCount -= 1
                    onSheetDismiss()
                }
            }
        }
    }
    
    // MARK: - Mail Fallback View
    struct MailFallbackView: View {
        let messageType: MailComposeView.MessageType
        @Environment(\.dismiss) var dismiss
        @State private var emailCopied = false
        
        var body: some View {
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "envelope.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 12) {
                        Text("Email Not Configured")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("To \(messageType == .feedback ? "send feedback" : "report a problem"), please contact us at:")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        // Email address with copy button
                        Button(action: {
                            UIPasteboard.general.string = "support@stampbook.app"
                            emailCopied = true
                            
                            // Reset after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                emailCopied = false
                            }
                        }) {
                            HStack {
                                Text("support@stampbook.app")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Image(systemName: emailCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                    .foregroundColor(emailCopied ? .green : .blue)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if emailCopied {
                            Text("Email copied to clipboard!")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }
                    
                    Text("You can send us an email from any email app installed on your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                    
                    Spacer()
                }
                .navigationTitle(messageType == .feedback ? "Send Feedback" : "Report Problem")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    /// Copies the App Store URL to clipboard and shows confirmation
    /// TODO: Update URL once app is published to App Store
    private func copyAppStoreUrl() {
        // TODO: Replace with actual App Store URL after app is published
        // Format: https://apps.apple.com/app/stampbook/idXXXXXXXXX
        let appStoreUrl = "https://apps.apple.com/app/stampbook/id123456789"
        UIPasteboard.general.string = appStoreUrl
        showAppStoreUrlCopied = true
    }
}
