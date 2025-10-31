import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared profile manager
    @StateObject private var stampsManager = StampsManager()
    @State private var selectedTab = 0
    
    var body: some View {
        // TODO: Add loading/error state UI overlay
        // - Show ProgressView when stampsManager.isLoading is true
        // - Show error message with retry button when stampsManager.loadError is not nil
        // - Blur/disable main content during loading/error states
        
        TabView(selection: $selectedTab) {
            FeedView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Feed", systemImage: "person.2.fill")
                }
                .tag(0)
            
            NavigationStack {
                MapView()
            }
            .tabItem {
                Label("Map", systemImage: "map.fill")
            }
            .tag(1)
            
            StampsView()
                .tabItem {
                    Label("Stamps", systemImage: "book.closed.fill")
                }
                .tag(2)
        }
        .environmentObject(stampsManager)
        .onAppear {
            // Set current user on initial load
            stampsManager.setCurrentUser(authManager.userId)
            
            // Load profile if already signed in on app launch
            if authManager.isSignedIn, let userId = authManager.userId {
                profileManager.loadProfile(userId: userId)
            }
        }
        .onChange(of: authManager.userId) { _, newUserId in
            // Update stamps manager when user changes (sign in/out or switch user)
            stampsManager.setCurrentUser(newUserId)
            
            // Load or clear profile based on sign-in state
            if authManager.isSignedIn, let userId = newUserId {
                profileManager.loadProfile(userId: userId)
            } else {
                profileManager.clearProfile()
            }
        }
        .onChange(of: profileManager.currentUserProfile) { _, newProfile in
            // Sync ProfileManager updates back to AuthManager for consistency
            if let profile = newProfile {
                authManager.userProfile = profile
                authManager.userDisplayName = profile.displayName
            }
        }
    }
}

#Preview {
    ContentView()
}

