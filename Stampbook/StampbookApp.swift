import SwiftUI
import FirebaseCore

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("⏱️ [AppDelegate] didFinishLaunching started")
        
        // Configure Firebase
        FirebaseApp.configure()
        
        print("⏱️ [AppDelegate] Firebase configured")
        return true
    }
}

// MARK: - Main App
@main
struct StampbookApp: App {
    // Register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // Track startup time for watchdog debugging
    init() {
        print("⏱️ [StampbookApp] App init() started")
        print("⏱️ [StampbookApp] About to create @StateObject managers...")
    }
    
    @StateObject private var authManager: AuthManager = {
        print("⏱️ [StampbookApp] Creating AuthManager...")
        let manager = AuthManager()
        print("✅ [StampbookApp] AuthManager created")
        return manager
    }()
    
    @StateObject private var networkMonitor: NetworkMonitor = {
        print("⏱️ [StampbookApp] Creating NetworkMonitor...")
        let monitor = NetworkMonitor()
        print("✅ [StampbookApp] NetworkMonitor created")
        return monitor
    }()
    
    @StateObject private var followManager: FollowManager = {
        print("⏱️ [StampbookApp] Creating FollowManager...")
        let manager = FollowManager()
        print("✅ [StampbookApp] FollowManager created")
        return manager
    }()
    
    @StateObject private var profileManager: ProfileManager = {
        print("⏱️ [StampbookApp] Creating ProfileManager...")
        let manager = ProfileManager()
        print("✅ [StampbookApp] ProfileManager created")
        return manager
    }()
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(networkMonitor)
                .environmentObject(followManager)
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
        // Currently no specific actions needed on auth state change
        if isSignedIn {
            print("✅ [AppLifecycle] User signed in")
        } else {
            print("✅ [AppLifecycle] User signed out")
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

