import SwiftUI
import AuthenticationServices

struct StampsView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var profileManager = ProfileManager()
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: StampTab = .all
    @State private var showProfileMenu = false
    @State private var showEditProfile = false
    
    enum StampTab: String, CaseIterable {
        case all = "All"
        case collections = "Collections"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar
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
                    } else {
                        // Signed-out: Show app logo
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    if authManager.isSignedIn {
                        // Signed-in menu
                        HStack(spacing: 16) {
                            // Edit Profile Button - Opens ProfileEditView sheet
                            Button(action: {
                                showEditProfile = true
                            }) {
                                Image(systemName: "pencil.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                            }
                            .disabled(profileManager.currentUserProfile == nil)
                            
                            // More Options Menu (debug/dev tools)
                            Button(action: {
                                showProfileMenu = true
                            }) {
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
                                // TODO: Open privacy policy
                                print("Privacy Policy tapped")
                            }) {
                                Label("Privacy Policy", systemImage: "hand.raised")
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
                                    
                                    Text("Sign in to start your stamp collection and create your own stampbook")
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
                        }
                        
                        // Profile section (only when signed in)
                        if authManager.isSignedIn {
                        HStack(spacing: 12) {
                            // Profile picture
                            if let avatarUrl = profileManager.currentUserProfile?.avatarUrl,
                               let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .overlay(
                                            ProgressView()
                                        )
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.gray)
                                    )
                            }
                            
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Loading User Name")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                        
                                        Text("Loading bio text here that spans multiple lines")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
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
                        
                        // Stats cards - horizontal scrollable
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                // Rank card
                                HStack(spacing: 12) {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Rank")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if let rank = profileManager.userRank {
                                            Text("#\(rank)")
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.5)
                                        } else {
                                            Text("...")
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(width: 160)
                                .frame(height: 70)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                                .onAppear {
                                    // Lazy load rank when card appears
                                    if profileManager.userRank == nil,
                                       let profile = profileManager.currentUserProfile {
                                        Task {
                                            await profileManager.fetchUserRank(for: profile)
                                        }
                                    }
                                }
                                
                                // Countries card
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
                                
                                // Followers card
                                NavigationLink(destination: FollowListView(
                                    userId: authManager.userId ?? "",
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
                                            Text("\(profileManager.currentUserProfile?.followerCount ?? 0)")
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
                                
                                // Following card
                                NavigationLink(destination: FollowListView(
                                    userId: authManager.userId ?? "",
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
                                            Text("\(profileManager.currentUserProfile?.followingCount ?? 0)")
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
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 20)
                        }
                        
                        // Native segmented control (only when signed in)
                        if authManager.isSignedIn {
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
                }
                .refreshable {
                    // Refresh in parallel for better performance
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            await profileManager.refresh()
                        }
                        group.addTask {
                            await stampsManager.refresh()
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
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
                // MARK: - Profile Loading
                // Load profile when user signs in or app opens
                .onChange(of: authManager.isSignedIn) { oldValue, newValue in
                    if newValue, let userId = authManager.userId {
                        // Load profile when user signs in
                        profileManager.loadProfile(userId: userId)
                    } else {
                        // Clear profile when user signs out
                        profileManager.clearProfile()
                    }
                }
                .onAppear {
                    // Load profile if already signed in on app launch
                    if authManager.isSignedIn, let userId = authManager.userId {
                        profileManager.loadProfile(userId: userId)
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
                .alert("Developer Options", isPresented: $showProfileMenu) {
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                    }
                    
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }
    
    struct AllStampsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        @State private var displayedCount = 20 // Initial load
        @State private var showSkeleton = true
        
        private let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        
        // Get collected stamps sorted by date (latest first)
        private var sortedCollectedStamps: [(stamp: Stamp, collectedDate: Date)] {
            let collectedStamps = stampsManager.userCollection.collectedStamps
                .sorted { $0.collectedDate > $1.collectedDate } // Latest first
            
            return collectedStamps.compactMap { collected in
                if let stamp = stampsManager.stamps.first(where: { $0.id == collected.stampId }) {
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
                if showSkeleton && stampsManager.isLoading {
                    // Skeleton loading state - show only when actively loading
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(0..<8, id: \.self) { _ in
                            SkeletonStampGridItem()
                                .redacted(reason: .placeholder)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                } else if sortedCollectedStamps.isEmpty {
                    // Empty state
                    VStack {
                        Spacer()
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding(.bottom, 20)
                        
                        Text("All Stamps")
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
            .onChange(of: stampsManager.isLoading) { oldValue, newValue in
                if !newValue {
                    // Add minimum display time for smooth transition
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSkeleton = false
                        }
                    }
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
                // Stamp image
                Image(stamp.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
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
        @State private var showSkeleton = true
        
        var body: some View {
            VStack(spacing: 20) {
                if showSkeleton && stampsManager.isLoading {
                    // Skeleton loading state - show only when actively loading
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonCollectionCard()
                            .redacted(reason: .placeholder)
                    }
                } else if stampsManager.collections.isEmpty {
                    // Empty state
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
                    ForEach(stampsManager.sortedCollections) { collection in
                        NavigationLink(destination: CollectionDetailView(collection: collection)) {
                            let collectedCount = stampsManager.collectedStampsInCollection(collection.id)
                            let totalCount = stampsManager.stampsInCollection(collection.id).count
                            let percentage = totalCount > 0 ? Double(collectedCount) / Double(totalCount) : 0.0
                            
                            CollectionCardView(
                                name: collection.name,
                                collectedCount: collectedCount,
                                totalCount: totalCount,
                                completionPercentage: percentage
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .onChange(of: stampsManager.isLoading) { oldValue, newValue in
                if !newValue {
                    // Add minimum display time for smooth transition
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSkeleton = false
                        }
                    }
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
}
