import SwiftUI

/// First-time profile setup page shown after sign-up
/// Matches InviteCodeSheet design for visual consistency
struct ProfileSetupPage: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    
    var onDismiss: () -> Void = {}
    
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var isSaving = false
    @State private var isCheckingUsername = false
    @State private var usernameAvailable: Bool? = nil
    @State private var errorMessage: String?
    @State private var usernameErrorMessage: String?
    
    private let firebaseService = FirebaseService.shared
    private let moderationService = ContentModerationService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header (exactly like invite code page)
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                
                Text("Create Your Profile")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Enter your username to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 80)
            .padding(.bottom, 20)
            
            // Username Field
            VStack(alignment: .leading, spacing: 8) {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
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
                            .stroke(shouldShowRedBorder ? Color.red : Color(.systemGray4), lineWidth: 1)
                    )
                    .disabled(isSaving)
                    .onChange(of: username) { oldValue, newValue in
                        // Clean username: only letters and numbers, max 20 characters
                        var cleaned = newValue.lowercased().filter { $0.isLetter || $0.isNumber }
                        
                        // Limit to 20 characters
                        if cleaned.count > 20 {
                            cleaned = String(cleaned.prefix(20))
                        }
                        
                        if cleaned != newValue {
                            username = cleaned
                        }
                        
                        // Clear errors when user types
                        usernameErrorMessage = nil
                        errorMessage = nil
                        usernameAvailable = nil
                        
                        // Trigger validation
                        validateUsernameDebounced()
                    }
                
                // Fixed height container for validation feedback to prevent layout shifts
                Group {
                    // Validation feedback (matches InviteCodeSheet style)
                if isCheckingUsername {
                        HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let error = usernameErrorMessage {
                        // Length-related messages are hints (gray, no icon)
                        // Other errors are actual errors (red, with icon)
                        if error == "Must be at least 3 characters" || error == "Must be 20 characters or less" {
                            Text(error)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                        }
                } else if let available = usernameAvailable, !username.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            Text(available ? "Available" : "Username taken")
                        }
                        .foregroundColor(available ? .green : .red)
                            .font(.caption)
                    } else {
                        // Empty spacer to maintain height
                        Text(" ")
                            .font(.caption)
                    }
                }
                .frame(height: 20, alignment: .leading)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Confirm Button (same style as Continue)
            Button(action: saveProfile) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Confirm")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(canSave ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canSave || isSaving)
            .padding(.horizontal)
            
            // Skip link
            Button(action: skipSetup) {
                Text("Skip and set up later")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .disabled(isSaving)
            .padding(.bottom, 32)
        }
    }
    
    private var canSave: Bool {
        !username.isEmpty &&
        username.count >= 3 &&
        usernameAvailable == true &&
        !isSaving
    }
    
    private var shouldShowRedBorder: Bool {
        guard let error = usernameErrorMessage else { return false }
        // Don't show red border for length hints
        return error != "Must be at least 3 characters" && error != "Must be 20 characters or less"
    }
    
    private func validateUsernameDebounced() {
        // Validate length
        guard username.count >= 3 else {
            usernameAvailable = nil
            usernameErrorMessage = username.isEmpty ? nil : "Must be at least 3 characters"
            return
        }
        
        guard username.count <= 20 else {
            usernameAvailable = false
            usernameErrorMessage = "Must be 20 characters or less"
            return
        }
        
        let textToCheck = username
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            
            guard textToCheck == username else { return }
            
            guard let userId = authManager.userId else { return }
            
            await MainActor.run {
                isCheckingUsername = true
                usernameErrorMessage = nil
            }
            
            do {
                let result = try await moderationService.checkUsernameAvailability(username: username, excludeUserId: userId)
                
                await MainActor.run {
                    self.usernameAvailable = result.isAvailable
                    self.isCheckingUsername = false
                    
                    // Show reason if unavailable (includes profanity/inappropriate content)
                    if !result.isAvailable, let reason = result.reason {
                        self.usernameErrorMessage = reason
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCheckingUsername = false
                    self.usernameErrorMessage = "Couldn't check availability"
                }
            }
        }
    }
    
    private func saveProfile() {
        guard let userId = authManager.userId else { return }
        
        Task {
            isSaving = true
            errorMessage = nil
            
            do {
                // Update profile in Firestore (displayName same as username)
                try await firebaseService.updateUserProfile(
                    userId: userId,
                    displayName: username,
                    username: username,
                    hasSeenOnboarding: true
                )
                
                Logger.success("Profile setup completed: @\(username)", category: "ProfileSetupPage")
                
                // Refresh profile in ProfileManager
                if let updatedProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                    await MainActor.run {
                        profileManager.updateProfile(updatedProfile)
                    }
                }
                
                await MainActor.run {
                    isSaving = false
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save profile. Please try again."
                }
                Logger.error("Profile setup failed", error: error, category: "ProfileSetupPage")
            }
        }
    }
    
    private func skipSetup() {
        guard let userId = authManager.userId else {
            onDismiss()
            return
        }
        
        Task {
            // Mark as seen even though they skipped
            try? await firebaseService.updateUserProfile(
                userId: userId,
                hasSeenOnboarding: true
            )
            
            Logger.info("User skipped profile setup", category: "ProfileSetupPage")
            
            // Refresh profile to get updated hasSeenOnboarding flag
            if let updatedProfile = try? await firebaseService.fetchUserProfile(userId: userId) {
                await MainActor.run {
                    profileManager.updateProfile(updatedProfile)
                }
            }
            
            await MainActor.run {
                onDismiss()
            }
        }
    }
}

