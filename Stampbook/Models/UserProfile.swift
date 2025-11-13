import Foundation
import FirebaseFirestore

/// User profile data stored in Firestore
struct UserProfile: Codable, Identifiable, Equatable, Sendable {
    let id: String // user ID from Firebase Auth
    let username: String // unique handle (e.g. "@johndoe"), changeable with restrictions
    var displayName: String
    var bio: String
    var avatarUrl: String?
    var totalStamps: Int
    var uniqueCountriesVisited: Int // Count of unique countries from collected stamps
    var followerCount: Int // Denormalized count (synced by Cloud Function updateFollowCounts)
    var followingCount: Int // Denormalized count (synced by Cloud Function updateFollowCounts)
    var createdAt: Date
    var lastActiveAt: Date
    var usernameLastChanged: Date? // Tracks when username was last changed - enforces 14-day cooldown between changes
    var hasSeenOnboarding: Bool // Tracks if user has seen the profile setup sheet (for first-time username customization)
    
    // TODO: Future enhancement for preventing username squatting
    // var previousUsername: String? // Stores previous username - reserved for 14 days to prevent squatting/impersonation
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case bio
        case avatarUrl
        case totalStamps
        case uniqueCountriesVisited
        case followerCount
        case followingCount
        case createdAt
        case lastActiveAt
        case usernameLastChanged
        case hasSeenOnboarding
    }
    
    init(id: String, username: String, displayName: String, bio: String = "", avatarUrl: String? = nil, totalStamps: Int = 0, uniqueCountriesVisited: Int = 0, followerCount: Int = 0, followingCount: Int = 0, createdAt: Date = Date(), lastActiveAt: Date = Date(), usernameLastChanged: Date? = nil, hasSeenOnboarding: Bool = false) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.totalStamps = totalStamps
        self.uniqueCountriesVisited = uniqueCountriesVisited
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.usernameLastChanged = usernameLastChanged
        self.hasSeenOnboarding = hasSeenOnboarding
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio) ?? ""
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        totalStamps = try container.decodeIfPresent(Int.self, forKey: .totalStamps) ?? 0
        uniqueCountriesVisited = try container.decodeIfPresent(Int.self, forKey: .uniqueCountriesVisited) ?? 0
        followerCount = try container.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        
        // Handle username migration: if username doesn't exist, generate one from displayName
        if let existingUsername = try? container.decode(String.self, forKey: .username) {
            username = existingUsername
        } else {
            // Legacy profile without username - generate from displayName + random number
            let firstName = displayName.components(separatedBy: " ").first ?? "user"
            let cleanFirstName = firstName.lowercased()
                .filter { $0.isLetter || $0.isNumber }
            let randomNumber = Int.random(in: AppConfig.usernameRandomNumberRange)
            username = cleanFirstName + "\(randomNumber)"
            print("⚠️ Migrated legacy profile: generated username @\(username)")
        }
        
        // Handle Timestamp conversion
        if let timestamp = try? container.decode(Timestamp.self, forKey: .createdAt) {
            createdAt = timestamp.dateValue()
        } else {
            createdAt = Date()
        }
        
        if let timestamp = try? container.decode(Timestamp.self, forKey: .lastActiveAt) {
            lastActiveAt = timestamp.dateValue()
        } else {
            lastActiveAt = Date()
        }
        
        // Handle usernameLastChanged (optional field for backward compatibility)
        if let timestamp = try? container.decode(Timestamp.self, forKey: .usernameLastChanged) {
            usernameLastChanged = timestamp.dateValue()
        } else {
            usernameLastChanged = nil
        }
        
        // Handle hasSeenOnboarding (optional field for backward compatibility)
        // For existing users without this field, treat as true (they already onboarded)
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? true
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(bio, forKey: .bio)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encode(totalStamps, forKey: .totalStamps)
        try container.encode(uniqueCountriesVisited, forKey: .uniqueCountriesVisited)
        try container.encode(followerCount, forKey: .followerCount)
        try container.encode(followingCount, forKey: .followingCount)
        try container.encode(Timestamp(date: createdAt), forKey: .createdAt)
        try container.encode(Timestamp(date: lastActiveAt), forKey: .lastActiveAt)
        if let usernameLastChanged = usernameLastChanged {
            try container.encode(Timestamp(date: usernameLastChanged), forKey: .usernameLastChanged)
        }
        try container.encode(hasSeenOnboarding, forKey: .hasSeenOnboarding)
    }
}

