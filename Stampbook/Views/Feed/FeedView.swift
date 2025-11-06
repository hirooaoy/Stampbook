import SwiftUI
import AuthenticationServices
import PhotosUI
import MessageUI

struct FeedView: View {
    // Debug flag - set to true to enable debug logging
    private let DEBUG_FEED = false
    
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var feedManager = FeedManager() // Persists across tab switches
    @StateObject private var likeManager = LikeManager() // Manages likes
    @StateObject private var commentManager = CommentManager() // Manages comments
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
    @State private var showAppStoreUrlCopied = false // Show confirmation when App Store URL is copied
    @State private var bannerState: ConnectionBanner.BannerState = .hidden // Connection status
    
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
        
        // Fetch like status for all posts to sync with cached state
        let postIds = postsToSync.map { $0.id }
        if !postIds.isEmpty {
            await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
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
                        // Logo on the left (app icon)
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        
                        Spacer()
                        
                        if authManager.isSignedIn {
                        // Signed-in menu: Search and ellipses
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
                                
                                // TODO: Implement notification system later
                                // Button(action: {
                                //     showNotifications = true
                                // }) {
                                //     Image(systemName: "bell")
                                //         .font(.system(size: 24))
                                //         .foregroundColor(.primary)
                                //         .frame(width: 44, height: 44)  // Larger tap target
                                //         .contentShape(Rectangle())     // Make entire frame tappable
                                // }
                                
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
                                
                                // Native Sign In with Apple button
                                Button(action: {
                                    authManager.signInWithApple()
                                }) {
                                    HStack {
                                        Image(systemName: "applelogo")
                                            .font(.system(size: 18, weight: .medium))
                                        Text("Sign in with Apple")
                                            .font(.system(size: 17, weight: .semibold))
                                    }
                                    .foregroundColor(colorScheme == .dark ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(colorScheme == .dark ? Color.white : Color.black)
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
        .alert("Notifications", isPresented: $showNotifications) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No new notifications")
        }
        .sheet(isPresented: $showUserSearch) {
            UserSearchView()
                .environmentObject(authManager)
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
                // Connection status banner
                ConnectionBanner(state: bannerState, context: .feed)
                
                // Feed error messages
                if let errorMessage = feedManager.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.top, bannerState == .hidden ? 8 : 0)
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
                        .padding(.top, (bannerState == .hidden && feedManager.errorMessage == nil) ? 8 : 0)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: errorMessage)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: bannerState)
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            handleConnectionChange(wasConnected: oldValue, isConnected: newValue)
        }
        .onAppear {
            // Set initial state if already offline
            if !networkMonitor.isConnected {
                bannerState = .offline
            }
        }
    }
    
    // MARK: - Banner Helpers
    
    private func handleConnectionChange(wasConnected: Bool, isConnected: Bool) {
        if !wasConnected && isConnected {
            // Going from offline to online
            bannerState = .reconnecting
            
            // Show "Reconnecting..." for 3 seconds, then hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                bannerState = .hidden
            }
        } else if wasConnected && !isConnected {
            // Going from online to offline
            bannerState = .offline
        } else if !isConnected && bannerState == .hidden {
            // Initial offline state
            bannerState = .offline
        }
    }
    
    // MARK: - Unified Feed Content View
    struct FeedContent: View {
        let feedType: FeedTab
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool
        @ObservedObject var feedManager: FeedManager
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        let debugEnabled: Bool
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @State private var hasLoadedOnce = false
        
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
                } else if posts.isEmpty && (feedManager.isLoading || !hasLoadedOnce) {
                    // Loading with no content - show skeleton posts
                    // Show skeleton during first load OR retry attempts to avoid flashing "No posts yet"
                    // This prevents confusing UX when retries happen after connection issues
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
                        PostView(
                            userId: post.userId,
                            userName: post.displayName,
                            avatarUrl: post.avatarUrl,
                            stampName: post.stampName,
                            stampImageName: post.stampImageName,
                            location: post.location,
                            date: post.date,
                            isCurrentUser: feedType == .onlyYou ? true : post.isCurrentUser,
                            stampId: post.stampId,
                            userPhotos: post.userPhotos,
                            note: post.note,
                            likeCount: post.likeCount,
                            commentCount: post.commentCount,
                            selectedTab: $selectedTab,
                            shouldResetStampsNavigation: $shouldResetStampsNavigation,
                            likeManager: likeManager,
                            commentManager: commentManager
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
                
                // Fetch like status for new posts
                let postIds = postsToSync.map { $0.id }
                if !postIds.isEmpty {
                    await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
                }
            }
        }
    }
    
    struct PostView: View {
        let userId: String
        let userName: String
        let avatarUrl: String?
        let stampName: String
        let stampImageName: String
        let location: String
        let date: String
        let isCurrentUser: Bool // true if this is the current user's post
        let stampId: String // The stamp ID to fetch from manager
        let userPhotos: [String] // Additional user photos (can be empty)
        let note: String? // Optional note
        let likeCount: Int
        let commentCount: Int
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool // Binding to reset StampsView navigation
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        @State private var navigateToStampDetail: Bool = false
        @State private var showNotesEditor: Bool = false
        @State private var showComments: Bool = false
        @State private var editingNotes: String = ""
        @State private var stamp: Stamp? // Lazy-loaded stamp
        @State private var isLoadingStamp = false
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @EnvironmentObject var profileManager: ProfileManager
        
        // Computed properties for real-time updates
        private var postId: String {
            "\(userId)-\(stampId)"
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
                        NavigationLink(destination: UserProfileView(userId: userId, username: "", displayName: userName)) {
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
                            loadStampAndNavigate()
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
                    stampId: stampId,
                    maxPhotos: 5,
                    showStampImage: true,  // Always show stamp image section on feed (shows placeholder if empty)
                    stampImageName: stampImageName,
                    onStampImageTap: {
                        loadStampAndNavigate()
                    }
                )
                .environmentObject(stampsManager)
                .environmentObject(authManager)
                
                // Note section
                if let note = note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isCurrentUser {
                    // Add Notes button (only for current user)
                    Button(action: {
                        editingNotes = ""
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
                    // Like button
                    Button(action: {
                        guard let currentUserId = authManager.userId else { return }
                        likeManager.toggleLike(
                            postId: postId,
                            stampId: stampId,
                            userId: currentUserId,
                            postOwnerId: userId
                        )
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundColor(isLiked ? .red : .primary)
                            
                            Text("\(currentLikeCount)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
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
            .onAppear {
                // Initialize comment count from feed data
                // (Like counts are initialized in bulk after feed load to prevent race conditions)
                commentManager.updateCommentCount(postId: postId, count: commentCount, forceUpdate: true)
                
                // PREFETCH: Load stamp data in background when post appears
                // Makes navigation instant when user taps (Instagram pattern)
                prefetchStampData()
            }
            .navigationDestination(isPresented: $navigateToStampDetail) {
                if let stamp = stamp {
                    StampDetailView(
                        stamp: stamp,
                        userLocation: nil,
                        showBackButton: true
                    )
                }
            }
            .sheet(isPresented: $showNotesEditor) {
                NotesEditorView(notes: $editingNotes) { savedNotes in
                    stampsManager.userCollection.updateNotes(for: stampId, notes: savedNotes)
                }
            }
            .sheet(isPresented: $showComments) {
                CommentView(
                    postId: postId,
                    postOwnerId: userId,
                    stampId: stampId,
                    commentManager: commentManager
                )
                .environmentObject(authManager)
                .environmentObject(profileManager)
            }
        }
        
        private func prefetchStampData() {
            // Skip if already loaded or loading
            guard stamp == nil, !isLoadingStamp else { return }
            
            // FAST PATH: Check cache synchronously first (instant if cached)
            // Avoids Task overhead and network delays when stamp is already in memory
            if let cached = stampsManager.getCachedStamp(id: stampId) {
                stamp = cached
                return
            }
            
            // SLOW PATH: Fetch from network in background
            // This prefetch makes navigation instant when user taps (Instagram pattern)
            isLoadingStamp = true
            Task {
                let stamps = await stampsManager.fetchStamps(ids: [stampId])
                await MainActor.run {
                    stamp = stamps.first
                    isLoadingStamp = false
                }
            }
        }
        
        private func loadStampAndNavigate() {
            // If stamp is already prefetched, navigate immediately
            if let _ = stamp {
                navigateToStampDetail = true
                return
            }
            
            guard !isLoadingStamp else { return }
            
            isLoadingStamp = true
            
            Task {
                // FALLBACK: Fetch stamp only if prefetch didn't complete
                let stamps = await stampsManager.fetchStamps(ids: [stampId])
                
                await MainActor.run {
                    stamp = stamps.first
                    isLoadingStamp = false
                    
                    if stamp != nil {
                        navigateToStampDetail = true
                    }
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
