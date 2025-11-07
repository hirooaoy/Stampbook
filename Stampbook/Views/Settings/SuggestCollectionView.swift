import SwiftUI

/// View for suggesting a new collection with multiple stamps
/// Uses native Form style matching ProfileEditView
struct SuggestCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var profileManager: ProfileManager
    
    @State private var collectionName = ""
    @State private var stamps: [EditableStamp] = [
        EditableStamp(), // Stamp 1
        EditableStamp(), // Stamp 2
        EditableStamp()  // Stamp 3 (minimum)
    ]
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    struct EditableStamp: Identifiable {
        let id = UUID()
        var name = ""
        var address = ""
        var notes = ""
        
        var isComplete: Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private var isValid: Bool {
        let collectionNameValid = !collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let completeStamps = stamps.filter { $0.isComplete }
        return collectionNameValid && completeStamps.count >= 3
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
                
                Section {
                    TextField("San Francisco Landmarks", text: $collectionName)
                } header: {
                    Text("Collection Name")
                } footer: {
                    Text("You need a minimum of 3 stamps for a collection")
                }
                
                ForEach(stamps.indices, id: \.self) { index in
                    // Divider between stamps
                    Section {
                        EmptyView()
                    } header: {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                            .padding(.vertical, 8)
                    }
                    
                    // Stamp fields (same detailed layout as single stamp)
                    Section {
                        TextField("Golden Gate View Point", text: binding(for: index, keyPath: \.name))
                    } header: {
                        Text("Stamp Name")
                    }
                    
                    Section {
                        TextField("Old Conzelman Rd, Mill Valley, CA 94941", text: binding(for: index, keyPath: \.address))
                    } header: {
                        Text("Address")
                    } footer: {
                        Text("Copy full address from Google or Apple Maps")
                    }
                    
                    Section {
                        TextField("Stamp should include the bridge", text: binding(for: index, keyPath: \.notes), axis: .vertical)
                            .lineLimit(5...10)
                            .lineSpacing(8)
                    } header: {
                        Text("Additional Notes")
                    } footer: {
                        Text("Tell us what we should include for the stamp image and things to do.")
                    }
                    
                    // Remove button as separate section
                    if stamps.count > 3 {
                        Section {
                            Button(role: .destructive, action: {
                                removeStamp(at: index)
                            }) {
                                Label("Remove Stamp", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section {
                    Button(action: addStamp) {
                        Label("Add Another Stamp", systemImage: "plus.circle.fill")
                    }
                }
            }
            .listSectionSpacing(16)
            .navigationTitle("Suggest a collection")
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
                Text("Thank you! We'll review your collection.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // Helper for bindings
    private func binding(for index: Int, keyPath: WritableKeyPath<EditableStamp, String>) -> Binding<String> {
        Binding(
            get: { stamps[index][keyPath: keyPath] },
            set: { stamps[index][keyPath: keyPath] = $0 }
        )
    }
    
    private func addStamp() {
        withAnimation {
            stamps.append(EditableStamp())
        }
    }
    
    private func removeStamp(at index: Int) {
        stamps.remove(at: index)
    }
    
    private func sendSuggestion() {
        guard let userId = authManager.userId else {
            errorMessage = "Please sign in to suggest collections"
            showErrorAlert = true
            return
        }
        
        let completeStamps = stamps.filter { $0.isComplete }
        guard completeStamps.count >= 3 else {
            errorMessage = "Please complete at least 3 stamps"
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
                
                // Convert all complete stamps to StampData
                let stampData = completeStamps.map { stamp in
                    StampData(
                        name: stamp.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        fullAddress: stamp.address.trimmingCharacters(in: .whitespacesAndNewlines),
                        additionalNotes: stamp.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                
                let suggestion = StampSuggestion(
                    userId: userId,
                    username: profile.username,
                    userDisplayName: profile.displayName,
                    type: .collection,
                    stampName: nil,
                    fullAddress: nil,
                    additionalNotes: nil,
                    collectionName: collectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                    stamps: stampData,
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
    SuggestCollectionView()
        .environmentObject(AuthManager())
        .environmentObject(ProfileManager())
}
