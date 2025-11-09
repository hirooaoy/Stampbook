import Foundation

// MARK: - Stamp Errors

/// Errors related to stamp collection
enum StampError: LocalizedError {
    case tooFarAway(distance: Int, required: Int)
    case alreadyCollected
    case notFound
    case locationRequired
    case locationPermissionDenied
    case collectionFailed(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .tooFarAway(let distance, let required):
            return "You're \(distance)m away. Get within \(required)m to collect this stamp."
        case .alreadyCollected:
            return "You already collected this stamp!"
        case .notFound:
            return "Stamp not found. It may have been removed."
        case .locationRequired:
            return "Location access is required to collect stamps."
        case .locationPermissionDenied:
            return "Please enable location access in Settings to collect stamps."
        case .collectionFailed(let reason):
            return "Failed to collect stamp: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .tooFarAway:
            return "Move closer to the stamp location and try again."
        case .alreadyCollected:
            return "Check your collection to see this stamp."
        case .notFound:
            return "Pull down to refresh the map."
        case .locationRequired, .locationPermissionDenied:
            return "Open Settings → Privacy → Location Services → Stampbook → While Using the App"
        case .collectionFailed:
            return "Check your internet connection and try again."
        }
    }
}

// MARK: - Profile Errors

/// Errors related to user profiles
enum ProfileError: LocalizedError {
    case notFound
    case loadFailed
    case updateFailed(reason: String)
    case invalidUsername
    case usernameTaken
    case usernameInvalidCharacters
    case usernameTooShort
    case usernameTooLong
    case photoUploadFailed
    case photoTooLarge
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Profile not found."
        case .loadFailed:
            return "Failed to load profile. Check your connection."
        case .updateFailed(let reason):
            return "Failed to update profile: \(reason)"
        case .invalidUsername:
            return "Invalid username format."
        case .usernameTaken:
            return "This username is already taken."
        case .usernameInvalidCharacters:
            return "Username can only contain letters, numbers, and underscores."
        case .usernameTooShort:
            return "Username must be at least 3 characters."
        case .usernameTooLong:
            return "Username must be 20 characters or less."
        case .photoUploadFailed:
            return "Failed to upload photo. Try again."
        case .photoTooLarge:
            return "Photo is too large. Maximum size is 10MB."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .loadFailed, .updateFailed:
            return "Check your internet connection and try again."
        case .usernameTaken:
            return "Try a different username."
        case .invalidUsername, .usernameInvalidCharacters:
            return "Use only lowercase letters, numbers, and underscores."
        case .usernameTooShort:
            return "Add at least 3 characters."
        case .usernameTooLong:
            return "Shorten to 20 characters or less."
        case .photoUploadFailed:
            return "Check your connection and try uploading again."
        case .photoTooLarge:
            return "Compress or choose a smaller photo."
        default:
            return nil
        }
    }
}

// MARK: - Auth Errors

/// Errors related to authentication
enum AuthError: LocalizedError {
    case signInFailed
    case signInCancelled
    case invalidCredentials
    case networkError
    case accountNotFound
    case profileCreationFailed
    case signOutFailed
    
    var errorDescription: String? {
        switch self {
        case .signInFailed:
            return "Sign in failed. Please try again."
        case .signInCancelled:
            return "Sign in was cancelled."
        case .invalidCredentials:
            return "Invalid credentials. Please sign in again."
        case .networkError:
            return "Network error. Check your connection."
        case .accountNotFound:
            return "No account found. Please create an account first."
        case .profileCreationFailed:
            return "Failed to create profile. Please try again."
        case .signOutFailed:
            return "Failed to sign out. Please try again."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .signInFailed, .invalidCredentials:
            return "Try signing in again with Apple."
        case .networkError:
            return "Check your internet connection and try again."
        case .accountNotFound:
            return "Use an invite code to create a new account."
        case .profileCreationFailed:
            return "Contact support if this persists."
        default:
            return nil
        }
    }
}

// MARK: - Social Errors

/// Errors related to social features (following, liking, commenting)
enum SocialError: LocalizedError {
    case followFailed
    case unfollowFailed
    case alreadyFollowing
    case likeFailed
    case commentFailed
    case commentTooLong
    case invalidUser
    
    var errorDescription: String? {
        switch self {
        case .followFailed:
            return "Failed to follow user."
        case .unfollowFailed:
            return "Failed to unfollow user."
        case .alreadyFollowing:
            return "You're already following this user."
        case .likeFailed:
            return "Failed to like post."
        case .commentFailed:
            return "Failed to post comment."
        case .commentTooLong:
            return "Comment is too long. Maximum 500 characters."
        case .invalidUser:
            return "User not found."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .followFailed, .unfollowFailed, .likeFailed, .commentFailed:
            return "Check your connection and try again."
        case .commentTooLong:
            return "Shorten your comment to 500 characters."
        case .invalidUser:
            return "This user may have deleted their account."
        default:
            return nil
        }
    }
}

// MARK: - Network Errors

/// Errors related to network operations
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case serverError
    case rateLimited
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection."
        case .timeout:
            return "Request timed out."
        case .serverError:
            return "Server error. Please try again later."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .unauthorized:
            return "Not authorized. Please sign in again."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Check your internet connection."
        case .timeout:
            return "Try again. Check your connection if this persists."
        case .serverError:
            return "Our servers are having issues. Try again in a few minutes."
        case .rateLimited:
            return "Wait a few seconds and try again."
        case .unauthorized:
            return "Sign out and sign back in."
        }
    }
}

