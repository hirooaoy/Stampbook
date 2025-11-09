import Foundation

/// Centralized configuration for the Stampbook app
/// All magic numbers and configurable values should be defined here
enum AppConfig {
    
    // MARK: - MVP Scale
    
    /// Target number of users for MVP launch
    static let targetUserCount: Int = 100
    
    /// Target number of stamps for MVP launch
    static let targetStampCount: Int = 1000
    
    // MARK: - Stamp Collection
    
    /// Collection radius in meters (150m ≈ 1.5 blocks)
    /// Accounts for GPS accuracy in urban areas
    static let stampCollectionRadius: Double = 150.0
    
    // MARK: - Invite System
    
    /// Default number of invites each user gets (Phase 1: disabled, set to 0)
    /// Phase 2: Will be 5 invites per user
    static let defaultInvitesPerUser: Int = 0
    
    // MARK: - Username Generation
    
    /// Range for random number suffix when generating usernames
    /// Example: "john" + random(10000...99999) = "john54321"
    static let usernameRandomNumberRange: ClosedRange<Int> = 10000...99999
    
    // MARK: - Performance
    
    /// Number of items to fetch per page in feed
    static let feedPageSize: Int = 20
    
    /// Maximum number of profile images to keep in cache
    static let maxCachedProfileImages: Int = 100
    
    // MARK: - Firebase
    
    /// Firestore cache settings
    static let firestorePersistenceEnabled: Bool = true
    
    /// Network timeout for Firebase operations (seconds)
    static let firebaseTimeout: TimeInterval = 10.0
    
    // MARK: - Testing
    
    /// Test user IDs for development
    static let testUserIds: [String] = ["hiroo", "watagumostudio"]
    
    // MARK: - Debug
    
    /// Enable verbose logging (only in DEBUG builds)
    static var verboseLogging: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

