import SwiftUI
import PhotosUI

/// Profile Editing Screen
/// Allows users to edit their display name, username, bio, and profile picture
/// 
/// Features:
/// - Server-side content moderation via Firebase Cloud Functions
/// - Username uniqueness validation (checks Firebase before saving)
/// - Profile photo upload with automatic old photo deletion
/// - Real-time input validation and sanitization
/// - Character limits: 20 for name/username, 70 for bio
/// - Username format: lowercase, alphanumeric + underscore only
/// - Profanity & reserved words filtering (server-side, cannot be bypassed)
struct ProfileEditView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    
    // Form fields - initialized from current profile
    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    
    // UI state
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var errorTitle = "Error"
    @State private var showError = false
    @State private var isCheckingUsername = false
    @State private var usernameError: String?
    @State private var displayNameError: String?
    
    // Content moderation service
    private let moderationService = ContentModerationService.shared
    
    let currentProfile: UserProfile
    let onSave: (UserProfile) -> Void
    
    /// Initialize with existing profile data
    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.currentProfile = profile
        self.onSave = onSave
        _username = State(initialValue: profile.username)
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Profile Photo
                    VStack(spacing: 16) {
                        if let image = profileImage {
                            // Show newly selected image
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            // Show existing profile picture with caching
                            ProfileImageView(
                                avatarUrl: currentProfile.avatarUrl,
                                userId: currentProfile.id,
                                size: 100
                            )
                        }
                        
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("Change Photo")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text("Profile Photo")
                }
                
                // MARK: - Username Field
                // Unique handle (e.g., @johndoe123) - changeable with 14-day cooldown
                // Format: lowercase, alphanumeric + underscore, 3-20 chars
                // Validated against Firestore for uniqueness on save
                Section {
                    HStack {
                        Text("@")
                            .foregroundColor(.secondary)
                        TextField("username", text: $username)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .onChange(of: username) { oldValue, newValue in
                                // Real-time sanitization: enforce lowercase, alphanumeric + underscore only
                                let filtered = newValue.lowercased()
                                    .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                
                                // Enforce 20 character limit
                                if filtered.count > 20 {
                                    username = String(filtered.prefix(20))
                                } else if filtered != newValue {
                                    username = filtered
                                }
                                
                                // Clear error when user starts typing a new username
                                if username != currentProfile.username {
                                    usernameError = nil
                                }
                            }
                    }
                } header: {
                    Text("Username")
                } footer: {
                    // Show validation errors, helpful info, or character limit warning
                    if let error = usernameError {
                        // Priority 1: Show validation errors in red
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } else if username != currentProfile.username && username.trimmingCharacters(in: .whitespaces).count >= 3 {
                        // Priority 2: Show helpful info when actively editing with valid length
                        Text("Username can be changed once every 14 days")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else if username.count >= 20 {
                        // Priority 3: Character limit warning
                        Text("Max characters reached")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                // MARK: - Display Name Field
                // User's public display name (e.g., "John Doe")
                // 20 character limit
                Section {
                    TextField("Display Name", text: $displayName)
                        .autocorrectionDisabled()
                        .onChange(of: displayName) { oldValue, newValue in
                            // Enforce 20 character limit
                            if newValue.count > 20 {
                                displayName = String(newValue.prefix(20))
                            }
                            // Clear error when user starts typing
                            if displayNameError != nil {
                                displayNameError = nil
                            }
                        }
                } header: {
                    Text("Name")
                } footer: {
                    // Show validation errors first, then character limit
                    if let error = displayNameError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    } else if displayName.count >= 20 {
                        Text("Max characters reached")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                // MARK: - Bio Field
                // Short description about the user (70 character limit)
                Section {
                    ZStack(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("Tell others about yourself...")
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        }
                        TextEditor(text: $bio)
                            .frame(minHeight: 100)
                            .opacity(bio.isEmpty ? 0.25 : 1)
                            .onChange(of: bio) { oldValue, newValue in
                                // Enforce 70 character limit
                                if newValue.count > 70 {
                                    bio = String(newValue.prefix(70))
                                }
                            }
                    }
                } header: {
                    Text("Bio")
                } footer: {
                    if bio.count >= 70 {
                        Text("Max characters reached")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // MARK: - Navigation Buttons
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(
                        // Validate before allowing save
                        displayName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        username.trimmingCharacters(in: .whitespaces).isEmpty ||
                        username.trimmingCharacters(in: .whitespaces).count < 3 ||
                        isLoading
                    )
                }
            }
            .overlay {
                // MARK: - Loading Overlay
                // Full-screen loading indicator shown during save
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .alert(errorTitle, isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onChange(of: selectedPhoto) { oldValue, newValue in
                // MARK: - Photo Selection Handler
                // Load and immediately resize selected photo for efficient UI rendering
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        // ⚡ OPTIMIZATION: Resize immediately to avoid decoding huge images in UI
                        // This prevents 3+ second decode delays when displaying the preview
                        // The image will be resized again on upload (to 200x200), but this
                        // intermediate resize (to 800px) makes the UI smooth
                        let resizedImage = ImageManager.shared.resizeImageToFit(image, maxDimension: 800) ?? image
                        
                        await MainActor.run {
                            profileImage = resizedImage
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Save Profile Function
    /// Saves the updated profile to Firebase
    /// 
    /// Process:
    /// 1. Validate input fields
    /// 2. Server-side content validation via Cloud Function
    /// 3. Check username uniqueness (if changed)
    /// 4. Upload new photo to Storage (if selected) and delete old one
    /// 5. Update profile in Firestore
    /// 6. Fetch updated profile to confirm changes
    /// 7. Call onSave callback and dismiss sheet
    private func saveProfile() {
        // Step 1: Check network connection
        guard networkMonitor.isConnected else {
            errorTitle = "No Connection"
            errorMessage = "Please connect to the internet and try again."
            showError = true
            return
        }
        
        // Step 2: Check authentication
        guard let userId = authManager.userId else {
            errorTitle = "Sign In Required"
            errorMessage = "Please sign in to save your profile."
            showError = true
            return
        }
        
        // Step 3: Validate display name (basic check)
        let trimmedName = displayName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorTitle = "Display Name Required"
            errorMessage = "Please enter a display name."
            showError = true
            return
        }
        
        // Step 4: Validate username (basic check)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty else {
            usernameError = "Username cannot be empty"
            return
        }
        
        guard trimmedUsername.count >= 3 else {
            usernameError = "Username must be at least 3 characters"
            return
        }
        
        // Step 5: Check 14-day cooldown (only if username is being changed)
        if trimmedUsername != currentProfile.username {
            if let lastChanged = currentProfile.usernameLastChanged {
                let daysSinceChange = Calendar.current.dateComponents([.day], from: lastChanged, to: Date()).day ?? 0
                if daysSinceChange < 14 {
                    let daysRemaining = 14 - daysSinceChange
                    usernameError = "You can change your username again in \(daysRemaining) day\(daysRemaining == 1 ? "" : "s")"
                    return
                }
            }
        }
        
        isLoading = true
        
        Task {
            do {
                // Step 6: Server-side content validation via Cloud Function
                // This checks for profanity, reserved words, and format validation
                print("🔒 [ProfileEditView] Validating content via Cloud Function...")
                let validationResult = try await moderationService.validateContent(
                    username: trimmedUsername != currentProfile.username ? trimmedUsername : nil,
                    displayName: trimmedName
                )
                
                if !validationResult.isValid {
                    await MainActor.run {
                        isLoading = false
                        // Set specific field errors
                        if let usernameErr = validationResult.usernameError {
                            usernameError = usernameErr
                        }
                        if let displayNameErr = validationResult.displayNameError {
                            displayNameError = displayNameErr
                        }
                    }
                    print("❌ [ProfileEditView] Validation failed")
                    return
                }
                
                print("✅ [ProfileEditView] Content validation passed")
                
                // Step 7: Check username availability (if changed)
                // This checks uniqueness AND validates against server-side rules
                if trimmedUsername != currentProfile.username {
                    print("🔒 [ProfileEditView] Checking username availability via Cloud Function...")
                    let availabilityResult = try await moderationService.checkUsernameAvailability(
                        username: trimmedUsername,
                        excludeUserId: userId
                    )
                    
                    if !availabilityResult.isAvailable {
                        await MainActor.run {
                            isLoading = false
                            usernameError = availabilityResult.reason ?? "Username is not available"
                        }
                        print("❌ [ProfileEditView] Username not available: \(availabilityResult.reason ?? "unknown")")
                        return
                    }
                    
                    print("✅ [ProfileEditView] Username available")
                }
                
                var avatarUrl = currentProfile.avatarUrl
                
                // Step 8: Upload new profile photo (if user selected one)
                // This also automatically deletes the old photo to save storage
                if let image = profileImage {
                    avatarUrl = try await FirebaseService.shared.uploadProfilePhoto(
                        userId: userId,
                        image: image,
                        oldAvatarUrl: currentProfile.avatarUrl
                    )
                    
                    // Clear old cached profile pictures for this user
                    ImageManager.shared.clearCachedProfilePictures(
                        userId: userId,
                        oldAvatarUrl: currentProfile.avatarUrl
                    )
                    
                    // Pre-cache the new profile picture to avoid network download on next load
                    if let avatarUrl = avatarUrl {
                        ImageManager.shared.precacheProfilePicture(
                            image: image,
                            url: avatarUrl,
                            userId: userId
                        )
                    }
                }
                
                // Step 9: Update profile document in Firestore
                try await FirebaseService.shared.updateUserProfile(
                    userId: userId,
                    displayName: trimmedName,
                    bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                    avatarUrl: avatarUrl,
                    username: trimmedUsername != currentProfile.username ? trimmedUsername : nil
                )
                
                // Step 10: Fetch the updated profile to ensure we have latest data
                let updatedProfile = try await FirebaseService.shared.fetchUserProfile(userId: userId)
                
                // Step 11: Success! Update UI and dismiss
                await MainActor.run {
                    isLoading = false
                    onSave(updatedProfile) // Notify parent view of changes
                    dismiss()
                }
                
                print("✅ Profile updated successfully")
                
            } catch {
                // Handle any errors during the save process
                await MainActor.run {
                    isLoading = false
                    errorTitle = "Save Failed"
                    errorMessage = "Couldn't save profile. Please try again."
                    showError = true
                }
                print("❌ Failed to update profile: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ProfileEditView(
        profile: UserProfile(
            id: "preview",
            username: "johndoe",
            displayName: "John Doe",
            bio: "I love traveling and exploring new places"
        ),
        onSave: { _ in }
    )
    .environmentObject(AuthManager())
}

