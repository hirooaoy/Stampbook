import SwiftUI
import FirebaseCore

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure Firebase
        FirebaseApp.configure()
        return true
    }
}

// MARK: - Main App
@main
struct StampbookApp: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var authManager = AuthManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var followManager = FollowManager() // Shared instance across the app
    @StateObject private var blockManager = BlockManager() // Shared instance for blocking across the app
    @StateObject private var profileManager = ProfileManager() // Shared profile cache across the app
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(networkMonitor)
                .environmentObject(followManager)
                .environmentObject(blockManager)
                .environmentObject(profileManager)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
        .onChange(of: authManager.isSignedIn) { _, isSignedIn in
            handleAuthStateChange(isSignedIn: isSignedIn)
        }
    }
    
    // MARK: - Authentication Handling
    
    /// Handle authentication state changes
    private func handleAuthStateChange(isSignedIn: Bool) {
        if isSignedIn {
            // User signed in - load blocked users
            if let userId = authManager.userId {
                blockManager.loadBlockedUsers(currentUserId: userId)
                print("✅ [AppLifecycle] User signed in, loaded blocked users")
            }
        } else {
            // User signed out - clear blocked users
            blockManager.clearBlockData()
            print("✅ [AppLifecycle] User signed out, cleared block data")
        }
    }
    
    // MARK: - App Lifecycle Handling
    
    /// Handle app lifecycle transitions (background/foreground)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active (foreground)
            if oldPhase == .inactive || oldPhase == .background {
                print("🌅 [AppLifecycle] App became active")
                // Network monitor will automatically check connectivity
            }
            
        case .inactive:
            // App became inactive (transitioning to/from background)
            print("⏸️ [AppLifecycle] App became inactive")
            
        case .background:
            // App moved to background
            print("🌙 [AppLifecycle] App moved to background")
            // ImageCacheManager automatically clears full images via notification
            
        @unknown default:
            break
        }
    }
}

