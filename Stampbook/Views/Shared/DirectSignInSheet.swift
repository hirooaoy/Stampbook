import SwiftUI
import FirebaseAuth

/// Simplified sign-in sheet that bypasses invite code requirement
/// Used for MVP after removing invite-only restriction
struct DirectSignInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var inviteManager = InviteManager()
    @Binding var isAuthenticated: Bool
    
    // UI State
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?
    @State private var errorTitle: String = "Error"
    @State private var showError = false
    @State private var showProfileLoadError = false
    @State private var pendingUserId: String? // Store userId for retry
    @State private var acceptedTerms = false // Terms of Service acceptance
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 8)
            
            // App logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .cornerRadius(16)
            
            // Welcome text
            VStack(spacing: 12) {
                Text("Create an account")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start collecting stamps around the world.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 16)
            
            // Terms of Service Checkbox
            HStack(alignment: .center, spacing: 8) {
                Button(action: {
                    acceptedTerms.toggle()
                }) {
                    Image(systemName: acceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(acceptedTerms ? .blue : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                
                HStack(spacing: 0) {
                    Text("I agree to the ")
                        .font(.footnote)
                        .foregroundColor(.primary)
                    
                    Button(action: {
                        if let url = URL(string: "https://stampbook-app.web.app/terms-of-service.html") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Terms of Service")
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .underline()
                    }
                    
                    Text(" and ")
                        .font(.footnote)
                        .foregroundColor(.primary)
                    
                    Button(action: {
                        if let url = URL(string: "https://stampbook-app.web.app/privacy-policy.html") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Privacy Policy")
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .underline()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            
            // Custom Sign in with Apple Button
            Button(action: signInWithApple) {
                HStack(spacing: 8) {
                    if isCreatingAccount {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: "applelogo")
                            .font(.system(size: 20, weight: .medium))
                        Text("Sign in with Apple")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(acceptedTerms && !isCreatingAccount ? .black : .gray)
                .frame(height: 54)
                .frame(maxWidth: .infinity)
                .background(acceptedTerms && !isCreatingAccount ? Color.white : Color.gray.opacity(0.2))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(acceptedTerms && !isCreatingAccount ? 0.1 : 0.05), lineWidth: 1)
                )
            }
            .disabled(!acceptedTerms || isCreatingAccount)
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert(errorTitle, isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong")
        }
        .alert("Connection Issue", isPresented: $showProfileLoadError) {
            Button("Try Again") {
                retryProfileLoad()
            }
            Button("Cancel", role: .cancel) {
                try? Auth.auth().signOut()
                authManager.isSignedIn = false
                authManager.userId = nil
                pendingUserId = nil
                dismiss()
            }
        } message: {
            Text("Your account was created successfully, but we couldn't load your profile due to a connection issue. Check your internet and try again.")
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreatingAccount)
    }
    
    // MARK: - Actions
    
    private func signInWithApple() {
        Task {
            isCreatingAccount = true
            errorMessage = nil
            showError = false
            
            Logger.info("🔐 Starting Sign in with Apple (direct flow, no invite)", category: "DirectSignInSheet")
            
            do {
                // Perform Sign in with Apple using AuthManager
                Logger.debug("Step 1: Calling signInWithAppleAsync")
                let result = try await authManager.signInWithAppleAsync()
                
                Logger.success("Step 1 Complete: Firebase Auth successful for \(result.user.uid)", category: "DirectSignInSheet")
                
                // Check if user profile exists (returning user vs new user)
                Logger.debug("Step 2: Checking if user profile already exists")
                let profileExists = await inviteManager.userProfileExists(userId: result.user.uid)
                
                if profileExists {
                    // RETURNING USER
                    Logger.success("Step 2 Complete: Profile found - returning user", category: "DirectSignInSheet")
                    
                    // Update AuthManager and let them in
                    await MainActor.run {
                        authManager.isSignedIn = true
                        authManager.userId = result.user.uid
                    }
                    
                    Logger.info("Step 3: Loading user profile", category: "DirectSignInSheet")
                    
                    // Load their profile via ProfileManager
                    do {
                        let profile = try await FirebaseService.shared.fetchUserProfile(userId: result.user.uid)
                        await MainActor.run {
                            authManager.profileManager?.updateProfile(profile)
                        }
                        Logger.success("Step 3 Complete: Profile loaded and cached", category: "DirectSignInSheet")
                        
                        dismiss()
                        Logger.success("✅ Returning user sign in completed successfully", category: "DirectSignInSheet")
                    } catch {
                        // Profile load failed - user exists but profile couldn't be fetched
                        Logger.error("Profile load failed for returning user", error: error, category: "DirectSignInSheet")
                        pendingUserId = result.user.uid
                        showProfileLoadError = true
                        isCreatingAccount = false
                        return
                    }
                } else {
                    // NEW USER - Create account without invite code
                    Logger.success("Step 2 Complete: No existing profile - creating new account", category: "DirectSignInSheet")
                    
                    // Generate username: firstname + random 5-digit number
                    let firstName = authManager.appleSignInGivenName ?? result.user.displayName?.components(separatedBy: " ").first ?? "user"
                    let cleanFirstName = firstName.lowercased()
                        .filter { $0.isLetter || $0.isNumber }
                    let randomNumber = Int.random(in: AppConfig.usernameRandomNumberRange)
                    var username = cleanFirstName + "\(randomNumber)"
                    
                    // Validate auto-generated username for profanity (safety check)
                    do {
                        let moderationService = ContentModerationService.shared
                        let validationResult = try await moderationService.validateContent(username: username)
                        
                        if !validationResult.isValid {
                            Logger.warning("Auto-generated username '\(username)' failed validation: \(validationResult.usernameError ?? "unknown error")", category: "DirectSignInSheet")
                            // Use safe fallback: "user" + random number
                            username = "user\(randomNumber)"
                            Logger.info("Using fallback username: \(username)", category: "DirectSignInSheet")
                        }
                    } catch {
                        Logger.error("Username validation failed, using as-is", error: error, category: "DirectSignInSheet")
                    }
                    
                    Logger.info("Step 3: Creating account with username: \(username)", category: "DirectSignInSheet")
                    
                    // Create account WITHOUT invite code (pass nil)
                    try await inviteManager.createAccountWithInviteCode(
                        userId: result.user.uid,
                        username: username,
                        code: nil // NO INVITE CODE REQUIRED
                    )
                    
                    Logger.success("Step 3 Complete: Account created successfully", category: "DirectSignInSheet")
                    
                    // Success! Update AuthManager state
                    await MainActor.run {
                        authManager.isSignedIn = true
                        authManager.userId = result.user.uid
                        authManager.appleSignInGivenName = nil // Clear stored name after use
                    }
                    
                    Logger.info("Step 4: Loading user profile", category: "DirectSignInSheet")
                    
                    // Load the newly created profile via ProfileManager
                    do {
                        let profile = try await FirebaseService.shared.fetchUserProfile(userId: result.user.uid)
                        await MainActor.run {
                            authManager.profileManager?.updateProfile(profile)
                        }
                        Logger.success("Step 4 Complete: Profile loaded and cached", category: "DirectSignInSheet")
                        
                        // Small delay to let ContentView fully render ProfileSetupPage
                        try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                        
                        dismiss()
                        Logger.success("✅ Account creation flow completed successfully", category: "DirectSignInSheet")
                    } catch {
                        // Profile load failed - account exists but profile couldn't be fetched
                        Logger.error("Profile load failed after account creation", error: error, category: "DirectSignInSheet")
                        pendingUserId = result.user.uid
                        showProfileLoadError = true
                        isCreatingAccount = false
                        return
                    }
                }
                
            } catch {
                // Check if user cancelled Apple Sign In
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                    Logger.info("User cancelled Apple Sign In", category: "DirectSignInSheet")
                    isCreatingAccount = false
                    return
                }
                
                // Check for duplicate sign in attempt (race condition)
                if nsError.domain == "AuthManager" && nsError.code == 100 {
                    Logger.warning("Duplicate sign in attempt blocked", category: "DirectSignInSheet")
                    isCreatingAccount = false
                    return
                }
                
                Logger.error("Unexpected error during sign in", error: error, category: "DirectSignInSheet")
                
                // Handle auth errors - sign out on failure
                try? Auth.auth().signOut()
                
                errorTitle = "Sign In Failed"
                errorMessage = "Unable to sign in. Please try again."
                showError = true
            }
            
            isCreatingAccount = false
        }
    }
    
    private func retryProfileLoad() {
        guard let userId = pendingUserId else { return }
        
        Task {
            isCreatingAccount = true
            
            do {
                Logger.info("Retrying profile load for userId: \(userId)", category: "DirectSignInSheet")
                let profile = try await FirebaseService.shared.fetchUserProfile(userId: userId)
                
                await MainActor.run {
                    authManager.profileManager?.updateProfile(profile)
                }
                
                Logger.success("Profile loaded successfully on retry", category: "DirectSignInSheet")
                
                dismiss()
            } catch {
                Logger.error("Profile load retry failed", error: error, category: "DirectSignInSheet")
                showProfileLoadError = true
                isCreatingAccount = false
            }
        }
    }
}

#Preview {
    DirectSignInSheet(isAuthenticated: .constant(false))
        .environmentObject(AuthManager())
}

