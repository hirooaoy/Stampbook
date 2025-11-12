import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager // Shared profile manager
    @StateObject private var stampsManager: StampsManager = {
        Logger.debug("Creating StampsManager...")
        let manager = StampsManager()
        Logger.debug("StampsManager created")
        return manager
    }()
    @StateObject private var mapCoordinator = MapCoordinator() // Coordinates map navigation
    @State private var selectedTab = 0
    @State private var previousTab = 0 // Track previous tab
    @State private var shouldResetStampsNavigation = false // Flag to reset StampsView navigation
    
    var body: some View {
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
            // Auth check complete - show main app (TabBar always visible)
        TabView(selection: $selectedTab) {
            FeedView(selectedTab: $selectedTab, shouldResetStampsNavigation: $shouldResetStampsNavigation)
                .tabItem {
                    Label("Feed", systemImage: "person.2.fill")
                }
                .tag(0)
            
            NavigationStack {
                MapView()
                    .environmentObject(mapCoordinator)
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
        .environmentObject(mapCoordinator)
        .onChange(of: selectedTab) { oldValue, newValue in
            previousTab = oldValue
        }
        .onChange(of: mapCoordinator.shouldSwitchToMapTab) { _, shouldSwitch in
            if shouldSwitch {
                Logger.debug("Switching to Map tab (tab 1)")
                selectedTab = 1 // Switch to Map tab
            }
        }
        .onAppear {
            Logger.debug("onAppear started")
            // Set current user on initial load
            stampsManager.setCurrentUser(authManager.userId, profileManager: profileManager)
            // Note: ProfileManager is linked to AuthManager in StampbookApp.body (WindowGroup.onAppear)
            Logger.debug("onAppear completed")
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            Logger.info("Auth state changed - isSignedIn: \(isSignedIn)", category: "ContentView")
            
            if !isSignedIn {
                // User signed out - clear profile
                Logger.info("User signed out, clearing profile", category: "ContentView")
                profileManager.clearProfile()
            }
            // Note: AuthManager handles profile loading on sign-in
        }
        .onChange(of: authManager.userId) { _, newUserId in
            Logger.info("UserId changed: \(newUserId ?? "nil")", category: "ContentView")
            
            // Update stamps manager when user changes (sign in/out or switch user)
            stampsManager.setCurrentUser(newUserId, profileManager: profileManager)
            
            // Clear profile if signed out
            if !authManager.isSignedIn {
                Logger.info("Clearing profile (signed out)", category: "ContentView")
                profileManager.clearProfile()
            }
                // Note: AuthManager handles profile loading via ProfileManager
        }
        }
    }
}
