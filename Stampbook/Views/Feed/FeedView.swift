import SwiftUI
import AuthenticationServices
import PhotosUI
import MessageUI

struct FeedView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var profileManager: ProfileManager
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
    
    enum FeedTab: String, CaseIterable {
        case all = "All"
        case onlyYou = "Only Yours"
    }
    
    /// Refresh feed data without clearing cached statistics
    private func refreshFeedData() async {
        // Just refresh the feed - no need to sync user's collected stamps
        // The feed will show the latest posts from Firebase
        guard let userId = authManager.userId else { return }
        await feedManager.refresh(userId: userId, stampsManager: stampsManager)
        
        // Fetch like status for all posts to sync with cached state
        let postIds = feedManager.feedPosts.map { $0.id }
        if !postIds.isEmpty {
            await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
        }
    }
    
    var body: some View {
        NavigationStack {
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
                        // Signed-in menu: Search, notification, and ellipses
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
                            
                            Button(action: {
                                showNotifications = true
                            }) {
                                Image(systemName: "bell")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)  // Larger tap target
                                    .contentShape(Rectangle())     // Make entire frame tappable
                            }
                            
                            Menu {
                                Button(action: {
                                    // TODO: Open about (will include Privacy Policy and Terms of Service inside)
                                    print("About Stampbook tapped")
                                }) {
                                    Label("About Stampbook", systemImage: "info.circle")
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    // TODO: Open business info
                                    print("For Local Business tapped")
                                }) {
                                    Label("For Local Business", systemImage: "storefront")
                                }
                                
                                Button(action: {
                                    // TODO: Open creator info
                                    print("For Creators tapped")
                                }) {
                                    Label("For Creators", systemImage: "sparkles")
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    showProblemReport = true
                                }) {
                                    Label("Report a Problem", systemImage: "exclamationmark.bubble")
                                }
                                
                                Button(action: {
                                    showFeedback = true
                                }) {
                                    Label("Send Feedback", systemImage: "envelope")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive, action: {
                                    showSignOutConfirmation = true
                                }) {
                                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
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
                            Button(action: {
                                // TODO: Open about (will include Privacy Policy and Terms of Service inside)
                                print("About Stampbook tapped")
                            }) {
                                Label("About Stampbook", systemImage: "info.circle")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                // TODO: Open business info
                                print("For Local Business tapped")
                            }) {
                                Label("For Local Business", systemImage: "storefront")
                            }
                            
                            Button(action: {
                                // TODO: Open creator info
                                print("For Creators tapped")
                            }) {
                                Label("For Creators", systemImage: "sparkles")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showProblemReport = true
                            }) {
                                Label("Report a Problem", systemImage: "exclamationmark.bubble")
                            }
                            
                            Button(action: {
                                showFeedback = true
                            }) {
                                Label("Send Feedback", systemImage: "envelope")
                            }
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
                ScrollView {
                    VStack(spacing: 0) {
                        // Sign-in prompt (only when signed out)
                        if !authManager.isSignedIn {
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
                                    SignInWithAppleButton(.signIn) { _ in }
                                        onCompletion: { _ in }
                                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                        .frame(height: 50)
                                        .cornerRadius(8)
                                        .allowsHitTesting(false)
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 8)
                                .padding(.bottom, 40)
                            }
                        } else {
                            // Signed in - show segmented control and content
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
                                if selectedFeedTab == .all {
                                    AllFeedContent(selectedTab: $selectedTab, shouldResetStampsNavigation: $shouldResetStampsNavigation, feedManager: feedManager, likeManager: likeManager, commentManager: commentManager)
                                } else {
                                    OnlyYouContent(selectedTab: $selectedTab, shouldResetStampsNavigation: $shouldResetStampsNavigation, feedManager: feedManager, likeManager: likeManager, commentManager: commentManager)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await refreshFeedData()
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
                .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                } message: {
                    Text("Are you sure you want to sign out?")
                }
                .overlay(alignment: .top) {
                    // Toast for like errors
                    if let errorMessage = likeManager.errorMessage {
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
    }
    
    struct AllFeedContent: View {
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool
        @ObservedObject var feedManager: FeedManager
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @State private var hasLoadedOnce = false
        
        var body: some View {
            VStack(spacing: 20) {
                // SIMPLE LOADING PATTERN: One consistent rule
                if !authManager.isSignedIn {
                    // Not signed in - show sign-in prompt (handled by parent)
                    EmptyView()
                } else if feedManager.feedPosts.isEmpty && !hasLoadedOnce {
                    // Loading with no content - show skeleton posts
                    // Show skeleton only if we've never successfully loaded
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonPostView()
                        
                        if index < 2 {
                            Divider()
                        }
                    }
                } else if feedManager.feedPosts.isEmpty {
                    // Empty state (no posts after loading)
                    VStack(spacing: 16) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No posts yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Follow others to see their stamp collections")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                } else {
                    // Show posts (from cache or fresh data)
                    ForEach(Array(feedManager.feedPosts.enumerated()), id: \.element.id) { index, post in
                        PostView(
                            userId: post.userId,
                            userName: post.displayName,
                            avatarUrl: post.avatarUrl,
                            stampName: post.stampName,
                            stampImageName: post.stampImageName,
                            location: post.location,
                            date: post.date,
                            isCurrentUser: post.isCurrentUser,
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
                        
                        if index < feedManager.feedPosts.count - 1 {
                            Divider()
                        }
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
            .onAppear {
                loadFeedIfNeeded()
            }
        }
        
        /// Load feed with smart caching
        private func loadFeedIfNeeded() {
            print("🔍 [DEBUG] AllFeedContent.loadFeedIfNeeded called")
            guard let userId = authManager.userId else { return }
            guard authManager.isSignedIn else { return }
            
            print("🔍 [DEBUG] AllFeedContent calling feedManager.loadFeed()")
            Task {
                await feedManager.loadFeed(
                    userId: userId,
                    stampsManager: stampsManager,
                    forceRefresh: false
                )
                
                // Fetch like status for all posts to sync with cached state
                let postIds = feedManager.feedPosts.map { $0.id }
                if !postIds.isEmpty {
                    await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
                }
                
                // Mark that we've attempted to load at least once
                await MainActor.run {
                    hasLoadedOnce = true
                }
            }
        }
    }
    
    struct OnlyYouContent: View {
        @Binding var selectedTab: Int
        @Binding var shouldResetStampsNavigation: Bool
        @ObservedObject var feedManager: FeedManager
        @ObservedObject var likeManager: LikeManager
        @ObservedObject var commentManager: CommentManager
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @State private var hasLoadedOnce = false
        
        var body: some View {
            VStack(spacing: 20) {
                // SIMPLE LOADING PATTERN: Same as All tab - consistent!
                if !authManager.isSignedIn {
                    // Not signed in - show sign-in prompt (handled by parent)
                    EmptyView()
                } else if feedManager.myPosts.isEmpty && !hasLoadedOnce {
                    // Loading with no content - show skeleton posts
                    // Show skeleton only if we've never successfully loaded
                    ForEach(0..<3, id: \.self) { index in
                        SkeletonPostView()
                        
                        if index < 2 {
                            Divider()
                        }
                    }
                } else if feedManager.myPosts.isEmpty {
                    // Empty state (no posts after loading)
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No stamps collected yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Start exploring to collect your first stamp!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                } else {
                    // Show filtered posts from feedManager
                    ForEach(Array(feedManager.myPosts.enumerated()), id: \.element.id) { index, post in
                        PostView(
                            userId: post.userId,
                            userName: post.displayName,
                            avatarUrl: post.avatarUrl,
                            stampName: post.stampName,
                            stampImageName: post.stampImageName,
                            location: post.location,
                            date: post.date,
                            isCurrentUser: true,
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
                        
                        if index < feedManager.myPosts.count - 1 {
                            Divider()
                        }
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
            .onAppear {
                loadFeedIfNeeded()
            }
        }
        
        /// Load feed with smart caching (reuses data from All tab if available)
        private func loadFeedIfNeeded() {
            print("🔍 [DEBUG] OnlyYouContent.loadFeedIfNeeded called")
            guard let userId = authManager.userId else { return }
            guard authManager.isSignedIn else { return }
            
            print("🔍 [DEBUG] OnlyYouContent calling feedManager.loadFeed()")
            // If All tab already loaded, myPosts is instantly available (filtered from cache)
            // Otherwise, trigger feed load which will populate both All and Only Yours
            Task {
                await feedManager.loadFeed(
                    userId: userId,
                    stampsManager: stampsManager,
                    forceRefresh: false
                )
                
                // Fetch like status for all posts to sync with cached state
                let postIds = feedManager.feedPosts.map { $0.id }
                if !postIds.isEmpty {
                    await likeManager.fetchLikeStatus(postIds: postIds, userId: userId)
                }
                
                // Mark that we've attempted to load at least once
                await MainActor.run {
                    hasLoadedOnce = true
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
                        
                        // Second line: Location
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
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
                    showStampImage: !stampImageName.isEmpty,
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
                        HStack(spacing: 8) {
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
                // Initialize like and comment counts from feed data
                likeManager.updateLikeCount(postId: postId, count: likeCount)
                commentManager.updateCommentCount(postId: postId, count: commentCount)
                
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
        
        private func buildCollectionText() -> AttributedString {
            var result = AttributedString()
            
            // Bold user name
            var userNameAttr = AttributedString(userName)
            userNameAttr.font = .body.bold()
            result += userNameAttr
            
            // Regular "collected"
            result += AttributedString(" collected ")
            
            // Bold stamp name (make it interactive-looking)
            var stampNameAttr = AttributedString(stampName)
            stampNameAttr.font = .body.bold()
            result += stampNameAttr
            
            return result
        }
        
        private func buildCollectionTextButton() -> some View {
            Button(action: {
                loadStampAndNavigate()
            }) {
                Text(buildCollectionText())
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        
        private func prefetchStampData() {
            // Skip if already loaded or loading
            guard stamp == nil, !isLoadingStamp else { return }
            
            // FAST PATH: Check cache synchronously first (0.000s if cached)
            // Avoids Task overhead and network delays when stamp is already in memory
            if let cached = stampsManager.getCachedStamp(id: stampId) {
                stamp = cached
                print("⚡️ [PostView] Instant cache hit: \(stampId)")
                return
            }
            
            isLoadingStamp = true
            
            Task {
                let prefetchStart = CFAbsoluteTimeGetCurrent()
                
                // OPTIMIZED: Shorter timeout now that cache check is separate
                // If not cached + slow network (Xcode debug), fail fast
                do {
                    let stamps = try await withThrowingTaskGroup(of: [Stamp].self) { group in
                        // Add prefetch task with 2 second timeout (shorter now that cache is instant)
                        group.addTask {
                            let stamps = await stampsManager.fetchStamps(ids: [stampId])
                            return stamps
                        }
                        
                        // Add timeout task - 2s for uncached fetches
                        group.addTask {
                            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                            throw TimeoutError()
                        }
                        
                        // Return first result (either stamps or timeout)
                        if let result = try await group.next() {
                            group.cancelAll()
                            return result
                        }
                        return []
                    }
                    
                    let prefetchTime = CFAbsoluteTimeGetCurrent() - prefetchStart
                    print("⏱️ [PostView] Stamp prefetch: \(String(format: "%.3f", prefetchTime))s for \(stampId)")
                    
                    await MainActor.run {
                        stamp = stamps.first
                        isLoadingStamp = false
                    }
                } catch {
                    // Timeout or error - fail gracefully, stamp will load on tap
                    let prefetchTime = CFAbsoluteTimeGetCurrent() - prefetchStart
                    print("⏱️ [PostView] Stamp prefetch timeout: \(String(format: "%.3f", prefetchTime))s for \(stampId)")
                    
                    await MainActor.run {
                        isLoadingStamp = false
                    }
                }
            }
        }
        
        private struct TimeoutError: Error {}
        
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
                print("🎯 [FeedView] Fetching stamp for navigation: \(stampId)")
                
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
}

