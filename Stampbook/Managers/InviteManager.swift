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
        case codeGenerationFailed
        case codeNotFound
        
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
            case .codeGenerationFailed:
                return "Failed to generate invite code. Please try again."
            case .codeNotFound:
                return "Invite code not found."
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
                
                // Generate personal invite code for new user
                var personalCode = self.generateRandomCode()
                var codeAttempts = 0
                
                // Check for code collisions
                while codeAttempts < 10 {
                    let personalCodeRef = self.db.collection("invite_codes").document(personalCode)
                    let personalCodeDoc: DocumentSnapshot
                    do {
                        personalCodeDoc = try transaction.getDocument(personalCodeRef)
                    } catch {
                        errorPointer?.pointee = NSError(
                            domain: "InviteError",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to check personal code"]
                        )
                        return nil
                    }
                    
                    if !personalCodeDoc.exists {
                        break
                    }
                    
                    personalCode = self.generateRandomCode()
                    codeAttempts += 1
                }
                
                // Create user profile with personal code
                let createdBy = data["createdBy"] as? String ?? "admin"
                // Capitalize first letter of username for display name (e.g. "dylan" -> "Dylan")
                let displayName = username.prefix(1).uppercased() + username.dropFirst()
                transaction.setData([
                    "id": userId,  // Required field for UserProfile decoder
                    "username": username,
                    "displayName": displayName,  // Capitalized first letter of username
                    "inviteCodeUsed": codeString,
                    "invitedBy": createdBy,
                    "personalInviteCode": personalCode,  // Their personal code to share
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
                
                // Create personal invite code document
                let personalCodeRef = self.db.collection("invite_codes").document(personalCode)
                transaction.setData([
                    "code": personalCode,
                    "type": "personal",
                    "createdBy": userId,
                    "createdByUsername": username,
                    "maxUses": 5,
                    "usedCount": 0,
                    "usedBy": [],
                    "createdAt": FieldValue.serverTimestamp(),
                    "expiresAt": NSNull(),
                    "status": "active"
                ], forDocument: personalCodeRef)
                
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
    
    // MARK: - Personal Invite Codes
    
    /// Generate a random 8-character code (no confusing characters)
    private func generateRandomCode() -> String {
        let chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
    
    /// Check if user already has a personal code
    func getUserPersonalCode(userId: String) async -> String? {
        Logger.info("Checking if user \(userId) has personal code", category: "InviteManager")
        
        // Check user profile first (cached)
        let userRef = db.collection("users").document(userId)
        guard let userData = try? await userRef.getDocument().data(),
              let code = userData["personalInviteCode"] as? String else {
            return nil
        }
        
        Logger.success("User has existing code: \(code)", category: "InviteManager")
        return code
    }
    
    /// Generate personal invite code for user
    func generatePersonalCode(userId: String, username: String) async throws -> String {
        Logger.info("Generating personal code for \(username) (\(userId))", category: "InviteManager")
        
        // Check if user already has a code
        if let existingCode = await getUserPersonalCode(userId: userId) {
            Logger.warning("User already has code: \(existingCode)", category: "InviteManager")
            return existingCode
        }
        
        // Generate unique code (check for collisions)
        var code = generateRandomCode()
        var attempts = 0
        
        while attempts < 10 {
            let codeRef = db.collection("invite_codes").document(code)
            let codeDoc = try await codeRef.getDocument()
            
            if !codeDoc.exists {
                // Code is unique, use it
                break
            }
            
            // Collision detected, regenerate
            Logger.warning("Code collision detected: \(code), regenerating...", category: "InviteManager")
            code = generateRandomCode()
            attempts += 1
        }
        
        if attempts >= 10 {
            throw InviteError.codeGenerationFailed
        }
        
        Logger.info("Generated unique code: \(code)", category: "InviteManager")
        
        // Create the invite code document
        let codeRef = db.collection("invite_codes").document(code)
        try await codeRef.setData([
            "code": code,
            "type": "personal",
            "createdBy": userId,
            "createdByUsername": username,
            "maxUses": 5,
            "usedCount": 0,
            "usedBy": [],
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": NSNull(),
            "status": "active"
        ])
        
        Logger.info("Created invite code document", category: "InviteManager")
        
        // Update user profile with their code
        let userRef = db.collection("users").document(userId)
        try await userRef.updateData([
            "personalInviteCode": code
        ])
        
        Logger.success("Personal code \(code) generated and saved for \(username)", category: "InviteManager")
        return code
    }
    
    /// Get usage stats for a personal code
    func getCodeUsageStats(code: String) async throws -> (used: Int, max: Int, status: String) {
        Logger.info("Fetching usage stats for code: \(code)", category: "InviteManager")
        
        let codeRef = db.collection("invite_codes").document(code)
        let codeDoc = try await codeRef.getDocument()
        
        guard codeDoc.exists,
              let data = codeDoc.data(),
              let usedCount = data["usedCount"] as? Int,
              let maxUses = data["maxUses"] as? Int,
              let status = data["status"] as? String else {
            throw InviteError.codeNotFound
        }
        
        return (used: usedCount, max: maxUses, status: status)
    }
}

