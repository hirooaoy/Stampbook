import SwiftUI

struct FollowListView: View {
    let userId: String // The user whose followers/following we're viewing
    let userDisplayName: String
    @EnvironmentObject var followManager: FollowManager // Shared instance
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab: FollowTab
    @State private var searchText = ""
    
    init(userId: String, userDisplayName: String, initialTab: FollowTab = .followers) {
        self.userId = userId
        self.userDisplayName = userDisplayName
        _selectedTab = State(initialValue: initialTab)
    }
    
    enum FollowTab: String, CaseIterable {
        case followers = "Followers"
        case following = "Following"
    }
    
    var filteredUsers: [UserProfile] {
        let users = selectedTab == .followers ? followManager.followers : followManager.following
        
        if searchText.isEmpty {
            return users
        } else {
            return users.filter { user in
                user.displayName.localizedCaseInsensitiveContains(searchText) ||
                user.username.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Native segmented control with counts
            Picker("View", selection: $selectedTab) {
                ForEach(FollowTab.allCases, id: \.self) { tab in
                    let count = tab == .followers ? followManager.followers.count : followManager.following.count
                    Text("\(count) \(tab.rawValue)")
                        .font(.system(size: 24, weight: .medium))
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
            .onChange(of: selectedTab) { oldTab, newTab in
                // Refresh data when switching tabs
                if newTab == .followers && followManager.followers.isEmpty {
                    followManager.fetchFollowers(userId: userId, currentUserId: authManager.userId)
                } else if newTab == .following && followManager.following.isEmpty {
                    followManager.fetchFollowing(userId: userId, currentUserId: authManager.userId)
                }
            }
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // List of users
            if followManager.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else if filteredUsers.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "No \(selectedTab.rawValue.lowercased()) yet" : "No results")
                    .foregroundColor(.secondary)
                    .font(.body)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredUsers) { user in
                            NavigationLink(destination: UserProfileView(userId: user.id, username: user.username, displayName: user.displayName)) {
                                UserRow(user: user)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle(userDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load both followers and following data to show accurate counts
            // Pass current user ID to batch check follow statuses
            followManager.fetchFollowers(userId: userId, currentUserId: authManager.userId)
            followManager.fetchFollowing(userId: userId, currentUserId: authManager.userId)
        }
    }
}

struct UserRow: View {
    let user: UserProfile
    @EnvironmentObject var followManager: FollowManager // Shared instance
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // BEST PRACTICE: Pass to keep counts synced
    
    var isCurrentUser: Bool {
        authManager.userId == user.id
    }
    
    var isFollowing: Bool {
        followManager.isFollowing[user.id] ?? false
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture with caching
            ProfileImageView(
                avatarUrl: user.avatarUrl,
                userId: user.id,
                size: 48
            )
            
            // Name and username
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("@\(user.username)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Follow button (don't show for current user)
            if !isCurrentUser {
                Button(action: {
                    guard let currentUserId = authManager.userId else { return }
                    // BEST PRACTICE: Pass ProfileManager to keep counts synced across views
                    followManager.toggleFollow(currentUserId: currentUserId, targetUserId: user.id, profileManager: profileManager)
                }) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(isFollowing ? .primary : .white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(isFollowing ? Color(.systemGray5) : Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        // Removed onAppear check - follow statuses are now batch loaded when fetching the list
    }
}

#Preview {
    NavigationStack {
        FollowListView(userId: "testUserId", userDisplayName: "Hiroo")
            .environmentObject(AuthManager())
            .environmentObject(FollowManager())
    }
}

