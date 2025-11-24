import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
import UserNotifications

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
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logger.debug("didFinishLaunching started")
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure Crashlytics
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        
        // Configure Push Notifications
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                Logger.info("Push notification permission granted", category: "AppDelegate")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                Logger.info("Push notification permission denied", category: "AppDelegate")
            }
            
            if let error = error {
                Logger.error("Push notification permission error: \(error.localizedDescription)", category: "AppDelegate")
            }
        }
        
        Logger.info("Firebase & Crashlytics configured", category: "AppDelegate")
        return true
    }
    
    // MARK: - Remote Notification Registration
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Logger.info("Successfully registered for remote notifications", category: "AppDelegate")
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.error("Failed to register for remote notifications: \(error.localizedDescription)", category: "AppDelegate")
    }
    
    // MARK: - FCM Token Handling
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else { return }
        
        Logger.info("FCM token received: \(fcmToken.prefix(20))...", category: "AppDelegate")
        
        // Save token to UserDefaults for access by other parts of the app
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
        
        // Post notification so other parts of the app can handle token updates
        NotificationCenter.default.post(name: NSNotification.Name("FCMTokenUpdated"), object: nil, userInfo: ["token": fcmToken])
    }
    
    // MARK: - Notification Handling
    
    /// Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        Logger.info("Notification received in foreground: \(userInfo)", category: "AppDelegate")
        
        // Show banner and sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Logger.info("Notification tapped: \(userInfo)", category: "AppDelegate")
        
        // Extract notification data for deep linking
        if let postId = userInfo["postId"] as? String {
            // Post deep link notification for navigation
            NotificationCenter.default.post(name: NSNotification.Name("OpenPost"), object: nil, userInfo: ["postId": postId])
        } else if let userId = userInfo["userId"] as? String {
            // Profile deep link notification for navigation
            NotificationCenter.default.post(name: NSNotification.Name("OpenProfile"), object: nil, userInfo: ["userId": userId])
        }
        
        completionHandler()
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
    
    @StateObject private var likeManager: LikeManager = {
        Logger.debug("Creating LikeManager...")
        let manager = LikeManager()
        Logger.debug("LikeManager created")
        return manager
    }()
    
    @StateObject private var commentManager: CommentManager = {
        Logger.debug("Creating CommentManager...")
        let manager = CommentManager()
        Logger.debug("CommentManager created")
        return manager
    }()
    
    @StateObject private var notificationManager: NotificationManager = {
        Logger.debug("Creating NotificationManager...")
        let manager = NotificationManager()
        Logger.debug("NotificationManager created")
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
                .environmentObject(likeManager)
                .environmentObject(commentManager)
                .environmentObject(notificationManager)
                .onAppear {
                    // Link ProfileManager to AuthManager BEFORE starting auth check
                    // This prevents race condition where checkAuthState() completes before profileManager is linked
                    authManager.profileManager = profileManager
                    Logger.debug("Linked ProfileManager to AuthManager in WindowGroup")
                    
                    // Now safe to start auth check (profileManager is guaranteed to be linked)
                    authManager.startAuthCheck()
                    Logger.debug("Started auth check after profileManager linkage")
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
        if isSignedIn {
            Logger.debug("User signed in")
            // Start notification polling if app is active
            if scenePhase == .active, let userId = authManager.userId {
                notificationManager.startPollingForUnreadNotifications(userId: userId)
            }
        } else {
            Logger.debug("User signed out - clearing all caches")
            // Stop notification polling
            notificationManager.stopPollingForUnreadNotifications()
            
            // ✅ CRITICAL FIX: Clear all manager caches to prevent data leakage between users
            // Without this, User B would see User A's liked posts, comments, feed, and follow data
            likeManager.clearCache()
            commentManager.clearCache()
            followManager.clearFollowData()
            // Note: FeedManager is created in FeedView (@StateObject), cleared automatically when view destroyed
            Logger.success("All manager caches cleared on sign out", category: "StampbookApp")
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
                
                // Start notification polling if user is signed in
                // Polls every 5 minutes - 98% cheaper than real-time listeners
                if authManager.isSignedIn, let userId = authManager.userId {
                    notificationManager.startPollingForUnreadNotifications(userId: userId)
                }
            }
            
        case .inactive:
            // App became inactive (transitioning to/from background)
            Logger.debug("App became inactive")
            
        case .background:
            // App moved to background
            Logger.debug("App moved to background")
            // ImageCacheManager automatically clears full images via notification
            
            // Stop notification polling to save battery and Firestore reads
            notificationManager.stopPollingForUnreadNotifications()
            
        @unknown default:
            break
        }
    }
}

