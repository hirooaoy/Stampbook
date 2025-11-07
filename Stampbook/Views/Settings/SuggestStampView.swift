import SwiftUI

/// Simple view for suggesting a single new stamp
/// Uses native Form style matching ProfileEditView
struct SuggestStampView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    
    @State private var stampName = ""
    @State private var fullAddress = ""
    @State private var additionalNotes = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    /// Check if all fields are filled
    private var isValid: Bool {
        !stampName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Logo at top
                Section {
                    HStack {
                        Spacer()
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .cornerRadius(16)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                StampSuggestionFormField(
                    stampNumber: nil,
                    name: $stampName,
                    address: $fullAddress,
                    notes: $additionalNotes
                )
            }
            .listSectionSpacing(16)
            .navigationTitle("Suggest a stamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendSuggestion) {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValid || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you! We'll review your suggestion.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendSuggestion() {
        guard let userId = authManager.userId else {
            errorMessage = "Please sign in to suggest stamps"
            showErrorAlert = true
            return
        }
        
        isSending = true
        
        Task {
            do {
                let profile = profileManager.currentUserProfile ?? UserProfile(
                    id: userId,
                    username: "user",
                    displayName: "User",
                    bio: "",
                    avatarUrl: nil,
                    totalStamps: 0,
                    createdAt: Date(),
                    lastActiveAt: Date()
                )
                
                let suggestion = StampSuggestion(
                    userId: userId,
                    username: profile.username,
                    userDisplayName: profile.displayName,
                    type: .singleStamp,
                    stampName: stampName.trimmingCharacters(in: .whitespacesAndNewlines),
                    fullAddress: fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),
                    additionalNotes: additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                    collectionName: nil,
                    stamps: nil,
                    createdAt: Date()
                )
                
                try await FirebaseService.shared.submitStampSuggestion(suggestion)
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send suggestion. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

#Preview {
    SuggestStampView()
        .environmentObject(AuthManager())
        .environmentObject(ProfileManager())
}
