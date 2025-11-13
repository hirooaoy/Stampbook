import SwiftUI
import AuthenticationServices
import MessageUI

struct StampsView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared instance - no more loading!
    @EnvironmentObject var followManager: FollowManager
    @Environment(\.colorScheme) var colorScheme
    @Binding var shouldResetNavigation: Bool // Binding to reset navigation when tab is selected
    @State private var selectedTab: StampTab = .all
    
    // SHEET MANAGEMENT: This view has 12 sheet modifiers which triggers SwiftUI warnings
    // ("Currently, only presenting a single sheet is supported"). These warnings are COSMETIC
    // and can be safely IGNORED. The sheets work correctly - they present one at a time as
    // expected. Decision made Nov 2025 to defer coordinator pattern refactor until post-launch
    // to avoid unnecessary risk at MVP stage. See: CROSS_REFERENCE_RISK_ANALYSIS.md
    @State private var showEditProfile = false
    @State private var showFeedback = false
    @State private var showProblemReport = false
    @State private var showAccountDeletion = false
    @State private var showDataDownload = false
    @State private var showSignOutConfirmation = false
    @State private var showAboutStampbook = false
    @State private var showForLocalBusiness = false
    @State private var showForCreators = false
    @State private var showAppStoreUrlCopied = false // Show confirmation when App Store URL is copied
    @State private var navigationPath = NavigationPath() // Track navigation stack
    @State private var welcomeStamp: Stamp? // Store the fetched welcome stamp (nil = sheet closed, non-nil = sheet open)
    @State private var showInviteCodeSheet = false // Show invite code sheet for signed-out users
    // @State private var hasAttemptedRankLoad = false // TODO: POST-MVP - Rank loading disabled
    
    enum StampTab: String, CaseIterable {
        case all = "Your Stamps"
        case collections = "Collections"
    }
    
    // Navigation destination types
    struct FollowListDestination: Hashable {
        let userId: String
        let userDisplayName: String
        let initialTab: FollowListView.FollowTab
    }
    
    var body: some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                // Refresh profile when app becomes active to get latest follow counts
                // Uses 5-minute cache for cost efficiency (respects cache timeout)
                if authManager.isSignedIn, let userId = authManager.userId {
                    print("📱 [StampsView] App became active - refreshing profile for latest follow counts")
                    Task {
                        do {
                            let profile = try await FirebaseService.shared.fetchUserProfile(userId: userId, forceRefresh: false)
                            await MainActor.run {
                                profileManager.currentUserProfile = profile
                                print("✅ [StampsView] Profile refreshed: followers=\(profile.followerCount), following=\(profile.followingCount)")
                            }
                        } catch {
                            print("⚠️ [StampsView] Failed to refresh profile on app active: \(error)")
                        }
                    }
                }
            }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            if authManager.isSignedIn {
                // Signed-in: Show username
                if let profile = profileManager.currentUserProfile {
                    Text("@\(profile.username)")
                        .font(.headline)
                        .fontWeight(.semibold)
                } else {
                    Text("@user")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            // Signed-out: Show nothing (no logo)
            
            Spacer()
            
            if authManager.isSignedIn {
                signedInMenuButtons
            } else {
                signedOutMenuButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
    
    // MARK: - Signed-in Menu Buttons
    private var signedInMenuButtons: some View {
        HStack(spacing: 8) {
            // Gift icon - only show if user hasn't claimed welcome stamp
            if !stampsManager.hasClaimedWelcomeStamp() {
                Button(action: {
                    // Fetch welcome stamp and show it
                    Task {
                        let stamps = await stampsManager.fetchStamps(ids: ["your-first-stamp"])
                        await MainActor.run {
                            // Setting welcomeStamp automatically opens the sheet
                            welcomeStamp = stamps.first
                        }
                    }
                }) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)  // Larger tap target
                        .contentShape(Rectangle())     // Make entire frame tappable
                }
            }
            
            // Edit Profile Button - Opens ProfileEditView sheet
            Button(action: {
                showEditProfile = true
            }) {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)  // Larger tap target
                    .contentShape(Rectangle())     // Make entire frame tappable
            }
            .disabled(profileManager.currentUserProfile == nil)
            
            // More Options Menu
            signedInOptionsMenu
        }
    }
    
    // MARK: - Signed-in Options Menu
    private var signedInOptionsMenu: some View {
        Menu {
            Button(action: {
                showAboutStampbook = true
            }) {
                Label("About Stampbook", systemImage: "info.circle")
            }
            
            // TODO: Add back later
            // Button(action: {
            //     copyAppStoreUrl()
            // }) {
            //     Label("Share app", systemImage: "square.and.arrow.up")
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
            
            Divider()
            
            Button(action: {
                showDataDownload = true
            }) {
                Label("Download my data", systemImage: "square.and.arrow.down")
            }
            
            Button(action: {
                showAccountDeletion = true
            }) {
                Label("Delete account", systemImage: "trash")
            }
            
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
    
    // MARK: - Signed-in Content
    private var signedInContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileSection
                statsCardsSection
                
                // Native segmented control
                Picker("View", selection: $selectedTab) {
                    ForEach(StampTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue)
                            .font(.system(size: 24, weight: .medium))
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // Content based on selected tab
                if selectedTab == .all {
                    AllStampsContent()
                } else {
                    CollectionsContent()
                }
            }
        }
        .refreshable {
            // Just refresh profile stats - user's stamps are already synced
            // No need to refetch all collected stamps from Firestore every time
            await profileManager.refresh()
        }
    }
    
    // MARK: - Signed-out Content
    private var signedOutContent: some View {
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
                    
                    Text("Sign in to start your stamp collection and create your own stampbook")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // Get Started button
                Button(action: {
                    showInviteCodeSheet = true
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Profile Section
    private var profileSection: some View {
        HStack(spacing: 12) {
            // Profile picture
            ProfileImageView(
                avatarUrl: profileManager.currentUserProfile?.avatarUrl,
                userId: authManager.userId ?? "",
                size: 64
            )
            
            // Name and bio
            VStack(alignment: .leading, spacing: 4) {
                if let profile = profileManager.currentUserProfile {
                    Text(profile.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    if !profile.bio.isEmpty {
                        Text(profile.bio)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    // Skeleton loading state - gray rectangles
                    VStack(alignment: .leading, spacing: 4) {
                        // Display name skeleton
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 150, height: 22)
                        
                        // Bio skeleton (2 lines)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 16)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 180, height: 16)
                    }
                    .redacted(reason: .placeholder)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
    
    // MARK: - Stats Cards Section
    private var statsCardsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                countriesCard
                followersCard
                followingCard
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Countries Card
    private var countriesCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Countries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(profileManager.currentUserProfile?.uniqueCountriesVisited ?? 0)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 160)
        .frame(height: 70)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Followers Card
    private var followersCard: some View {
        let userId = authManager.userId ?? ""
        let cachedCount = followManager.followCounts[userId]?.followers
        let profileCount = profileManager.currentUserProfile?.followerCount
        let displayCount = cachedCount ?? profileCount ?? 0
        
        let _ = print("🎨 [StampsView.followersCard] Rendering...")
        let _ = print("🎨 [StampsView.followersCard]   userId: \(userId)")
        let _ = print("🎨 [StampsView.followersCard]   cachedCount: \(cachedCount ?? -1)")
        let _ = print("🎨 [StampsView.followersCard]   profileCount: \(profileCount ?? -1)")
        let _ = print("🎨 [StampsView.followersCard]   displayCount: \(displayCount)")
        
        return NavigationLink(value: FollowListDestination(
            userId: userId,
            userDisplayName: profileManager.currentUserProfile?.displayName ?? "User",
            initialTab: .followers
        )) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // Use cached count if available, fallback to profile
                    Text("\(displayCount)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 160)
            .frame(height: 70)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Following Card
    private var followingCard: some View {
        let userId = authManager.userId ?? ""
        let cachedCount = followManager.followCounts[userId]?.following
        let profileCount = profileManager.currentUserProfile?.followingCount
        let displayCount = cachedCount ?? profileCount ?? 0
        
        let _ = print("🎨 [StampsView.followingCard] Rendering...")
        let _ = print("🎨 [StampsView.followingCard]   userId: \(userId)")
        let _ = print("🎨 [StampsView.followingCard]   cachedCount: \(cachedCount ?? -1)")
        let _ = print("🎨 [StampsView.followingCard]   profileCount: \(profileCount ?? -1)")
        let _ = print("🎨 [StampsView.followingCard]   displayCount: \(displayCount)")
        
        return NavigationLink(value: FollowListDestination(
            userId: userId,
            userDisplayName: profileManager.currentUserProfile?.displayName ?? "User",
            initialTab: .following
        )) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // Use cached count if available, fallback to profile
                    Text("\(displayCount)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 160)
            .frame(height: 70)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Signed-out Menu Button
    private var signedOutMenuButton: some View {
        Menu {
            Button(action: {
                showAboutStampbook = true
            }) {
                Label("About Stampbook", systemImage: "info.circle")
            }
            
            // TODO: Add back later
            // Button(action: {
            //     copyAppStoreUrl()
            // }) {
            //     Label("Share app", systemImage: "square.and.arrow.up")
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 24))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)  // Larger tap target
                .contentShape(Rectangle())     // Make entire frame tappable
        }
    }
    
    private var content: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                topBar
                
                // Scrollable content
                if authManager.isSignedIn {
                    signedInContent
                } else {
                    signedOutContent
                }
            }
            .navigationDestination(for: FollowListDestination.self) { destination in
                FollowListView(
                    userId: destination.userId,
                    userDisplayName: destination.userDisplayName,
                    initialTab: destination.initialTab
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // MARK: - Cache Follow Counts
        // Initialize cache when profile loads (only if cache is empty)
        .onAppear {
            print("📱 [StampsView] onAppear - checking if profile needs refresh")
            
            // Refresh profile when view appears to get latest follow counts
            // Uses 5-minute cache for cost efficiency (80-95% read savings)
            // User can pull-to-refresh for instant updates if needed
            if authManager.isSignedIn, let userId = authManager.userId {
                print("📱 [StampsView] Refreshing profile for latest follow counts")
                Task {
                    do {
                        let profile = try await FirebaseService.shared.fetchUserProfile(userId: userId, forceRefresh: false)
                        await MainActor.run {
                            profileManager.currentUserProfile = profile
                            print("✅ [StampsView] Profile refreshed on appear: followers=\(profile.followerCount), following=\(profile.followingCount)")
                        }
                    } catch {
                        print("⚠️ [StampsView] Failed to refresh profile on appear: \(error)")
                    }
                }
            }
            
            if let profile = profileManager.currentUserProfile, let userId = authManager.userId {
                // Only initialize cache if it's not already set (to avoid overwriting fresh counts from follow actions)
                if followManager.followCounts[userId] == nil {
                    print("📊 [StampsView] Initializing follow counts cache on appear: userId=\(userId)")
                    print("📊 [StampsView] Profile counts: followers=\(profile.followerCount), following=\(profile.followingCount)")
                    followManager.updateFollowCounts(userId: userId, followerCount: profile.followerCount, followingCount: profile.followingCount)
                } else {
                    print("📊 [StampsView] Follow counts cache already exists, not overwriting")
                }
            }
        }
        // Update cache when profile changes
        .onChange(of: profileManager.currentUserProfile) { oldProfile, newProfile in
            print("📊 [StampsView] ========================================")
            print("📊 [StampsView] onChange(profileManager.currentUserProfile) FIRED")
            print("📊 [StampsView] Old profile: \(oldProfile?.username ?? "nil")")
            print("📊 [StampsView]   Old followers: \(oldProfile?.followerCount ?? -1)")
            print("📊 [StampsView]   Old following: \(oldProfile?.followingCount ?? -1)")
            print("📊 [StampsView] New profile: \(newProfile?.username ?? "nil")")
            print("📊 [StampsView]   New followers: \(newProfile?.followerCount ?? -1)")
            print("📊 [StampsView]   New following: \(newProfile?.followingCount ?? -1)")
            
            if let profile = newProfile, let userId = authManager.userId {
                print("📊 [StampsView] Auth userId: \(userId)")
                print("📊 [StampsView] Current followManager.followCounts cache:")
                for (cachedUserId, counts) in followManager.followCounts {
                    print("📊 [StampsView]   \(cachedUserId): followers=\(counts.followers), following=\(counts.following)")
                }
                
                // Check if follow counts actually changed (indicating a follow/unfollow occurred)
                let oldFollowerCount = oldProfile?.followerCount ?? 0
                let oldFollowingCount = oldProfile?.followingCount ?? 0
                let countsChanged = profile.followerCount != oldFollowerCount || profile.followingCount != oldFollowingCount
                
                print("📊 [StampsView] Counts changed? \(countsChanged)")
                
                if countsChanged {
                    // Follow counts changed - always update cache with fresh Firebase data
                    print("📊 [StampsView] ✅ Profile follow counts CHANGED - updating cache")
                    print("📊 [StampsView] Old: followers=\(oldFollowerCount), following=\(oldFollowingCount)")
                    print("📊 [StampsView] New: followers=\(profile.followerCount), following=\(profile.followingCount)")
                    followManager.updateFollowCounts(userId: userId, followerCount: profile.followerCount, followingCount: profile.followingCount)
                    print("📊 [StampsView] Cache update complete")
                } else if followManager.followCounts[userId] == nil {
                    // No change in counts, but cache is empty - initialize it
                    print("📊 [StampsView] ✅ No count change, but cache empty - initializing")
                    followManager.updateFollowCounts(userId: userId, followerCount: profile.followerCount, followingCount: profile.followingCount)
                } else {
                    print("📊 [StampsView] ⏭️  No count change and cache exists - skipping update")
                }
            } else {
                print("📊 [StampsView] ⚠️  Missing profile or userId - skipping")
            }
            print("📊 [StampsView] ========================================")
        }
        // MARK: - Profile Edit Sheet
        // Shows ProfileEditView when user taps pencil icon
        // On save, updates the local profile state and syncs to Firebase
        .sheet(isPresented: $showEditProfile) {
            if let profile = profileManager.currentUserProfile {
                ProfileEditView(profile: profile) { updatedProfile in
                    // Update local profile state when save succeeds
                    profileManager.updateProfile(updatedProfile)
                }
                .environmentObject(authManager)
            }
        }
        // MARK: - Profile Refresh on Stamp Collection
        // Refresh profile stats when user collects stamps
        .onChange(of: stampsManager.userCollection.collectedStamps.count) { oldCount, newCount in
            // Only refresh if count increased (stamp collected)
            if newCount > oldCount && authManager.isSignedIn {
                // Add slight delay to ensure Firebase stats are updated
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    profileManager.refreshProfile()
                }
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
        .sheet(isPresented: $showAccountDeletion) {
            AccountDeletionRequestView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showDataDownload) {
            DataDownloadRequestView()
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
        .sheet(item: $welcomeStamp) { stamp in
            // Sheet opens when welcomeStamp is set, closes when set to nil
            NavigationStack {
                StampDetailView(
                    stamp: stamp,
                    userLocation: nil,
                    showBackButton: false
                )
                .environmentObject(stampsManager)
                .environmentObject(authManager)
                .environmentObject(MapCoordinator())
                .toolbar(.visible, for: .tabBar)
            }
        }
        .sheet(isPresented: $showInviteCodeSheet) {
            InviteCodeSheet(isAuthenticated: $authManager.isSignedIn)
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
        .alert("App Store Link Copied", isPresented: $showAppStoreUrlCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The App Store link has been copied to your clipboard.")
        }
        .onChange(of: shouldResetNavigation) { _, newValue in
            // Reset navigation stack when flag is set
            if newValue {
                navigationPath = NavigationPath()
                shouldResetNavigation = false
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
    
    struct AllStampsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        @State private var displayedCount = 20 // Initial load
        @State private var userStamps: [Stamp] = [] // Lazy-loaded user stamps
        @State private var hasLoadedOnce = false // Prevent multiple initial loads
        
        private let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        
        // Get collected stamps sorted by date (latest first)
        private var sortedCollectedStamps: [(stamp: Stamp, collectedDate: Date)] {
            let collectedStamps = stampsManager.userCollection.collectedStamps
                .sorted { $0.collectedDate > $1.collectedDate } // Latest first
            
            return collectedStamps.compactMap { collected in
                if let stamp = userStamps.first(where: { $0.id == collected.stampId }) {
                    return (stamp, collected.collectedDate)
                }
                return nil
            }
        }
        
        // Get stamps to display (paginated)
        private var displayedStamps: [(stamp: Stamp, collectedDate: Date)] {
            Array(sortedCollectedStamps.prefix(displayedCount))
        }
        
        var body: some View {
            Group {
                if stampsManager.isLoadingUserStamps && !hasLoadedOnce {
                    // Skeleton loading state - show only on first load
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(0..<8, id: \.self) { _ in
                            SkeletonStampGridItem()
                                .redacted(reason: .placeholder)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                } else if sortedCollectedStamps.isEmpty && !stampsManager.isLoadingUserStamps {
                    // Empty state - only show if not loading and truly empty
                    VStack {
                        Spacer()
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding(.bottom, 20)
                        
                        Text("Your Stamps")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Your stamp collection will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                    .frame(height: 300)
                } else {
                    // Grid view
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(Array(displayedStamps.enumerated()), id: \.element.stamp.id) { index, item in
                            NavigationLink(destination:
                                            StampDetailView(
                                                stamp: item.stamp,
                                                userLocation: nil,
                                                showBackButton: true
                                            )
                                                .environmentObject(stampsManager)
                            ) {
                                StampGridItem(stamp: item.stamp)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onAppear {
                                // Load more when approaching the end
                                if index == displayedStamps.count - 1 && displayedCount < sortedCollectedStamps.count {
                                    loadMoreStamps()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .task {
                // .task is more stable than .onAppear - only runs once per view appearance
                guard !hasLoadedOnce else { return }
                loadUserStamps()
            }
            .onChange(of: stampsManager.userCollection.collectedStamps.count) { oldValue, newValue in
                // Reload when user collects new stamps
                if newValue != oldValue {
                    loadUserStamps()
                }
            }
        }
        
        private func loadUserStamps() {
            // Prevent re-entry if already loading
            guard !stampsManager.isLoadingUserStamps else { 
                print("⏭️ [AllStampsContent] Already loading, skipping loadUserStamps()")
                return 
            }
            
            print("🔄 [AllStampsContent] loadUserStamps() called")
            print("📊 [AllStampsContent] Current collectedStamps count: \(stampsManager.userCollection.collectedStamps.count)")
            
            Task {
                // Set loading state at view level
                await MainActor.run {
                    stampsManager.isLoadingUserStamps = true
                }
                
                // LAZY LOADING: Fetch ONLY stamps the user has collected
                let collectedStampIds = stampsManager.userCollection.collectedStamps.map { $0.stampId }
                print("🎯 [AllStampsContent] Fetching \(collectedStampIds.count) user stamps")
                print("🎯 [AllStampsContent] Stamp IDs: \(collectedStampIds)")
                
                // Include removed stamps - users keep what they collected
                // Note: fetchStamps will also set/clear isLoadingUserStamps, but we control it here
                let stamps = await stampsManager.fetchStamps(ids: collectedStampIds, includeRemoved: true)
                
                print("✅ [AllStampsContent] Fetched \(stamps.count) stamps")
                
                await MainActor.run {
                    userStamps = stamps
                    hasLoadedOnce = true // Mark as loaded to prevent re-entry
                    stampsManager.isLoadingUserStamps = false // Clear AFTER data is set
                    
                    print("📊 [AllStampsContent] userStamps count after update: \(userStamps.count)")
                    print("📊 [AllStampsContent] sortedCollectedStamps count: \(sortedCollectedStamps.count)")
                }
            }
        }
        
        private func loadMoreStamps() {
            // Load 20 more stamps
            let newCount = min(displayedCount + 20, sortedCollectedStamps.count)
            displayedCount = newCount
        }
    }
    
    struct StampGridItem: View {
        let stamp: Stamp
        
        var body: some View {
            VStack(spacing: 12) {
                // Stamp image - use CachedImageView for proper caching and instant display
                if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                    // Load from Firebase Storage with caching
                    CachedImageView.stampPhoto(
                        imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                        storagePath: stamp.imageStoragePath,
                        stampId: stamp.id,
                        size: CGSize(width: 148, height: 148),
                        cornerRadius: 12,
                        imageUrl: imageUrl
                    )
                    .frame(height: 148)
                } else if !stamp.imageName.isEmpty {
                    // Fallback to bundled image for backward compatibility
                    Image(stamp.imageName)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 148)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // No image - show placeholder
                    Image("empty")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 148)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Stamp name (centered, fixed height for 2 lines)
                Text(stamp.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
            }
        }
    }
    
    struct CollectionsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        @EnvironmentObject var authManager: AuthManager
        @State private var collectionMetadata: [String: (total: Int, collected: Int)] = [:]
        @State private var isLoadingMetadata = false
        @State private var hasLoadedOnce = false
        
        var body: some View {
            VStack(spacing: 20) {
                if stampsManager.isLoadingCollections {
                    // Skeleton loading state - show while collections are loading from Firebase
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonCollectionCard()
                            .redacted(reason: .placeholder)
                    }
                } else if isLoadingMetadata && !hasLoadedOnce && !stampsManager.collections.isEmpty {
                    // Skeleton loading state - show only on FIRST metadata load (after collections loaded)
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonCollectionCard()
                            .redacted(reason: .placeholder)
                    }
                } else if stampsManager.collections.isEmpty {
                    // Empty state - only show if not loading and collections are truly empty
                    VStack {
                        Spacer()
                        
                        Image(systemName: "folder.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding(.bottom, 20)
                        
                        Text("Collections")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Collections will appear here")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                    .frame(height: 300)
                } else {
                    ForEach(sortedCollections()) { collection in
                        NavigationLink(destination: CollectionDetailView(collection: collection)) {
                            let metadata = collectionMetadata[collection.id] ?? (total: 0, collected: 0)
                            let percentage = metadata.total > 0 ? Double(metadata.collected) / Double(metadata.total) : 0.0
                            
                            CollectionCardView(
                                emoji: collection.emoji,
                                name: collection.name,
                                collectedCount: metadata.collected,
                                totalCount: metadata.total,
                                completionPercentage: percentage
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .task {
                // Load metadata using already-synced data (no need to refresh from Firestore every time)
                loadCollectionMetadata()
            }
            .onChange(of: stampsManager.userCollection.collectedStamps.count) { oldValue, newValue in
                // Reload metadata when user collects new stamps
                if newValue != oldValue {
                    loadCollectionMetadata()
                }
            }
        }
        
        private func loadCollectionMetadata() {
            // Prevent multiple simultaneous loads
            guard !isLoadingMetadata else {
                print("⚠️ [CollectionsContent] Already loading metadata, skipping")
                return
            }
            
            print("🔄 [CollectionsContent] Starting metadata load")
            isLoadingMetadata = true
            
            Task {
                let startTime = Date()
                
                // OPTIMIZED: Instead of fetching ALL stamps in each collection,
                // only fetch the stamps that the user has collected, then count by collection
                let collectedStampIds = stampsManager.userCollection.collectedStamps.map { $0.stampId }
                
                print("📚 [CollectionsContent] Processing \(stampsManager.collections.count) collections")
                print("🎯 [CollectionsContent] User has \(collectedStampIds.count) collected stamps")
                
                // Fetch only the user's collected stamps (much faster than fetching all stamps in all collections!)
                let collectedStamps = await stampsManager.fetchStamps(ids: collectedStampIds)
                let fetchTime = Date().timeIntervalSince(startTime)
                print("⏱️ [CollectionsContent] Fetched \(collectedStamps.count) stamps in \(String(format: "%.2f", fetchTime))s")
                
                // Count how many collected stamps belong to each collection
                var metadata: [String: (total: Int, collected: Int)] = [:]
                
                for collection in stampsManager.collections {
                    // Use the hard-coded totalStamps from the collection
                    let total = collection.totalStamps
                    
                    // Count how many of the user's collected stamps belong to this collection
                    let collected = collectedStamps.filter { stamp in
                        stamp.collectionIds.contains(collection.id)
                    }.count
                    
                    metadata[collection.id] = (total: total, collected: collected)
                    print("✅ [CollectionsContent] \(collection.name): \(collected)/\(total)")
                }
                
                let totalTime = Date().timeIntervalSince(startTime)
                print("✅ [CollectionsContent] Metadata load complete in \(String(format: "%.2f", totalTime))s")
                
                await MainActor.run {
                    collectionMetadata = metadata
                    isLoadingMetadata = false
                    hasLoadedOnce = true
                }
            }
        }
        
        private struct TimeoutError: Error {}
        
        private func sortedCollections() -> [Collection] {
            stampsManager.collections.sorted { collection1, collection2 in
                let metadata1 = collectionMetadata[collection1.id] ?? (total: 0, collected: 0)
                let metadata2 = collectionMetadata[collection2.id] ?? (total: 0, collected: 0)
                
                let completion1 = metadata1.total > 0 ? Double(metadata1.collected) / Double(metadata1.total) : 0.0
                let completion2 = metadata2.total > 0 ? Double(metadata2.collected) / Double(metadata2.total) : 0.0
                
                if completion1 != completion2 {
                    return completion1 > completion2  // Higher completion first
                } else {
                    return collection1.name < collection2.name  // Alphabetical tiebreaker
                }
            }
        }
    }
    
    // MARK: - Skeleton Loading Views
    struct SkeletonStampGridItem: View {
        var body: some View {
            VStack(spacing: 12) {
                // Stamp image placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 160)
                
                // Stamp name placeholder (2 lines)
                VStack(spacing: 4) {
                    Text("Placeholder Stamp Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Second Line")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
            }
        }
    }
    
    struct SkeletonCollectionCard: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collection Name Here")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                HStack {
                    Text("0 / 0")
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text("0%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
            }
            .padding(16)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
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
