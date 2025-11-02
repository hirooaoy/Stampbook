import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared profile manager
    @StateObject private var stampsManager = StampsManager()
    @State private var selectedTab = 0
    @State private var previousTab = 0 // Track previous tab
    @State private var shouldResetStampsNavigation = false // Flag to reset StampsView navigation
    
    var body: some View {
        // TODO: Add loading/error state UI overlay
        // - Show ProgressView when stampsManager.isLoading is true
        // - Show error message with retry button when stampsManager.loadError is not nil
        // - Blur/disable main content during loading/error states
        
        TabView(selection: $selectedTab) {
            FeedView(selectedTab: $selectedTab, shouldResetStampsNavigation: $shouldResetStampsNavigation)
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
            
            StampsView(shouldResetNavigation: $shouldResetStampsNavigation)
                .tabItem {
                    Label("Stamps", systemImage: "book.closed.fill")
                }
                .tag(2)
        }
        .environmentObject(stampsManager)
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
        }
        .onAppear {
            // Set current user on initial load
            stampsManager.setCurrentUser(authManager.userId)
            
            // Load profile if already signed in on app launch
            if authManager.isSignedIn, let userId = authManager.userId {
                print("🔄 [ContentView.onAppear] Loading profile for signed-in user: \(userId)")
                profileManager.loadProfile(userId: userId)
            }
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            print("🔄 [ContentView] Auth state changed - isSignedIn: \(isSignedIn)")
            
            if isSignedIn {
                // User signed in - load profile
                if let userId = authManager.userId {
                    print("🔄 [ContentView] User signed in, loading profile for userId: \(userId)")
                    profileManager.loadProfile(userId: userId)
                }
            } else {
                // User signed out - clear profile
                print("🔄 [ContentView] User signed out, clearing profile")
                profileManager.clearProfile()
            }
        }
        .onChange(of: authManager.userId) { _, newUserId in
            print("🔄 [ContentView] UserId changed: \(newUserId ?? "nil")")
            
            // Update stamps manager when user changes (sign in/out or switch user)
            stampsManager.setCurrentUser(newUserId)
            
            // Load or clear profile based on sign-in state
            if authManager.isSignedIn, let userId = newUserId {
                print("🔄 [ContentView] Loading profile for new userId: \(userId)")
                profileManager.loadProfile(userId: userId)
            } else {
                print("🔄 [ContentView] Clearing profile (signed out or nil userId)")
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

