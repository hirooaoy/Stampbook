import Foundation
import Combine
import AuthenticationServices
import FirebaseAuth
import CryptoKit

class AuthManager: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var userId: String?
    @Published var userDisplayName: String?
    @Published var userProfile: UserProfile?
    
    // For Apple Sign In with Firebase
    private var currentNonce: String?
    private let firebaseService = FirebaseService.shared
    private let imageManager = ImageManager.shared
    
    override init() {
        super.init()
        checkAuthState()
    }
    
    /// Check if user is already signed in with Firebase
    private func checkAuthState() {
        if let currentUser = Auth.auth().currentUser {
            // User is signed in with Firebase
            userId = currentUser.uid
            userDisplayName = currentUser.displayName ?? "User"
            isSignedIn = true
            
            print("✅ [AuthManager] User already signed in: \(currentUser.uid)")
            
            // Load user profile from Firestore
            Task {
                await loadUserProfile(userId: currentUser.uid)
            }
        } else {
            print("ℹ️ [AuthManager] No user signed in")
        }
    }
    
    /// Load user profile from Firestore
    @MainActor
    private func loadUserProfile(userId: String) async {
        print("🔄 [AuthManager] Loading user profile for userId: \(userId)")
        do {
            userProfile = try await firebaseService.fetchUserProfile(userId: userId)
            userDisplayName = userProfile?.displayName ?? "User"
            print("✅ [AuthManager] User profile loaded: \(userProfile?.displayName ?? "unknown")")
            
            // Prefetch own profile pic for instant display across app
            prefetchOwnProfilePicture()
        } catch {
            print("⚠️ [AuthManager] Failed to load user profile: \(error.localizedDescription)")
            // Profile doesn't exist yet, will be created on next sign in
        }
    }
    
    /// Prefetch user's own profile pic on app launch (instant profile tab)
    private func prefetchOwnProfilePicture() {
        guard let avatarUrl = userProfile?.avatarUrl, !avatarUrl.isEmpty else { return }
        guard let currentUserId = userId else { return }
        
        Task.detached { [weak self, currentUserId] in
            guard let self = self else { return }
            do {
                try await self.imageManager.downloadAndCacheProfilePicture(url: avatarUrl, userId: currentUserId)
                print("✅ [AuthManager] Prefetched own profile picture")
            } catch {
                print("⚠️ [AuthManager] Failed to prefetch profile picture: \(error.localizedDescription)")
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
        controller.performRequests()
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isSignedIn = false
            userId = nil
            userDisplayName = nil
            userProfile = nil
        } catch {
            print("Error signing out: \(error.localizedDescription)")
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
                print("Invalid state: A login callback was received, but no login request was sent.")
                return
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
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
                    print("❌ [AuthManager] Firebase sign in error: \(error.localizedDescription)")
                    return
                }
                
                guard let user = authResult?.user else {
                    print("❌ [AuthManager] No user returned from auth result")
                    return
                }
                
                print("✅ [AuthManager] Firebase sign in successful for user: \(user.uid)")
                
                let displayName = user.displayName ?? appleIDCredential.fullName?.givenName ?? "User"
                
                // Update user info
                self.userId = user.uid
                self.userDisplayName = displayName
                self.isSignedIn = true
                
                print("✅ [AuthManager] Updated auth state - userId: \(user.uid), isSignedIn: true")
                
                // Update Firebase Auth display name if this is first sign in
                if user.displayName == nil, let fullName = appleIDCredential.fullName?.givenName {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = fullName
                    changeRequest.commitChanges { error in
                        if let error = error {
                            print("⚠️ [AuthManager] Error updating display name: \(error.localizedDescription)")
                        }
                    }
                }
                
                // Create or update Firestore user profile
                Task {
                    await self.createOrUpdateUserProfile(userId: user.uid, displayName: displayName)
                    
                    // Prefetch own profile pic after sign in
                    await MainActor.run {
                        self.prefetchOwnProfilePicture()
                    }
                }
            }
        }
    }
    
    /// Create or update user profile in Firestore
    @MainActor
    private func createOrUpdateUserProfile(userId: String, displayName: String) async {
        print("🔄 [AuthManager] Creating/updating user profile for userId: \(userId)")
        do {
            // Try to fetch existing profile
            if let existingProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                // Profile exists, update it
                userProfile = existingProfile
                
                print("✅ [AuthManager] Found existing profile: @\(existingProfile.username)")
                
                // Save back to Firebase to ensure username is persisted (for legacy migrations)
                try await firebaseService.saveUserProfile(existingProfile)
                
                print("✅ [AuthManager] Updated user profile for \(displayName) (@\(existingProfile.username))")
            } else {
                print("🔄 [AuthManager] No existing profile found, creating new one")
                // Profile doesn't exist, create it
                // Generate initial username: firstname + random 5-digit number
                let firstName = displayName.components(separatedBy: " ").first ?? "user"
                let cleanFirstName = firstName.lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                
                // Generate random 5-digit number
                let randomNumber = Int.random(in: 10000...99999)
                let initialUsername = cleanFirstName + "\(randomNumber)"
                
                print("🔄 [AuthManager] Creating profile with username: @\(initialUsername)")
                
                try await firebaseService.createUserProfile(userId: userId, username: initialUsername, displayName: displayName)
                userProfile = try? await firebaseService.fetchUserProfile(userId: userId)
                print("✅ [AuthManager] Created new user profile for \(displayName) (@\(initialUsername))")
            }
        } catch {
            print("❌ [AuthManager] Failed to create/update user profile: \(error.localizedDescription)")
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Apple Sign In failed: \(error.localizedDescription)")
    }
}
