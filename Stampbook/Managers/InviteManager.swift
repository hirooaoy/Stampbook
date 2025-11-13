import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

/// Manages invite code validation and account creation with invite codes
/// Note: Auto-generated usernames are safe by design and skip validation
@MainActor
class InviteManager: ObservableObject {
    private let db = Firestore.firestore()
    @Published var isProcessing = false
    
    // MARK: - Invite Errors
    
    enum InviteError: LocalizedError {
        case invalidCode
        case codeExpired
        case codeFullyUsed
        case networkError
        case accountCreationFailed
        case accountAlreadyExists
        
        var errorDescription: String? {
            switch self {
            case .invalidCode:
                return "This invite code doesn't exist."
            case .codeExpired:
                return "This invite code has expired."
            case .codeFullyUsed:
                return "This invite code has been fully claimed."
            case .networkError:
                return "There was a connection issue. Please try again."
            case .accountCreationFailed:
                return "Something went wrong creating your account. Please try again."
            case .accountAlreadyExists:
                return "You already have an account. Please use 'Already have an account?' to sign in."
            }
        }
    }
    
    // MARK: - Code Validation
    
    /// Validates an invite code by checking if it exists and is active
    /// This is a preliminary check - final validation happens during account creation
    func validateCode(_ code: String) async throws -> Bool {
        let codeString = code.uppercased().trimmingCharacters(in: .whitespaces)
        
        guard !codeString.isEmpty else {
            throw InviteError.invalidCode
        }
        
        do {
            let codeDoc = try await db.collection("invite_codes").document(codeString).getDocument()
            
            guard codeDoc.exists, let data = codeDoc.data() else {
                throw InviteError.invalidCode
            }
            
            guard let status = data["status"] as? String else {
                throw InviteError.invalidCode
            }
            
            guard status == "active" else {
                throw InviteError.codeExpired
            }
            
            guard let usedCount = data["usedCount"] as? Int,
                  let maxUses = data["maxUses"] as? Int else {
                throw InviteError.invalidCode
            }
            
            guard usedCount < maxUses else {
                throw InviteError.codeFullyUsed
            }
            
            return true
            
        } catch let error as InviteError {
            throw error
        } catch {
            Logger.error("Error validating invite code", error: error, category: "InviteManager")
            throw InviteError.networkError
        }
    }
    
    // MARK: - Account Creation
    
    /// Creates user account with invite code
    /// This performs atomic transaction: create user profile + mark code as used
    /// 
    /// NOTE: Auto-generated usernames (user_abc12345) are NOT validated via Cloud Functions
    /// because they are safe by design (no profanity, not reserved, unique by Firebase UID).
    /// Validation only happens when users manually change their username in profile settings.
    func createAccountWithInviteCode(userId: String, username: String, code: String) async throws {
        print("✅ [InviteManager] Creating account with auto-generated username: \(username)")
        
        let codeString = code.uppercased().trimmingCharacters(in: .whitespaces)
        let codeRef = db.collection("invite_codes").document(codeString)
        let userRef = db.collection("users").document(userId)
        
        do {
            _ = try await db.runTransaction { transaction, errorPointer in
                // Read the code document
                let codeDoc: DocumentSnapshot
                do {
                    codeDoc = try transaction.getDocument(codeRef)
                } catch {
                    errorPointer?.pointee = NSError(
                        domain: "InviteError",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to read invite code"]
                    )
                    return nil
                }
                
                // Check if user already exists (SAFETY CHECK)
                let userDoc: DocumentSnapshot
                do {
                    userDoc = try transaction.getDocument(userRef)
                } catch {
                    errorPointer?.pointee = NSError(
                        domain: "InviteError",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to check user profile"]
                    )
                    return nil
                }
                
                // If user already exists, prevent overwriting their account
                if userDoc.exists {
                    errorPointer?.pointee = NSError(
                        domain: "InviteError",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Account already exists"]
                    )
                    return nil
                }
                
                // Validate the code again (race condition protection)
                guard codeDoc.exists,
                      let data = codeDoc.data(),
                      let status = data["status"] as? String,
                      let usedCount = data["usedCount"] as? Int,
                      let maxUses = data["maxUses"] as? Int,
                      var usedBy = data["usedBy"] as? [String] else {
                    errorPointer?.pointee = NSError(
                        domain: "InviteError",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid invite code"]
                    )
                    return nil
                }
                
                // Check if code is still valid
                guard status == "active", usedCount < maxUses else {
                    errorPointer?.pointee = NSError(
                        domain: "InviteError",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Code no longer valid"]
                    )
                    return nil
                }
                
                // Create user profile
                let createdBy = data["createdBy"] as? String ?? "admin"
                transaction.setData([
                    "id": userId,  // Required field for UserProfile decoder
                    "username": username,
                    "displayName": username,  // Default to username, user can change later
                    "inviteCodeUsed": codeString,
                    "invitedBy": createdBy,
                    "invitesRemaining": 0,  // Phase 2: set to 5 for user invites
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastActiveAt": FieldValue.serverTimestamp(),
                    "totalStamps": 0,
                    "uniqueCountriesVisited": 0,
                    "bio": "",
                    "avatarUrl": "",
                    "followerCount": 0,
                    "followingCount": 0,
                    "hasSeenOnboarding": false  // Show profile setup sheet to new users
                ], forDocument: userRef)
                
                // Update code usage
                usedBy.append(userId)
                let newUsedCount = usedCount + 1
                let newStatus = (newUsedCount >= maxUses) ? "used" : "active"
                
                transaction.updateData([
                    "usedCount": newUsedCount,
                    "usedBy": usedBy,
                    "status": newStatus
                ], forDocument: codeRef)
                
                return nil
            }
            
            Logger.success("Account created successfully with invite code: \(codeString)", category: "InviteManager")
            
        } catch {
            Logger.error("Transaction failed", error: error, category: "InviteManager")
            
            // Check for specific error codes
            if let nsError = error as NSError?, nsError.domain == "InviteError" {
                switch nsError.code {
                case 3:
                    // Code validation error (fully used)
                throw InviteError.codeFullyUsed
                case 5:
                    // Account already exists
                    throw InviteError.accountAlreadyExists
                default:
                    break
                }
            }
            
            throw InviteError.accountCreationFailed
        }
    }
    
    // MARK: - User Profile Check
    
    /// Checks if a user profile exists for the given userId
    /// Used to differentiate returning users from new signups
    func userProfileExists(userId: String) async -> Bool {
        do {
            let userDoc = try await db.collection("users").document(userId).getDocument()
            return userDoc.exists
        } catch {
            Logger.error("Error checking user profile", error: error, category: "InviteManager")
            return false
        }
    }
}

