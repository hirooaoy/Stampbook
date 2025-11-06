import SwiftUI

// MARK: - User Search View
// Simple people search for MVP - search by username to find users to follow
//
// POST-MVP ENHANCEMENTS:
// - Add segmented control: "All Users" | "Suggested"
// - Suggested users based on:
//   • Most followers (popular users)
//   • Most stamps collected (active users)
//   • Mutual followers (friends of friends)
//   • Similar stamps collected (shared interests)
//   • Location proximity (nearby collectors)
// - Phone contacts sync (match phone numbers to users)
// - QR code scanning to follow users in person
// - Search by display name in addition to username
// - Recent searches / search history
// - Featured/verified users section

struct UserSearchView: View {
    @EnvironmentObject var followManager: FollowManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // BEST PRACTICE: Pass to keep counts synced
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @FocusState private var isSearchFieldFocused: Bool
    
    private let firebaseService = FirebaseService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search usernames", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isSearchFieldFocused)
                        .onChange(of: searchText) { oldValue, newValue in
                            // Trigger search after user stops typing (debounced)
                            performSearch()
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                            hasSearched = false
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
                .padding(.top, 16)
                .padding(.bottom, 16)
                
                // Results
                if isSearching {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if !hasSearched && searchText.isEmpty {
                    // Initial state - show prompt
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Find people to follow")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Search by username")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else if hasSearched && searchResults.isEmpty {
                    // Empty results
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No users found")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    // Show results
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(searchResults) { user in
                                NavigationLink(destination: UserProfileView(userId: user.id, username: user.username, displayName: user.displayName)) {
                                    UserSearchRow(user: user)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Search people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }
            .onAppear {
                // Automatically focus the search field when the view appears
                isSearchFieldFocused = true
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }
        
        // Simple debounce - only search if text hasn't changed in 0.3s
        let currentSearch = searchText
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            // Check if search text is still the same
            guard currentSearch == searchText else { return }
            
            await MainActor.run {
                isSearching = true
            }
            
            do {
                let results = try await firebaseService.searchUsers(query: searchText, currentUserId: authManager.userId, limit: 50)
                
                await MainActor.run {
                    self.searchResults = results
                    self.hasSearched = true
                    self.isSearching = false
                }
                
                // Batch check follow statuses for all search results
                if let currentUserId = authManager.userId {
                    let userIds = results.map { $0.id }
                    await followManager.checkFollowStatuses(currentUserId: currentUserId, targetUserIds: userIds)
                }
            } catch {
                print("❌ Search failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.searchResults = []
                    self.hasSearched = true
                    self.isSearching = false
                }
            }
        }
    }
}

struct UserSearchRow: View {
    let user: UserProfile
    @EnvironmentObject var followManager: FollowManager
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
        // Removed onAppear check - follow statuses are now batch loaded after search
    }
}

#Preview {
    NavigationStack {
        UserSearchView()
            .environmentObject(AuthManager())
            .environmentObject(FollowManager())
    }
}

