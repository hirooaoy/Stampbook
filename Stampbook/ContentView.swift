import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared profile manager
    @StateObject private var stampsManager: StampsManager = {
        print("⏱️ [ContentView] Creating StampsManager...")
        let manager = StampsManager()
        print("✅ [ContentView] StampsManager created")
        return manager
    }()
    @State private var selectedTab = 0
    @State private var previousTab = 0 // Track previous tab
    @State private var shouldResetStampsNavigation = false // Flag to reset StampsView navigation
    
    var body: some View {
        let _ = print("⏱️ [ContentView] body evaluation started")
        
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
        } else {
            // Auth check complete - show main app
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
            print("⏱️ [ContentView] onAppear started")
            // Set current user on initial load
            stampsManager.setCurrentUser(authManager.userId)
            
            // Link AuthManager to ProfileManager
            authManager.profileManager = profileManager
            print("✅ [ContentView] onAppear completed")
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            print("🔄 [ContentView] Auth state changed - isSignedIn: \(isSignedIn)")
            
            if !isSignedIn {
                // User signed out - clear profile
                print("🔄 [ContentView] User signed out, clearing profile")
                profileManager.clearProfile()
            }
            // Note: AuthManager handles profile loading on sign-in
        }
        .onChange(of: authManager.userId) { _, newUserId in
            print("🔄 [ContentView] UserId changed: \(newUserId ?? "nil")")
            
            // Update stamps manager when user changes (sign in/out or switch user)
            stampsManager.setCurrentUser(newUserId)
            
            // Clear profile if signed out
            if !authManager.isSignedIn {
                print("🔄 [ContentView] Clearing profile (signed out)")
                profileManager.clearProfile()
            }
            // Note: AuthManager handles profile loading
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
}
