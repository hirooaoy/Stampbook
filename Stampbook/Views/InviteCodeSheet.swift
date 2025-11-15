import SwiftUI
import FirebaseAuth

/// Two-page sheet for invite code entry and Sign in with Apple
struct InviteCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var inviteManager = InviteManager()
    @Binding var isAuthenticated: Bool
    
    // Sheet navigation
    @State private var currentPage: Page = .codeEntry
    @State private var inviteCode = ""
    @State private var validatedCode = ""
    
    // UI State
    @State private var isValidating = false
    @State private var isCreatingAccount = false
    @State private var errorMessage: String?
    @State private var errorTitle: String = "Error"
    @State private var showError = false
    @State private var showInlineError = false // Show error inline instead of alert
    @State private var showProfileLoadError = false
    @State private var pendingUserId: String? // Store userId for retry
    
    enum Page {
        case codeEntry
        case signIn
    }
    
    var body: some View {
        Group {
            switch currentPage {
            case .codeEntry:
                codeEntryPage
            case .signIn:
                signInPage
            }
        }
        .toolbar {
            // X button on page 1, Back button on page 2
            if currentPage == .codeEntry {
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
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        // Clear validated code when going back
                        validatedCode = ""
                        withAnimation {
                            currentPage = .codeEntry
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
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
            Button("Sign Out", role: .cancel) {
                try? Auth.auth().signOut()
                authManager.isSignedIn = false
                authManager.userId = nil
                pendingUserId = nil
                dismiss()
            }
        } message: {
            Text("Your account was created successfully, but we couldn't load your profile due to a connection issue. Check your internet and try again.")
        }
        .presentationDetents(currentPage == .codeEntry ? [.height(480), .large] : [.height(360)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreatingAccount || isValidating)
    }
    
    // MARK: - Page 1: Code Entry
    
    private var codeEntryPage: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                
                Text("Stampbook is Invite Only")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter an invite code to join")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 64)
            .padding(.bottom, 20)
            
            // Code Input
            VStack(alignment: .leading, spacing: 8) {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(showInlineError ? Color.red : Color(.systemGray4), lineWidth: 1)
                    )
                    .disabled(isValidating)
                    .onChange(of: inviteCode) { oldValue, newValue in
                        // Auto-uppercase and limit to 20 characters
                        inviteCode = newValue.uppercased().prefix(20).description
                        // Clear error when user starts typing
                        if showInlineError {
                            showInlineError = false
                            errorMessage = nil
                        }
                    }
                
                // Error message
                if showInlineError, let error = errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            
            // Continue Button
            Button(action: validateAndContinue) {
                HStack {
                    if isValidating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(inviteCode.isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(inviteCode.isEmpty || isValidating)
            .padding(.horizontal)
            
            Spacer()
            
            // Already have account
            VStack(spacing: 8) {
                Text("Already have an account?")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Button(action: handleReturningUser) {
                    HStack(spacing: 4) {
                        if isCreatingAccount {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Sign in with Apple")
                            .font(.footnote)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(isCreatingAccount ? .gray : .blue)
                }
                .disabled(isCreatingAccount)
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Page 2: Sign In
    
    private var signInPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success Icon and Title
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                
                Text("You're invited!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Please continue to set up your account")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
            
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
                .foregroundColor(.black)
                .frame(height: 54)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
            }
            .disabled(isCreatingAccount)
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func validateAndContinue() {
        Task {
            isValidating = true
            errorMessage = nil
            showInlineError = false
            
            do {
                let isValid = try await inviteManager.validateCode(inviteCode)
                
                if isValid {
                    validatedCode = inviteCode.uppercased()
                    withAnimation {
                        currentPage = .signIn
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
                
                // Option 1: Inline error (default - looks better)
                showInlineError = true
                
                // Option 2: Also show alert for critical errors (uncomment to enable)
                // showError = true
                
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
            
            isValidating = false
        }
    }
    
    private func signInWithApple() {
        Task {
            isCreatingAccount = true
            errorMessage = nil
            showError = false
            showInlineError = false
            
            Logger.info("🔐 Starting Sign in with Apple (new account flow)", category: "InviteCodeSheet")
            
            do {
                // Perform Sign in with Apple using AuthManager
                Logger.debug("Step 1: Calling signInWithAppleAsync")
                let result = try await authManager.signInWithAppleAsync()
                
                Logger.success("Step 1 Complete: Firebase Auth successful for \(result.user.uid)", category: "InviteCodeSheet")
                
                // SAFETY CHECK: Verify user doesn't already have a profile (orphaned auth protection)
                Logger.debug("Step 2: Checking if user profile already exists")
                let profileExists = await inviteManager.userProfileExists(userId: result.user.uid)
                
                if profileExists {
                    Logger.warning("User profile already exists - redirecting to returning user flow", category: "InviteCodeSheet")
                    try? Auth.auth().signOut()
                    
                    errorTitle = "You already have an account"
                    errorMessage = "Please use 'Already have an account' to sign in."
                    showError = true
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                    isCreatingAccount = false
                    return
                }
                
                Logger.success("Step 2 Complete: No existing profile found", category: "InviteCodeSheet")
                
                // Generate username: firstname + random 5-digit number
                let firstName = authManager.appleSignInGivenName ?? result.user.displayName?.components(separatedBy: " ").first ?? "user"
                let cleanFirstName = firstName.lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                let randomNumber = Int.random(in: AppConfig.usernameRandomNumberRange)
                var username = cleanFirstName + "\(randomNumber)"
                
                // Validate auto-generated username for profanity (safety check)
                // If it contains inappropriate content, use safe fallback
                do {
                    let moderationService = ContentModerationService.shared
                    let validationResult = try await moderationService.validateContent(username: username)
                    
                    if !validationResult.isValid {
                        Logger.warning("Auto-generated username '\(username)' failed validation: \(validationResult.usernameError ?? "unknown error")", category: "InviteCodeSheet")
                        // Use safe fallback: "user" + random number
                        username = "user\(randomNumber)"
                        Logger.info("Using fallback username: \(username)", category: "InviteCodeSheet")
                    }
                } catch {
                    Logger.error("Username validation failed, using as-is", error: error, category: "InviteCodeSheet")
                    // If validation service fails, proceed with generated username
                    // User will see ProfileSetupSheet immediately where they can change it
                }
                
                Logger.info("Step 3: Creating account with username: \(username) (from name: \(firstName))", category: "InviteCodeSheet")
                
                // Create account with invite code
                try await inviteManager.createAccountWithInviteCode(
                    userId: result.user.uid,
                    username: username,
                    code: validatedCode
                )
                
                Logger.success("Step 3 Complete: Account created successfully", category: "InviteCodeSheet")
                
                // Success! Update AuthManager state
                await MainActor.run {
                    authManager.isSignedIn = true
                    authManager.userId = result.user.uid
                    authManager.appleSignInGivenName = nil // Clear stored name after use
                }
                
                Logger.info("Step 4: Loading user profile", category: "InviteCodeSheet")
                
                // Load the newly created profile via ProfileManager
                do {
                    let profile = try await FirebaseService.shared.fetchUserProfile(userId: result.user.uid)
                    await MainActor.run {
                        authManager.profileManager?.updateProfile(profile)
                    }
                    Logger.success("Step 4 Complete: Profile loaded and cached", category: "InviteCodeSheet")
                    
                    // Small delay to let ContentView fully render ProfileSetupPage
                    // Ensures smooth transition with no flash of underlying view
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
                    
                    dismiss()
                    Logger.success("✅ Account creation flow completed successfully", category: "InviteCodeSheet")
                } catch {
                    // Profile load failed - account exists but profile couldn't be fetched
                    Logger.error("Profile load failed after account creation", error: error, category: "InviteCodeSheet")
                    pendingUserId = result.user.uid
                    showProfileLoadError = true
                    isCreatingAccount = false
                    return
                }
                
            } catch let error as InviteManager.InviteError {
                Logger.error("Invite error occurred", error: error, category: "InviteCodeSheet")
                
                // Handle invite-specific errors with descriptive titles
                switch error {
                case .codeFullyUsed:
                    // Sign out since the code became unavailable after validation
                    try? Auth.auth().signOut()
                    
                    errorTitle = "Code Unavailable"
                    errorMessage = error.localizedDescription
                    showError = true
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                    
                case .accountAlreadyExists:
                    // Sign out the Firebase Auth user since they shouldn't use this flow
                    try? Auth.auth().signOut()
                    
                    errorTitle = "You already have an account"
                    errorMessage = "Please use 'Already have an account' to sign in."
                    showError = true
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                    
                case .accountCreationFailed:
                    // Sign out on account creation failure
                    try? Auth.auth().signOut()
                    
                    errorTitle = "Account Creation Failed"
                    errorMessage = "Something went wrong. Please try again."
                    showError = true
                    
                case .invalidCode, .codeExpired, .networkError:
                    // These should be caught during validation (inline errors)
                    // But handle them just in case
                    // Sign out if we got here with an invalid code
                    try? Auth.auth().signOut()
                    
                    errorTitle = "Error"
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } catch {
                // Check if user cancelled Apple Sign In
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                    Logger.info("User cancelled Apple Sign In", category: "InviteCodeSheet")
                    // User cancelled - reset state and dismiss silently
                    isCreatingAccount = false
                    return
                }
                
                // Check for duplicate sign in attempt (race condition)
                if nsError.domain == "AuthManager" && nsError.code == 100 {
                    Logger.warning("Duplicate sign in attempt blocked", category: "InviteCodeSheet")
                    // Silent fail - UI is already showing processing state
                    isCreatingAccount = false
                    return
                }
                
                // Check for transaction errors that indicate account already exists
                if nsError.domain == "InviteError" && nsError.code == 5 {
                    Logger.error("Account already exists (transaction error)", category: "InviteCodeSheet")
                    try? Auth.auth().signOut()
                    
                    errorTitle = "You already have an account"
                    errorMessage = "Please use 'Already have an account' to sign in."
                    showError = true
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                    isCreatingAccount = false
                    return
                }
                
                Logger.error("Unexpected error during sign in", error: error, category: "InviteCodeSheet")
                
                // Handle auth errors - sign out on failure
                try? Auth.auth().signOut()
                
                errorTitle = "Sign In Failed"
                errorMessage = "Unable to sign in. Please try again."
                showError = true
            }
            
            isCreatingAccount = false
        }
    }
    
    private func handleReturningUser() {
        Task {
            isCreatingAccount = true
            errorMessage = nil
            showError = false
            showInlineError = false
            
            Logger.info("🔐 Starting Sign in with Apple (returning user flow)", category: "InviteCodeSheet")
            
            do {
                // Sign in with Apple using AuthManager
                Logger.debug("Step 1: Calling signInWithAppleAsync")
                let result = try await authManager.signInWithAppleAsync()
                
                Logger.success("Step 1 Complete: Firebase Auth successful for \(result.user.uid)", category: "InviteCodeSheet")
                
                // Check if user profile exists
                Logger.debug("Step 2: Checking if user profile exists")
                let profileExists = await inviteManager.userProfileExists(userId: result.user.uid)
                
                if profileExists {
                    Logger.success("Step 2 Complete: Profile found - returning user verified", category: "InviteCodeSheet")
                    
                    // Returning user - update AuthManager and let them in
                    await MainActor.run {
                        authManager.isSignedIn = true
                        authManager.userId = result.user.uid
                    }
                    
                    Logger.info("Step 3: Loading user profile", category: "InviteCodeSheet")
                    
                    // Load their profile via ProfileManager
                    do {
                        let profile = try await FirebaseService.shared.fetchUserProfile(userId: result.user.uid)
                        await MainActor.run {
                            authManager.profileManager?.updateProfile(profile)
                        }
                        Logger.success("Step 3 Complete: Profile loaded and cached", category: "InviteCodeSheet")
                        
                        // Dismiss directly - authManager.isSignedIn already set to true (line 518)
                        // Don't set isAuthenticated here to avoid sheet recreation & page flash
                        dismiss()
                        
                        Logger.success("✅ Returning user sign in completed successfully", category: "InviteCodeSheet")
                    } catch {
                        // Profile load failed - user exists but profile couldn't be fetched
                        Logger.error("Profile load failed for returning user", error: error, category: "InviteCodeSheet")
                        pendingUserId = result.user.uid
                        showProfileLoadError = true
                        isCreatingAccount = false
                        return
                    }
                } else {
                    Logger.warning("Step 2: No profile found - new user trying to bypass", category: "InviteCodeSheet")
                    
                    // New user trying to bypass - sign them out
                    try Auth.auth().signOut()
                    errorTitle = "No Account Found"
                    errorMessage = "You need an invite code to create a new account."
                    showError = true
                }
            } catch {
                // Check if user cancelled Apple Sign In
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                    Logger.info("User cancelled Apple Sign In", category: "InviteCodeSheet")
                    // User cancelled - reset state and dismiss silently
                    isCreatingAccount = false
                    return
                }
                
                // Check for duplicate sign in attempt (race condition)
                if nsError.domain == "AuthManager" && nsError.code == 100 {
                    Logger.warning("Duplicate sign in attempt blocked", category: "InviteCodeSheet")
                    // Silent fail - UI is already showing processing state
                    isCreatingAccount = false
                    return
                }
                
                Logger.error("Error during returning user sign in", error: error, category: "InviteCodeSheet")
                
                // Show error for actual failures
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
                Logger.info("Retrying profile load for userId: \(userId)", category: "InviteCodeSheet")
                let profile = try await FirebaseService.shared.fetchUserProfile(userId: userId)
                
                await MainActor.run {
                    authManager.profileManager?.updateProfile(profile)
                }
                
                Logger.success("Profile loaded successfully on retry", category: "InviteCodeSheet")
                
                // Dismiss directly - authManager.isSignedIn already set from previous attempt
                // Don't set isAuthenticated here to avoid sheet recreation & page flash
                dismiss()
            } catch {
                Logger.error("Profile load retry failed", error: error, category: "InviteCodeSheet")
                // Show error again
                showProfileLoadError = true
                isCreatingAccount = false
            }
        }
    }
}

#Preview {
    InviteCodeSheet(isAuthenticated: .constant(false))
        .environmentObject(AuthManager())
}

