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
    @Published var isCheckingAuth = true  // Track if we're still checking auth state
    
    // For Apple Sign In with Firebase
    private var currentNonce: String?
    private var authController: ASAuthorizationController? // Keep controller alive during authorization
    private let firebaseService = FirebaseService.shared
    private let imageManager = ImageManager.shared
    
    // Reference to ProfileManager (set by ContentView after init)
    weak var profileManager: ProfileManager?
    
    override init() {
        super.init()
        print("⏱️ [AuthManager] init() started")
        
        // Defer auth check to avoid blocking app launch
        // Use regular Task (not detached) to maintain proper MainActor context
        Task { [weak self] in
            await self?.checkAuthState()
        }
        
        print("⏱️ [AuthManager] init() completed (auth check deferred)")
    }
    
    /// Check if user is already signed in with Firebase
    private func checkAuthState() async {
        print("⏱️ [AuthManager] checkAuthState() started")
        
        guard let currentUser = Auth.auth().currentUser else {
            print("ℹ️ [AuthManager] No user signed in")
            await MainActor.run {
                self.isCheckingAuth = false
            }
            return
        }
        
        // Update auth state on main thread
        await MainActor.run {
            // User is signed in with Firebase
            self.userId = currentUser.uid
            self.userDisplayName = currentUser.displayName ?? "User"
            self.isSignedIn = true
            self.isCheckingAuth = false
            print("✅ [AuthManager] User already signed in: \(currentUser.uid)")
            print("✅ [AuthManager] Set isCheckingAuth = false, isSignedIn = true")
        }
        
        print("⏱️ [AuthManager] checkAuthState() completed")
        print("⏱️ [AuthManager] Final state: isCheckingAuth=\(isCheckingAuth), isSignedIn=\(isSignedIn)")
        
        // Load user profile from Firestore (in background, non-blocking)
        Task.detached(priority: .medium) { [weak self] in
            await self?.loadUserProfile(userId: currentUser.uid)
        }
    }
    
    /// Load user profile from Firestore
    private func loadUserProfile(userId: String) async {
        print("🔄 [AuthManager] Loading user profile for userId: \(userId)")
        
        let fetchStart = Date()
        do {
            // Fetch profile (no timeout wrapper - let Firebase SDK handle network timeouts)
            var profile = try await firebaseService.fetchUserProfile(userId: userId)
            
            // Fetch counts on-demand for MVP scale (<100 users)
            let followerCount = try await firebaseService.fetchFollowerCount(userId: userId)
            let followingCount = try await firebaseService.fetchFollowingCount(userId: userId)
            
            // Update profile with actual counts from subcollections
            profile.followerCount = followerCount
            profile.followingCount = followingCount
            
            let duration = Date().timeIntervalSince(fetchStart)
            
            // Update published properties on MainActor
            await MainActor.run {
                self.userProfile = profile
                self.userDisplayName = profile.displayName
            }
            
            print("✅ [AuthManager] User profile loaded in \(String(format: "%.2f", duration))s: \(profile.displayName) (\(followerCount) followers, \(followingCount) following)")
            
            // Sync profile to ProfileManager
            await MainActor.run {
                if let profile = self.userProfile {
                    self.profileManager?.updateProfile(profile)
                print("✅ [AuthManager] Synced profile to ProfileManager")
                }
            }
            
            // Prefetch own profile pic for instant display across app
            prefetchOwnProfilePicture()
        } catch {
            let duration = Date().timeIntervalSince(fetchStart)
            print("⚠️ [AuthManager] Failed to load user profile after \(String(format: "%.2f", duration))s: \(error.localizedDescription)")
            // Profile doesn't exist yet, will be created on next sign in
            // App should still continue - profile is not critical for basic usage
        }
    }
    
    /// Prefetch user's own profile pic on app launch (instant profile tab)
    private func prefetchOwnProfilePicture() {
        guard let avatarUrl = userProfile?.avatarUrl, !avatarUrl.isEmpty else { return }
        guard let currentUserId = userId else { return }
        
        Task.detached { [weak self, currentUserId] in
            guard let self = self else { return }
            do {
                _ = try await self.imageManager.downloadAndCacheProfilePicture(url: avatarUrl, userId: currentUserId)
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
        controller.presentationContextProvider = self
        
        // Store controller to prevent deallocation before authorization completes
        self.authController = controller
        controller.performRequests()
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            isSignedIn = false
            userId = nil
            userDisplayName = nil
            userProfile = nil
            profileManager?.clearProfile() // Clear ProfileManager state on sign out
            // Don't set isCheckingAuth = true here - we know the state immediately
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
                
                // Sync profile to ProfileManager
                profileManager?.updateProfile(existingProfile)
                print("✅ [AuthManager] Synced existing profile to ProfileManager")
                
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
                
                // Sync new profile to ProfileManager
                if let newProfile = userProfile {
                    profileManager?.updateProfile(newProfile)
                    print("✅ [AuthManager] Synced new profile to ProfileManager")
                }
                
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
