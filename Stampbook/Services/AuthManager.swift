import Foundation
import Combine
import AuthenticationServices
import FirebaseAuth
import CryptoKit

class AuthManager: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var userId: String?
    @Published var isCheckingAuth = true  // Track if we're still checking auth state
    
    // For Apple Sign In with Firebase
    private var currentNonce: String?
    private var authController: ASAuthorizationController? // Keep controller alive during authorization
    private let firebaseService = FirebaseService.shared
    private let imageManager = ImageManager.shared
    
    // Reference to ProfileManager (set by ContentView after init)
    // ProfileManager is now the single source of truth for profile data
    weak var profileManager: ProfileManager?
    
    // For async/await Sign in with Apple (invite flow)
    private var signInContinuation: CheckedContinuation<AuthDataResult, Error>?
    
    // Store the user's name from Apple Sign In for username generation
    @Published var appleSignInGivenName: String?
    
    override init() {
        super.init()
        Logger.debug("AuthManager init() started")
        
        // Defer auth check to avoid blocking app launch
        // Use regular Task (not detached) to maintain proper MainActor context
        Task { [weak self] in
            await self?.checkAuthState()
        }
        
        Logger.debug("AuthManager init() completed (auth check deferred)")
    }
    
    /// Check if user is already signed in with Firebase
    private func checkAuthState() async {
        Logger.debug("checkAuthState() started")
        
        guard let currentUser = Auth.auth().currentUser else {
            Logger.info("No user signed in", category: "AuthManager")
            await MainActor.run {
                self.isCheckingAuth = false
            }
            return
        }
        
        // Check if user profile exists (orphaned auth state protection)
        let profileExists = await checkUserProfileExists(userId: currentUser.uid)
        
        // Only sign out if we KNOW the profile doesn't exist (false)
        // If nil (network error/offline), allow user to stay signed in
        if profileExists == false {
            Logger.warning("Orphaned auth state detected - user authenticated but no profile exists", category: "AuthManager")
            Logger.info("Signing user out to restart onboarding", category: "AuthManager")
            
            // Sign out the orphaned user
            do {
                try Auth.auth().signOut()
            } catch {
                Logger.error("Error signing out orphaned user", error: error, category: "AuthManager")
            }
            
            await MainActor.run {
                self.isCheckingAuth = false
            }
            return
        } else if profileExists == nil {
            Logger.info("Cannot verify profile existence (offline/network error) - allowing sign in", category: "AuthManager")
            // Continue to sign in - Firebase offline persistence will work
        }
        
        // Update auth state on main thread
        await MainActor.run {
            // User is signed in with Firebase
            self.userId = currentUser.uid
            self.isSignedIn = true
            self.isCheckingAuth = false
            Logger.success("User already signed in: \(currentUser.uid)", category: "AuthManager")
            Logger.debug("Set isCheckingAuth = false, isSignedIn = true")
        }
        
        Logger.debug("checkAuthState() completed")
        Logger.debug("Final state: isCheckingAuth=\(isCheckingAuth), isSignedIn=\(isSignedIn)")
        
        // Load user profile via ProfileManager (in background, non-blocking)
        Task.detached(priority: .medium) { [weak self] in
            await self?.loadUserProfileViaProfileManager(userId: currentUser.uid)
        }
    }
    
    /// Check if user profile exists in Firestore
    /// Returns: true = exists, false = doesn't exist, nil = couldn't determine (network error)
    private func checkUserProfileExists(userId: String) async -> Bool? {
        return await firebaseService.userProfileExists(userId: userId)
    }
    
    /// Load user profile via ProfileManager (single source of truth)
    private func loadUserProfileViaProfileManager(userId: String) async {
        Logger.info("Requesting ProfileManager to load profile for userId: \(userId)", category: "AuthManager")
        
        await MainActor.run {
            profileManager?.loadProfile(userId: userId)
        }
        
        // Prefetch own profile pic after profile is loaded
        // Wait a moment for profile to load
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        await MainActor.run {
            if let profileManager = self.profileManager,
               let avatarUrl = profileManager.currentUserProfile?.avatarUrl,
               !avatarUrl.isEmpty {
                Task.detached { [weak self, userId] in
                    guard let self = self else { return }
                    do {
                        _ = try await self.imageManager.downloadAndCacheProfilePicture(url: avatarUrl, userId: userId)
                        await MainActor.run {
                            Logger.success("Prefetched own profile picture", category: "AuthManager")
                        }
                    } catch {
                        await MainActor.run {
                            Logger.warning("Failed to prefetch profile picture", category: "AuthManager")
                        }
                    }
                }
            }
        }
    }
    
    func signInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        
        // Store controller to prevent deallocation before authorization completes
        self.authController = controller
        controller.performRequests()
    }
    
    /// Async version of Sign in with Apple for invite flow
    /// Returns AuthDataResult without creating Firestore profile (invite flow handles that)
    func signInWithAppleAsync() async throws -> AuthDataResult {
        // Prevent multiple simultaneous sign in attempts (race condition protection)
        guard signInContinuation == nil else {
            Logger.warning("Sign in already in progress, rejecting duplicate attempt", category: "AuthManager")
            throw NSError(domain: "AuthManager", code: 100, 
                         userInfo: [NSLocalizedDescriptionKey: "Sign in already in progress. Please wait."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.signInContinuation = continuation
            
            let nonce = randomNonceString()
            currentNonce = nonce
            
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            
            // Store controller to prevent deallocation before authorization completes
            self.authController = controller
            controller.performRequests()
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isSignedIn = false
            userId = nil
            appleSignInGivenName = nil // Clear stored name
            profileManager?.clearProfile() // Clear ProfileManager state on sign out
            Logger.success("User signed out successfully", category: "AuthManager")
            // Don't set isCheckingAuth = true here - we know the state immediately
        } catch {
            Logger.error("Sign out failed", error: error, category: "AuthManager")
        }
    }
    
    // MARK: - Apple Sign In Helpers
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                Logger.error("Invalid state: A login callback was received, but no login request was sent", category: "AuthManager")
                signInContinuation?.resume(throwing: NSError(domain: "AuthManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid state"]))
                signInContinuation = nil
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                Logger.error("Unable to fetch identity token", category: "AuthManager")
                signInContinuation?.resume(throwing: NSError(domain: "AuthManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to fetch identity token"]))
                signInContinuation = nil
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                Logger.error("Unable to serialize token string from data: \(appleIDToken.debugDescription)", category: "AuthManager")
                signInContinuation?.resume(throwing: NSError(domain: "AuthManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to serialize token"]))
                signInContinuation = nil
                return
            }
            
            // Initialize a Firebase credential with the Apple ID token
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce
            )
            
            // Sign in with Firebase
            Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                guard let self = self else { return }
                
                if let error = error {
                    Logger.error("Firebase sign in failed", error: error, category: "AuthManager")
                    self.signInContinuation?.resume(throwing: error)
                    self.signInContinuation = nil
                    return
                }
                
                guard let authResult = authResult else {
                    Logger.error("No auth result returned", category: "AuthManager")
                    self.signInContinuation?.resume(throwing: NSError(domain: "AuthManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "No auth result"]))
                    self.signInContinuation = nil
                    return
                }
                
                let user = authResult.user
                Logger.success("Firebase sign in successful for user: \(user.uid)", category: "AuthManager")
                
                // Store the given name for username generation (first sign in only)
                if let givenName = appleIDCredential.fullName?.givenName {
                    Task { @MainActor in
                        self.appleSignInGivenName = givenName
                        Logger.info("Captured given name from Apple Sign In: \(givenName)", category: "AuthManager")
                    }
                }
                
                // If this is the async flow (invite), resume continuation and DON'T create profile
                if self.signInContinuation != nil {
                    Logger.debug("Async sign in - returning AuthDataResult without profile creation")
                    self.signInContinuation?.resume(returning: authResult)
                    self.signInContinuation = nil
                    return
                }
                
                // Regular sign in flow - create/update profile
                let displayName = user.displayName ?? appleIDCredential.fullName?.givenName ?? "User"
                
                // Update user info
                self.userId = user.uid
                self.isSignedIn = true
                
                Logger.success("Updated auth state - userId: \(user.uid), isSignedIn: true", category: "AuthManager")
                
                // Update Firebase Auth display name if this is first sign in
                if user.displayName == nil, let fullName = appleIDCredential.fullName?.givenName {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = fullName
                    changeRequest.commitChanges { error in
                        if let error = error {
                            Logger.warning("Error updating display name: \(error.localizedDescription)", category: "AuthManager")
                        }
                    }
                }
                
                // Create or update Firestore user profile
                Task {
                    await self.createOrUpdateUserProfile(userId: user.uid, displayName: displayName)
                }
            }
        }
    }
    
    /// Create or update user profile in Firestore
    @MainActor
    private func createOrUpdateUserProfile(userId: String, displayName: String) async {
        Logger.info("Creating/updating user profile for userId: \(userId)", category: "AuthManager")
        do {
            // Try to fetch existing profile
            if var existingProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                // Validate existing username for profanity (safety check for legacy profiles)
                do {
                    let moderationService = ContentModerationService.shared
                    let validationResult = try await moderationService.validateContent(username: existingProfile.username)
                    
                    if !validationResult.isValid {
                        Logger.warning("Existing username '\(existingProfile.username)' failed validation: \(validationResult.usernameError ?? "unknown error")", category: "AuthManager")
                        // Generate safe fallback username
                        let randomNumber = Int.random(in: AppConfig.usernameRandomNumberRange)
                        let newUsername = "user\(randomNumber)"
                        Logger.info("Replacing with safe username: \(newUsername)", category: "AuthManager")
                        
                        // Update profile with new username
                        try await firebaseService.updateUserProfile(userId: userId, username: newUsername)
                        
                        // Fetch updated profile
                        if let updatedProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                            existingProfile = updatedProfile
                        }
                    }
                } catch {
                    Logger.error("Username validation failed for existing profile", error: error, category: "AuthManager")
                    // Continue with existing username if validation service fails
                }
                
                // Profile exists, sync it to ProfileManager
                profileManager?.updateProfile(existingProfile)
                
                Logger.success("Found existing profile: @\(existingProfile.username)", category: "AuthManager")
                
                // Save back to Firebase to ensure username is persisted (for legacy migrations)
                try await firebaseService.saveUserProfile(existingProfile)
                
                Logger.success("Updated user profile for \(displayName) (@\(existingProfile.username))", category: "AuthManager")
            } else {
                Logger.info("No existing profile found, creating new one", category: "AuthManager")
                // Profile doesn't exist, create it
                // Generate initial username: firstname + random 5-digit number
                let firstName = displayName.components(separatedBy: " ").first ?? "user"
                let cleanFirstName = firstName.lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                
                // Generate random 5-digit number
                let randomNumber = Int.random(in: AppConfig.usernameRandomNumberRange)
                var initialUsername = cleanFirstName + "\(randomNumber)"
                
                // Validate auto-generated username for profanity (safety check)
                // If it contains inappropriate content, use safe fallback
                do {
                    let moderationService = ContentModerationService.shared
                    let validationResult = try await moderationService.validateContent(username: initialUsername)
                    
                    if !validationResult.isValid {
                        Logger.warning("Auto-generated username '\(initialUsername)' failed validation: \(validationResult.usernameError ?? "unknown error")", category: "AuthManager")
                        // Use safe fallback: "user" + random number
                        initialUsername = "user\(randomNumber)"
                        Logger.info("Using fallback username: \(initialUsername)", category: "AuthManager")
                    }
                } catch {
                    Logger.error("Username validation failed, using as-is", error: error, category: "AuthManager")
                    // If validation service fails, proceed with generated username
                }
                
                Logger.info("Creating profile with username: @\(initialUsername)", category: "AuthManager")
                
                try await firebaseService.createUserProfile(userId: userId, username: initialUsername, displayName: displayName)
                
                // Fetch the newly created profile and sync to ProfileManager
                if let newProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                    profileManager?.updateProfile(newProfile)
                    Logger.success("Synced new profile to ProfileManager", category: "AuthManager")
                }
                
                Logger.success("Created new user profile for \(displayName) (@\(initialUsername))", category: "AuthManager")
            }
            
            // Prefetch profile picture after profile is loaded
            if let profileManager = profileManager,
               let avatarUrl = profileManager.currentUserProfile?.avatarUrl,
               !avatarUrl.isEmpty {
                Task.detached { [weak self, userId] in
                    guard let self = self else { return }
                    do {
                        _ = try await self.imageManager.downloadAndCacheProfilePicture(url: avatarUrl, userId: userId)
                        await MainActor.run {
                            Logger.success("Prefetched profile picture after sign in", category: "AuthManager")
                        }
                    } catch {
                        await MainActor.run {
                            Logger.warning("Failed to prefetch profile picture", category: "AuthManager")
                        }
                    }
                }
            }
        } catch {
            Logger.error("Failed to create/update user profile", error: error, category: "AuthManager")
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Logger.error("Apple Sign In failed", error: error, category: "AuthManager")
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Return the key window for presenting the authorization UI
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available for presentation")
        }
        return window
    }
}
