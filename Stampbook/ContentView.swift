import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared profile manager
    @EnvironmentObject var deepLinkManager: DeepLinkManager // Deep link handler for notifications
    @StateObject private var stampsManager: StampsManager = {
        Logger.debug("Creating StampsManager...")
        let manager = StampsManager()
        Logger.debug("StampsManager created")
        return manager
    }()
    @StateObject private var mapCoordinator = MapCoordinator() // Coordinates map navigation
    @State private var selectedTab = 0
    @State private var previousTab = 0 // Track previous tab
    @State private var shouldResetStampsNavigation = false // Flag to reset StampsView navigation
    @State private var deepLinkedStamp: Stamp? = nil // Stamp to show from deep link
    
    // Safety net for broken account state (signed in but no profile cached)
    @State private var isLoadingMissingProfile = false
    @State private var profileLoadError: String? = nil
    
    // Profile setup page for first-time users
    @State private var showProfileSetupPage = false
    @State private var hasShownProfileSetup = false
    
    var body: some View {
        // Show splash while checking auth state
        if authManager.isCheckingAuth {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
            }
        } else if isLoadingMissingProfile {
            // Safety net: Loading missing profile
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading your profile...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        } else if let error = profileLoadError {
            // Safety net: Profile load failed
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text("Connection Issue")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button("Try Again") {
                    Task {
                        await loadMissingProfile()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Sign Out") {
                    authManager.signOut()
                    profileLoadError = nil
                }
                .buttonStyle(.bordered)
            }
            .padding()
        } else if showProfileSetupPage {
            // Show profile setup for new users (full page, not a sheet)
            ProfileSetupPage(onDismiss: {
                showProfileSetupPage = false
                selectedTab = 2  // Take new users to StampsView to explore collections
            })
            .environmentObject(authManager)
            .environmentObject(profileManager)
            .transition(.opacity)  // Fade in smoothly
        } else {
            // Auth check complete - show main app (TabBar always visible)
        TabView(selection: $selectedTab) {
            FeedView(selectedTab: $selectedTab, shouldResetStampsNavigation: $shouldResetStampsNavigation)
                .tabItem {
                    Label("Feed", systemImage: "person.2.fill")
                }
                .tag(0)
            
            NavigationStack {
                MapView()
                    .environmentObject(mapCoordinator)
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }
                .tag(1)
            
            StampsView(shouldResetNavigation: $shouldResetStampsNavigation)
                .tabItem {
                    Label("Stamps", systemImage: "book.closed.fill")
                }
                .tag(2)
        }
        .environmentObject(stampsManager)
        .environmentObject(mapCoordinator)
        .transition(.opacity)  // Fade in smoothly when appearing
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
        }
        .onChange(of: mapCoordinator.shouldSwitchToMapTab) { _, shouldSwitch in
            if shouldSwitch {
                Logger.debug("Switching to Map tab (tab 1)")
                selectedTab = 1 // Switch to Map tab
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenPost"))) { notification in
            // Handle notification banner taps for post-related notifications
            guard let postId = notification.userInfo?["postId"] as? String else { return }
            let commentId = notification.userInfo?["commentId"] as? String
            
            Logger.info("🔔 [ContentView] Received OpenPost notification: postId=\(postId), commentId=\(commentId ?? "nil")", category: "DeepLink")
            deepLinkManager.handlePostNotification(postId: postId, commentId: commentId)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenProfile"))) { notification in
            // Handle notification banner taps for profile-related notifications (follows)
            guard let userId = notification.userInfo?["userId"] as? String else { return }
            
            Logger.info("🔔 [ContentView] Received OpenProfile notification: userId=\(userId)", category: "DeepLink")
            deepLinkManager.handleProfileNotification(userId: userId)
        }
        .onAppear {
            Logger.debug("onAppear started")
            // Set current user on initial load
            stampsManager.setCurrentUser(authManager.userId, profileManager: profileManager)
            // Note: ProfileManager is linked to AuthManager in StampbookApp.body (WindowGroup.onAppear)
            Logger.debug("onAppear completed")
        }
        .task {
            // Safety net: Check for broken account state on launch
            await loadMissingProfile()
        }
        .onChange(of: authManager.isSignedIn) { oldValue, isSignedIn in
            Logger.info("Auth state changed - isSignedIn: \(isSignedIn)", category: "ContentView")
            
            if !isSignedIn {
                // User signed out - clear profile
                Logger.info("User signed out, clearing profile", category: "ContentView")
                profileManager.clearProfile()
            } else if !oldValue && isSignedIn {
                // User just signed in (false → true)
                checkIfShouldShowProfileSetup()
            }
            // Note: AuthManager handles profile loading on sign-in
        }
        .onChange(of: authManager.userId) { _, newUserId in
            Logger.info("UserId changed: \(newUserId ?? "nil")", category: "ContentView")
            
            // Update stamps manager when user changes (sign in/out or switch user)
            stampsManager.setCurrentUser(newUserId, profileManager: profileManager)
            
            // Clear profile if signed out
            if !authManager.isSignedIn {
                Logger.info("Clearing profile (signed out)", category: "ContentView")
                profileManager.clearProfile()
            }
                // Note: AuthManager handles profile loading via ProfileManager
        }
        .onChange(of: profileManager.currentUserProfile) { _, newProfile in
            // Check if we should show profile setup when profile loads
            // This catches the case where auth state changes before profile loads
            if authManager.isSignedIn && newProfile != nil {
                checkIfShouldShowProfileSetup()
            }
        }
        .fullScreenCover(item: $deepLinkedStamp) { stamp in
            // Present stamp detail from widget deep link (works from any tab)
            NavigationStack {
                StampDetailView(
                    stamp: stamp,
                    isCollected: stampsManager.isCollected(stamp),
                    userLocation: nil,
                    showBackButton: false
                )
                .sheetContentBackground()
                .environmentObject(stampsManager)
                .environmentObject(authManager)
                .environmentObject(MapCoordinator())
                .toolbar(.visible, for: .tabBar)
            }
        }
        }
    }
    
    // MARK: - Deep Linking
    
    /// Handle deep links from widget (stampbook://stamp/{stampId})
    private func handleDeepLink(_ url: URL) {
        Logger.debug("Received deep link: \(url)")
        
        // Parse URL: stampbook://stamp/{stampId}
        guard url.scheme == "stampbook",
              url.host() == "stamp",
              let stampId = url.pathComponents.dropFirst().first else {
            Logger.warning("Invalid deep link format: \(url)")
            return
        }
        
        Logger.info("Opening stamp from widget: \(stampId)", category: "DeepLink")
        
        // Fetch the stamp and present it at ContentView level
        // This works from any tab without needing StampsView to be initialized
        Task {
            let stamps = await stampsManager.fetchStamps(ids: [stampId])
            await MainActor.run {
                if let stamp = stamps.first {
                    deepLinkedStamp = stamp // Opens the fullScreenCover
                    Logger.success("✅ [ContentView] Opened stamp detail for: \(stamp.name)", category: "DeepLink")
                } else {
                    Logger.warning("⚠️ [ContentView] Could not find stamp: \(stampId)", category: "DeepLink")
                }
            }
        }
    }
    
    // MARK: - Profile Setup Check
    
    /// Check if we should show the profile setup page for new users
    private func checkIfShouldShowProfileSetup() {
        // Only check once per session
        guard !hasShownProfileSetup else { return }
        
        // Wait for profile to load
        guard let profile = profileManager.currentUserProfile else {
            return
        }
        
        // For existing users: if account older than 5 min, they already onboarded
        let accountAge = Date().timeIntervalSince(profile.createdAt)
        if accountAge > 300 && !profile.hasSeenOnboarding {
            // Existing user without the field, don't show
            return
        }
        
        // New users: show if they haven't seen onboarding
        if !profile.hasSeenOnboarding {
            Logger.info("🎯 [ContentView] Showing profile setup for new user", category: "ContentView")
            
            // Animate the transition smoothly
            withAnimation(.easeInOut(duration: 0.3)) {
                showProfileSetupPage = true
                hasShownProfileSetup = true
            }
        }
    }
    
    // MARK: - Safety Net for Broken Account State
    
    /// Load profile if user is signed in but has no cached profile
    /// This catches edge cases like force-killing during signup or cache expiration
    private func loadMissingProfile() async {
        // Check if user is in broken state (signed in but no profile cached)
        guard authManager.isSignedIn,
              let userId = authManager.userId,
              profileManager.currentUserProfile == nil,
              !profileManager.isLoadingProfile else { // Don't interfere if profile is already loading
            return // State is fine or already being handled
        }
        
        Logger.warning("Detected broken account state - user signed in but no profile cached", category: "ContentView")
        Logger.info("Loading profile to fix broken state...", category: "ContentView")
        
        await MainActor.run {
            isLoadingMissingProfile = true
            profileLoadError = nil
        }
        
        do {
            let profile = try await FirebaseService.shared.fetchUserProfile(userId: userId)
            await MainActor.run {
                profileManager.updateProfile(profile)
                isLoadingMissingProfile = false
            }
            Logger.success("Broken state fixed - profile loaded successfully", category: "ContentView")
        } catch {
            Logger.error("Failed to load missing profile", error: error, category: "ContentView")
            await MainActor.run {
                isLoadingMissingProfile = false
                profileLoadError = "Couldn't load your profile. Check your internet connection and try again."
            }
        }
    }
}
