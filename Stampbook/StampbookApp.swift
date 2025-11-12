import SwiftUI
import FirebaseCore
import FirebaseCrashlytics

// MARK: - Future Features
// TODO: iOS Widget - Rotating Stamp Widget
// Implement a home screen widget that rotates through collected stamps (like Google Photos widget)
// - Small widget: Shows one stamp image with name overlay
// - Medium/Large: Stamp image + location details
// - Rotates hourly to show different stamps from collection
// - Deep link to specific stamp on tap
// Implementation: ~2-3 hours
//   1. Add App Group for data sharing between app and widget
//   2. Create WidgetDataManager to share stamp collection via App Group UserDefaults
//   3. Add Widget Extension target (File → New → Target → Widget Extension)
//   4. Build widget UI with SwiftUI (AsyncImage + rotation logic)
//   5. Add deep linking support with .onOpenURL()

// MARK: - App Delegate
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logger.debug("didFinishLaunching started")
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure Crashlytics
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        Logger.info("Firebase & Crashlytics configured", category: "AppDelegate")
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
        Logger.debug("App init() started")
        Logger.debug("About to create @StateObject managers...")
    }
    
    @StateObject private var authManager: AuthManager = {
        Logger.debug("Creating AuthManager...")
        let manager = AuthManager()
        Logger.debug("AuthManager created")
        return manager
    }()
    
    @StateObject private var networkMonitor: NetworkMonitor = {
        Logger.debug("Creating NetworkMonitor...")
        let monitor = NetworkMonitor()
        Logger.debug("NetworkMonitor created")
        return monitor
    }()
    
    @StateObject private var followManager: FollowManager = {
        Logger.debug("Creating FollowManager...")
        let manager = FollowManager()
        Logger.debug("FollowManager created")
        return manager
    }()
    
    @StateObject private var profileManager: ProfileManager = {
        Logger.debug("Creating ProfileManager...")
        let manager = ProfileManager()
        Logger.debug("ProfileManager created")
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
                .onAppear {
                    // Link ProfileManager to AuthManager as soon as WindowGroup appears
                    // This happens after @StateObjects are initialized but before deferred auth check completes
                    authManager.profileManager = profileManager
                    Logger.debug("Linked ProfileManager to AuthManager in WindowGroup")
                }
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
            Logger.debug("User signed in")
        } else {
            Logger.debug("User signed out")
        }
    }
    
    // MARK: - App Lifecycle Handling
    
    /// Handle app lifecycle transitions (background/foreground)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active (foreground)
            if oldPhase == .inactive || oldPhase == .background {
                Logger.debug("App became active")
                // Network monitor will automatically check connectivity
            }
            
        case .inactive:
            // App became inactive (transitioning to/from background)
            Logger.debug("App became inactive")
            
        case .background:
            // App moved to background
            Logger.debug("App moved to background")
            // ImageCacheManager automatically clears full images via notification
            
        @unknown default:
            break
        }
    }
}

