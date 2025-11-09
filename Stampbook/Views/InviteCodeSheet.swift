import SwiftUI
import FirebaseAuth
import AuthenticationServices

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
    @State private var showError = false
    @State private var showInlineError = false // Show error inline instead of alert
    
    enum Page {
        case codeEntry
        case signIn
    }
    
    var body: some View {
        NavigationStack {
            Group {
                switch currentPage {
                case .codeEntry:
                    codeEntryPage
                case .signIn:
                    signInPage
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Page 1: X button on right to dismiss
                // Page 2: Back chevron on left to go back
                if currentPage == .codeEntry {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            withAnimation {
                                currentPage = .codeEntry
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Something went wrong")
            }
        }
        .presentationDetents([.height(480), .large])
        .presentationDragIndicator(.visible)
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
            .padding(.top, 32)
            .padding(.bottom, 20)
            
            // Code Input (Plain style)
            VStack(alignment: .leading, spacing: 8) {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding()
                    .background(Color(.systemBackground))
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
                .background(inviteCode.count >= 4 ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(inviteCode.count < 4 || isValidating)
            .padding(.horizontal)
            
            Spacer()
            
            // Already have account
            VStack(spacing: 8) {
                Text("Already have an account?")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Button(action: handleReturningUser) {
                    Text("Sign in with Apple")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
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
            .padding(.bottom, 32)
            
            // Sign in with Apple Button (Native)
            Button(action: signInWithApple) {
                SignInWithAppleButton(.signIn) { _ in }
                    onCompletion: { _ in }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 54)
                    .cornerRadius(12)
                    .allowsHitTesting(false)
            }
            .disabled(isCreatingAccount)
            .padding(.horizontal)
            
            Spacer()
            
            // Extra bottom padding
            Color.clear.frame(height: 40)
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
            
            do {
                // Perform Sign in with Apple using AuthManager
                let result = try await authManager.signInWithAppleAsync()
                
                // Generate username from user ID
                let username = "user_\(result.user.uid.prefix(8))"
                
                // Create account with invite code
                try await inviteManager.createAccountWithInviteCode(
                    userId: result.user.uid,
                    username: username,
                    code: validatedCode
                )
                
                // Success! Update AuthManager state
                await MainActor.run {
                    authManager.isSignedIn = true
                    authManager.userId = result.user.uid
                }
                
                // Load the newly created profile via ProfileManager
                Task {
                    if let profile = try? await FirebaseService.shared.fetchUserProfile(userId: result.user.uid) {
                        await MainActor.run {
                            authManager.profileManager?.updateProfile(profile)
                        }
                    }
                }
                
                isAuthenticated = true
                dismiss()
                
            } catch let error as InviteManager.InviteError {
                // Handle invite-specific errors
                errorMessage = error.localizedDescription
                showError = true
                
                // If code was fully used or account already exists, go back to code entry
                if case .codeFullyUsed = error {
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                } else if case .accountAlreadyExists = error {
                    // User already has account - send them back to use the "Already have account" button
                    withAnimation {
                        currentPage = .codeEntry
                        inviteCode = ""
                        validatedCode = ""
                    }
                }
            } catch {
                // Check if user cancelled Apple Sign In
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                    // User cancelled - just dismiss silently, no error needed
                    return
                }
                
                // Handle auth errors
                errorMessage = "Sign in failed: \(error.localizedDescription)"
                showError = true
            }
            
            isCreatingAccount = false
        }
    }
    
    private func handleReturningUser() {
        Task {
            isCreatingAccount = true
            errorMessage = nil
            
            do {
                // Sign in with Apple using AuthManager
                let result = try await authManager.signInWithAppleAsync()
                
                // Check if user profile exists
                let profileExists = await inviteManager.userProfileExists(userId: result.user.uid)
                
                if profileExists {
                    // Returning user - update AuthManager and let them in
                    await MainActor.run {
                        authManager.isSignedIn = true
                        authManager.userId = result.user.uid
                    }
                    
                    // Load their profile via ProfileManager
                    Task {
                        if let profile = try? await FirebaseService.shared.fetchUserProfile(userId: result.user.uid) {
                            await MainActor.run {
                                authManager.profileManager?.updateProfile(profile)
                            }
                        }
                    }
                    
                    isAuthenticated = true
                    dismiss()
                } else {
                    // New user trying to bypass - sign them out
                    try Auth.auth().signOut()
                    errorMessage = "No account found. You need an invite code to create a new account."
                    showError = true
                }
            } catch {
                // Check if user cancelled Apple Sign In
                let nsError = error as NSError
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" && nsError.code == 1001 {
                    // User cancelled - just dismiss silently, no error needed
                    return
                }
                
                // Show error for actual failures
                errorMessage = "Sign in failed: \(error.localizedDescription)"
                showError = true
            }
            
            isCreatingAccount = false
        }
    }
}

#Preview {
    InviteCodeSheet(isAuthenticated: .constant(false))
        .environmentObject(AuthManager())
}

