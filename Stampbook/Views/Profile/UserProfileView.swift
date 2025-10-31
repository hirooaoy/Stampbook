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
    @StateObject private var profileManager = ProfileManager()
    
    @State private var selectedTab: StampTab = .all
    @State private var showBlockMenu = false
    @State private var userProfile: UserProfile?
    @State private var userRank: Int? // Rank for the viewed user
    @State private var showFollowError = false
    
    var isCurrentUser: Bool {
        authManager.userId == userId
    }
    
    var isFollowing: Bool {
        followManager.isFollowing[userId] ?? false
    }
    
    enum StampTab: String, CaseIterable {
        case all = "All"
        case collections = "Collections"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile section
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
                            if userRank == nil, let profile = userProfile {
                                Task {
                                    await fetchUserRank(for: profile)
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
                        
                        // Followers card
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
                        
                        // Following card
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
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
                
                // Follow/Following button with triple dot menu (full width)
                // Don't show for current user
                if !isCurrentUser {
                    HStack(spacing: 8) {
                        Button(action: {
                            guard let currentUserId = authManager.userId else { return }
                            followManager.toggleFollow(currentUserId: currentUserId, targetUserId: userId) { updatedProfile in
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
                            showBlockMenu = true
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
            // Pull-to-refresh to get latest profile data (without rank for speed)
            await profileManager.refreshWithoutRank()
        }
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showFollowError) {
            Button("OK", role: .cancel) {
                followManager.error = nil
            }
        } message: {
            Text(followManager.error ?? "Failed to update follow status. Please try again.")
        }
        .alert("", isPresented: $showBlockMenu) {
            Button("Share Profile") {
                // Handle share action
                // TODO: Implement share functionality
            }
            
            Button("Report", role: .destructive) {
                // Handle report action
                // TODO: Implement report functionality
            }
            
            Button("Block", role: .destructive) {
                // Handle block action
                // TODO: Implement block functionality
            }
            
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // Load user profile
            profileManager.loadProfile(userId: userId)
            
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
                
                // Rank is loaded lazily when rank card appears (for better performance)
            }
        }
        .onChange(of: followManager.error) { oldError, newError in
            // Show error alert when error occurs
            if newError != nil {
                showFollowError = true
            }
        }
    }
    
    /// Fetch rank for the viewed user (with caching)
    private func fetchUserRank(for profile: UserProfile) async {
        do {
            let rank = try await FirebaseService.shared.calculateUserRankCached(
                userId: profile.id,
                totalStamps: profile.totalStamps
            )
            await MainActor.run {
                self.userRank = rank
            }
            print("✅ Fetched rank for \(profile.displayName): #\(rank)")
        } catch {
            print("⚠️ Failed to fetch rank: \(error.localizedDescription)")
        }
    }
    
    struct AllStampsContent: View {
        @EnvironmentObject var stampsManager: StampsManager
        @State private var displayedCount = 20 // Initial load
        
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
                if sortedCollectedStamps.isEmpty {
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
        
        var body: some View {
            VStack(spacing: 20) {
                ForEach(stampsManager.collections) { collection in
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
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
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

