import Foundation
import FirebaseFunctions

/// Service for content moderation via Firebase Cloud Functions
/// Validates usernames, display names, and comments against profanity/reserved words
class ContentModerationService {
    static let shared = ContentModerationService()
    
    private let functions = Functions.functions()
    
    private init() {}
    
    /// Validation error types
    enum ValidationError: LocalizedError {
        case inappropriateContent
        case reservedWords
        case invalidFormat
        case tooShort
        case tooLong
        case alreadyTaken
        case networkError(String)
        case unknown(String)
        
        var errorDescription: String? {
            switch self {
            case .inappropriateContent:
                return "Contains inappropriate content"
            case .reservedWords:
                return "Contains reserved words"
            case .invalidFormat:
                return "Invalid format"
            case .tooShort:
                return "Too short"
            case .tooLong:
                return "Too long"
            case .alreadyTaken:
                return "Already taken"
            case .networkError(let message):
                return message
            case .unknown(let message):
                return message
            }
        }
    }
    
    struct ValidationResult {
        let isValid: Bool
        let usernameError: String?
        let displayNameError: String?
    }
    
    struct AvailabilityResult {
        let isAvailable: Bool
        let reason: String?
    }
    
    /// Validate username and display name via Cloud Function
    /// - Parameters:
    ///   - username: Username to validate (optional)
    ///   - displayName: Display name to validate (optional)
    /// - Returns: ValidationResult with any errors found
    func validateContent(username: String? = nil, displayName: String? = nil) async throws -> ValidationResult {
        var data: [String: Any] = [:]
        
        if let username = username {
            data["username"] = username
        }
        if let displayName = displayName {
            data["displayName"] = displayName
        }
        
        do {
            let result = try await functions.httpsCallable("validateContent").call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let isValid = resultData["valid"] as? Bool else {
                throw ValidationError.unknown("Invalid response from server")
            }
            
            let errors = resultData["errors"] as? [String: String]
            
            return ValidationResult(
                isValid: isValid,
                usernameError: errors?["username"],
                displayNameError: errors?["displayName"]
            )
        } catch let error as NSError {
            if error.domain == "FIRFunctionsErrorDomain" {
                // Firebase Functions error
                throw ValidationError.networkError("Unable to validate. Please check your connection.")
            }
            throw ValidationError.unknown(error.localizedDescription)
        }
    }
    
    /// Check if username is available (combines validation + uniqueness check)
    /// - Parameters:
    ///   - username: Username to check
    ///   - excludeUserId: User ID to exclude from check (for current user updating their username)
    /// - Returns: AvailabilityResult with availability status and reason if unavailable
    func checkUsernameAvailability(username: String, excludeUserId: String? = nil) async throws -> AvailabilityResult {
        var data: [String: Any] = ["username": username]
        
        if let excludeUserId = excludeUserId {
            data["excludeUserId"] = excludeUserId
        }
        
        do {
            let result = try await functions.httpsCallable("checkUsernameAvailability").call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let isAvailable = resultData["available"] as? Bool else {
                throw ValidationError.unknown("Invalid response from server")
            }
            
            let reason = resultData["reason"] as? String
            
            return AvailabilityResult(
                isAvailable: isAvailable,
                reason: reason
            )
        } catch let error as NSError {
            if error.domain == "FIRFunctionsErrorDomain" {
                throw ValidationError.networkError("Unable to check availability. Please check your connection.")
            }
            throw ValidationError.unknown(error.localizedDescription)
        }
    }
    
    /// Moderate comment text before posting
    /// - Parameter text: Comment text to validate
    /// - Returns: true if clean, throws error if inappropriate
    func moderateComment(text: String) async throws -> Bool {
        let data: [String: Any] = ["text": text]
        
        do {
            let result = try await functions.httpsCallable("moderateComment").call(data)
            
            guard let resultData = result.data as? [String: Any],
                  let isClean = resultData["clean"] as? Bool else {
                throw ValidationError.unknown("Invalid response from server")
            }
            
            if !isClean {
                if let _ = resultData["error"] as? String {
                    throw ValidationError.inappropriateContent
                }
                throw ValidationError.inappropriateContent
            }
            
            return true
        } catch let error as NSError {
            if error.domain == "FIRFunctionsErrorDomain" {
                throw ValidationError.networkError("Unable to validate comment. Please check your connection.")
            }
            throw error
        }
    }
}

