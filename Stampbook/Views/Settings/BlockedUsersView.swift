import SwiftUI

/// View showing list of blocked users with ability to unblock
/// Accessed from Settings > Blocked Users
struct BlockedUsersView: View {
    @EnvironmentObject var blockManager: BlockManager
    @EnvironmentObject var authManager: AuthManager
    
    @State private var blockedProfiles: [UserProfile] = []
    @State private var isLoading = false
    @State private var showUnblockConfirmation = false
    @State private var userToUnblock: UserProfile?
    @State private var error: String?
    
    private let firebaseService = FirebaseService.shared
    
    var body: some View {
        Group {
            if isLoading && blockedProfiles.isEmpty {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading blocked users...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if blockedProfiles.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "hand.raised.slash.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No Blocked Users")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("When you block someone, they won't be able to find your profile or see your stamps and activity.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List of blocked users
                List {
                    Section {
                        ForEach(blockedProfiles) { profile in
                            BlockedUserRow(
                                profile: profile,
                                onUnblock: {
                                    userToUnblock = profile
                                    showUnblockConfirmation = true
                                }
                            )
                        }
                    } header: {
                        Text("\(blockedProfiles.count) blocked user\(blockedProfiles.count == 1 ? "" : "s")")
                    } footer: {
                        Text("Blocked users cannot see your profile, stamps, or activity. They are not notified when you block or unblock them.")
                            .font(.footnote)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadBlockedUsers()
        }
        .refreshable {
            loadBlockedUsers()
        }
        .alert("Unblock \(userToUnblock?.displayName ?? "User")?", isPresented: $showUnblockConfirmation) {
            Button("Unblock", role: .destructive) {
                if let profile = userToUnblock {
                    handleUnblock(profile: profile)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will be able to see your profile and stamps again. You can block them again at any time.")
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK", role: .cancel) {
                error = nil
            }
        } message: {
            Text(error ?? "An error occurred")
        }
    }
    
    private func loadBlockedUsers() {
        guard let userId = authManager.userId else { return }
        
        isLoading = true
        
        Task {
            do {
                // Fetch blocked user IDs
                let blockedIds = blockManager.blockedUserIds.isEmpty
                    ? try await firebaseService.fetchBlockedUserIds(userId: userId)
                    : Array(blockManager.blockedUserIds)
                
                // Fetch profiles for blocked users
                let profiles = try await firebaseService.fetchProfilesBatch(userIds: blockedIds)
                
                await MainActor.run {
                    self.blockedProfiles = profiles.sorted { $0.displayName < $1.displayName }
                    self.isLoading = false
                }
                print("✅ Loaded \(profiles.count) blocked user profiles")
            } catch {
                await MainActor.run {
                    self.error = "Failed to load blocked users: \(error.localizedDescription)"
                    self.isLoading = false
                }
                print("❌ Failed to load blocked users: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleUnblock(profile: UserProfile) {
        guard let currentUserId = authManager.userId else { return }
        
        blockManager.unblockUser(currentUserId: currentUserId, targetUserId: profile.id) {
            // On success, remove from local list
            blockedProfiles.removeAll { $0.id == profile.id }
            print("✅ Unblocked user: \(profile.displayName)")
        }
    }
}

struct BlockedUserRow: View {
    let profile: UserProfile
    let onUnblock: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            ProfileImageView(
                avatarUrl: profile.avatarUrl,
                userId: profile.id,
                size: 50
            )
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                
                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Unblock button
            Button(action: onUnblock) {
                Text("Unblock")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BlockedUsersView()
            .environmentObject(BlockManager())
            .environmentObject(AuthManager())
    }
}

