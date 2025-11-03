import SwiftUI

// MARK: - Other User Profile View
// Only accessible from posts in feed (which require sign-in to view)
// No additional signed-out protection needed
struct UserProfileView: View {
    let userId: String // User ID to view
    let username: String
    let displayName: String
    
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var followManager: FollowManager // Shared instance
    @EnvironmentObject var currentUserProfileManager: ProfileManager // BEST PRACTICE: Global ProfileManager for current user counts
    @StateObject private var profileManager = ProfileManager() // Local ProfileManager for viewing this user's profile
    @Environment(\.dismiss) var dismiss
    
    @State private var showMoreMenu = false
    @State private var showUserReport = false // Show user report sheet
    @State private var userProfile: UserProfile?
    // @State private var userRank: Int? // TODO: POST-MVP - Rank for the viewed user
    @State private var showFollowError = false
    @State private var userCollectedStamps: [CollectedStamp] = [] // Stamps for the viewed user
    @State private var isLoadingStamps = false
    
    var isCurrentUser: Bool {
        authManager.userId == userId
    }
    
    var isFollowing: Bool {
        followManager.isFollowing[userId] ?? false
    }
    
    // MARK: - View Components
    
    private var profileSection: some View {
        HStack(spacing: 12) {
            // Profile picture with caching
            if isCurrentUser {
                // Current user - tapping should switch to Stamps tab
                Button(action: {
                    // Already on own profile view (shouldn't happen)
                }) {
                    ProfileImageView(
                        avatarUrl: userProfile?.avatarUrl,
                        userId: userId,
                        size: 64
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Other user - just show profile pic (already on their profile)
                ProfileImageView(
                    avatarUrl: userProfile?.avatarUrl,
                    userId: userId,
                    size: 64
                )
            }
            
            // Name and bio
            VStack(alignment: .leading, spacing: 4) {
                Text(userProfile?.displayName ?? displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(userProfile?.bio ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
    }
    
    private var statsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // rankCard // TODO: POST-MVP - Rank display disabled
                countriesCard
                followersCard
                followingCard
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }
    
    // TODO: POST-MVP - Rank Card Disabled
    // Rank calculation requires expensive Firestore queries comparing all users
    // Consider implementing with Cloud Functions for cached ranks
    /*
    private var rankCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Rank")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let rank = userRank {
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
            print("🎯 [UserProfileView] Rank card appeared for user \(userId) - userRank: \(userRank?.description ?? "nil")")
            if userRank == nil, let profile = userProfile {
                print("🔄 [UserProfileView] Triggering rank fetch for \(profile.displayName)...")
                Task {
                    await fetchUserRank(for: profile)
                }
            } else if let rank = userRank {
                print("✅ [UserProfileView] Rank already loaded: #\(rank)")
            } else {
                print("⚠️ [UserProfileView] Profile not loaded yet - cannot fetch rank")
            }
        }
    }
    */
    
    private var countriesCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 24))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Countries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(userProfile?.uniqueCountriesVisited ?? 0)")
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
    
    private var followersCard: some View {
        NavigationLink(destination: FollowListView(userId: userId, userDisplayName: userProfile?.displayName ?? displayName, initialTab: .followers)) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Followers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // Use cached count if available, fallback to profile
                    Text("\(followManager.followCounts[userId]?.followers ?? userProfile?.followerCount ?? 0)")
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
    
    private var followingCard: some View {
        NavigationLink(destination: FollowListView(userId: userId, userDisplayName: userProfile?.displayName ?? displayName, initialTab: .following)) {
            HStack(spacing: 12) {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Following")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    // Use cached count if available, fallback to profile
                    Text("\(followManager.followCounts[userId]?.following ?? userProfile?.followingCount ?? 0)")
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
    
    @ViewBuilder
    private var followButtonSection: some View {
        // Follow/Following button with triple dot menu (full width)
        // Don't show for current user
        if !isCurrentUser {
            HStack(spacing: 8) {
                Button(action: {
                    guard let currentUserId = authManager.userId else { return }
                    // BEST PRACTICE: Pass current user's ProfileManager to keep counts synced
                    followManager.toggleFollow(currentUserId: currentUserId, targetUserId: userId, profileManager: currentUserProfileManager) { updatedProfile in
                        // Update local profile state with returned profile
                        if let profile = updatedProfile {
                            userProfile = profile
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if followManager.isProcessingFollow[userId] == true {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text(isFollowing ? "Following" : "Follow")
                    }
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(isFollowing ? .primary : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(isFollowing ? Color(.systemGray5) : Color.blue)
                    .cornerRadius(10)
                }
                .disabled(followManager.isProcessingFollow[userId] == true)
                
                // Square button with triple dot
                Button(action: {
                    showMoreMenu = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    
    var body: some View {
        Group {
            // Profile content
            ScrollView {
                VStack(spacing: 0) {
                    profileSection
                    statsSection
                    followButtonSection
                    AllStampsContent(userCollectedStamps: userCollectedStamps, isLoadingStamps: isLoadingStamps)
                }
            }
            .refreshable {
                // Pull-to-refresh to get latest profile data
                await profileManager.refresh()
                // Also refresh stamps
                loadUserStamps()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showFollowError) {
            Button("OK", role: .cancel) {
                followManager.error = nil
            }
        } message: {
            Text(followManager.error ?? "Failed to update follow status. Please try again.")
        }
        .alert("More Options", isPresented: $showMoreMenu) {
            Button("Share Profile") {
                // Handle share action
                // TODO: Implement share functionality
            }
            
            Button("Report User", role: .destructive) {
                // Show user report view
                showUserReport = true
            }
            
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showUserReport) {
            SimpleUserReportView(reportedUserId: userId, reportedUsername: username)
        }
        .onAppear {
            // Load user profile
            profileManager.loadProfile(userId: userId)
            
            // Load user's collected stamps
            loadUserStamps()
            
            // Cache initial counts in FollowManager
            if let profile = userProfile {
                followManager.updateFollowCounts(userId: userId, followerCount: profile.followerCount, followingCount: profile.followingCount)
            }
            
            // Check follow status if not current user
            if !isCurrentUser, let currentUserId = authManager.userId {
                followManager.checkFollowStatus(currentUserId: currentUserId, targetUserId: userId)
            }
        }
        .onChange(of: profileManager.currentUserProfile) { oldProfile, profile in
            // Update local state when profile loads
            userProfile = profile
            if let profile = profile {
                followManager.updateFollowCounts(userId: userId, followerCount: profile.followerCount, followingCount: profile.followingCount)
                
                // TODO: POST-MVP - Rank fetch disabled
                // if userRank == nil {
                //     Task {
                //         await fetchUserRank(for: profile)
                //     }
                // }
            }
        }
        .onChange(of: followManager.error) { oldError, newError in
            // Show error alert when error occurs
            if newError != nil {
                showFollowError = true
            }
        }
    }
    
    /// Load collected stamps for the viewed user
    private func loadUserStamps() {
        isLoadingStamps = true
        Task {
            do {
                // Fetch stamps from Firebase for this specific user
                let stamps = try await FirebaseService.shared.fetchCollectedStamps(for: userId)
                await MainActor.run {
                    self.userCollectedStamps = stamps
                    self.isLoadingStamps = false
                }
                print("✅ Loaded \(stamps.count) stamps for user: \(userId)")
            } catch {
                await MainActor.run {
                    self.isLoadingStamps = false
                }
                print("❌ Failed to load user stamps: \(error.localizedDescription)")
            }
        }
    }
    
    // TODO: POST-MVP - User Rank Fetching Disabled
    // This function is disabled for MVP due to expensive Firestore queries
    // Comparing all users requires fetching large datasets and complex caching
    /*
    private func fetchUserRank(for profile: UserProfile) async {
        let startTime = Date()
        print("🔍 [UserProfileView] Fetching rank for \(profile.displayName) (userId: \(profile.id), totalStamps: \(profile.totalStamps))")
        
        do {
            let rank = try await FirebaseService.shared.calculateUserRankCached(
                userId: profile.id,
                totalStamps: profile.totalStamps
            )
            let elapsed = Date().timeIntervalSince(startTime)
            await MainActor.run {
                self.userRank = rank
            }
            print("✅ [UserProfileView] Fetched rank for \(profile.displayName): #\(rank) (took \(String(format: "%.3f", elapsed))s)")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("❌ [UserProfileView] Failed to fetch rank after \(String(format: "%.3f", elapsed))s: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ [UserProfileView] Error domain: \(nsError.domain), code: \(nsError.code)")
            }
        }
    }
    */
    
    struct AllStampsContent: View {
        let userCollectedStamps: [CollectedStamp]
        let isLoadingStamps: Bool
        
        @EnvironmentObject var stampsManager: StampsManager
        @State private var displayedCount = 20 // Initial load
        @State private var userStamps: [Stamp] = [] // Lazy-loaded stamps
        @State private var isLoadingLazyStamps = false
        
        private let columns = [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
        
        // Get collected stamps sorted by date (latest first)
        private var sortedCollectedStamps: [(stamp: Stamp, collectedDate: Date)] {
            let collectedStamps = userCollectedStamps
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
                if isLoadingLazyStamps && userStamps.isEmpty {
                    // Loading skeleton
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    }
                    .frame(height: 300)
                } else if sortedCollectedStamps.isEmpty && !isLoadingLazyStamps {
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
                        
                        Text("This user hasn't collected any stamps yet")
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
            .onAppear {
                loadUserStamps()
            }
            .onChange(of: userCollectedStamps.count) { oldCount, newCount in
                // Only reload if the count actually changed
                if oldCount != newCount {
                    loadUserStamps()
                }
            }
        }
        
        private func loadUserStamps() {
            guard !isLoadingLazyStamps else { return }
            
            isLoadingLazyStamps = true
            
            Task {
                // LAZY LOADING: Fetch ONLY stamps this user has collected
                let collectedStampIds = userCollectedStamps.map { $0.stampId }
                print("🎯 [UserProfileView] Fetching \(collectedStampIds.count) user stamps")
                
                let stamps = await stampsManager.fetchStamps(ids: collectedStampIds)
                
                await MainActor.run {
                    userStamps = stamps
                    isLoadingLazyStamps = false
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
                if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                    // Load from Firebase Storage
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure, .empty:
                            // Fallback to placeholder
                            Image("empty")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else if !stamp.imageName.isEmpty {
                    // Fallback to bundled image for backward compatibility
                    Image(stamp.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // No image - show placeholder
                    Image("empty")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 160)
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
}

#Preview {
    NavigationStack {
        UserProfileView(userId: "testUserId", username: "johndoe", displayName: "John Doe")
            .environmentObject(StampsManager())
            .environmentObject(AuthManager())
            .environmentObject(FollowManager())
    }
}

