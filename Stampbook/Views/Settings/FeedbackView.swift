import SwiftUI

/// Simple feedback view - Notes-like experience for sending feedback
struct SimpleFeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var feedbackText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $feedbackText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if feedbackText.isEmpty {
                    Text(authManager.isSignedIn ? "Share your thoughts, ideas, or suggestions..." : "Share your thoughts, ideas, or suggestions...\n(Submitted anonymously)")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendFeedback) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your feedback!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendFeedback() {
        let trimmedText = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Feedback",
                    message: trimmedText
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send feedback. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

/// Simple problem report view - Notes-like experience for reporting problems
struct SimpleProblemReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var problemText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $problemText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if problemText.isEmpty {
                    Text(authManager.isSignedIn ? "Describe the problem you're experiencing..." : "Describe the problem you're experiencing...\n(Submitted anonymously)")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendProblemReport) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(problemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your report!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendProblemReport() {
        let trimmedText = problemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Problem Report",
                    message: trimmedText
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send report. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

/// Simple user report view - For reporting users (spam, inappropriate content, etc.)
struct SimpleUserReportView: View {
    let reportedUserId: String
    let reportedUsername: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var reportText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reportText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if reportText.isEmpty {
                    Text("Tell us what's wrong (this is a spam account, inappropriate content, etc.).")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Report user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendUserReport) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your report!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendUserReport() {
        let trimmedText = reportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase with reported user info (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                let reportMessage = """
                Reported User: @\(reportedUsername) (ID: \(reportedUserId))
                
                Report:
                \(trimmedText)
                """
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "User Report",
                    message: reportMessage
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send report. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

/// Suggest edit view - For suggesting edits to stamp information
struct SuggestEditView: View {
    let stampId: String
    let stampName: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var editText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if editText.isEmpty {
                    Text(authManager.isSignedIn ? "Suggest improvements to stamp details (address, description, things to do, etc.)..." : "Suggest improvements to stamp details (address, description, things to do, etc.)...\n(Submitted anonymously)")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Suggest an edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendSuggestEdit) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your suggestion!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendSuggestEdit() {
        let trimmedText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase with stamp info (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                let editMessage = """
                Stamp: \(stampName) (ID: \(stampId))
                
                Suggested Edit:
                \(trimmedText)
                """
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Stamp Edit Suggestion",
                    message: editMessage
                )
                
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

/// Suggest edit view for collections - For suggesting edits to collection information
struct SuggestCollectionEditView: View {
    let collectionId: String
    let collectionName: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var editText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if editText.isEmpty {
                    Text(authManager.isSignedIn ? "Suggest improvements to collection details (name, description, stamps to add/remove, etc.)..." : "Suggest improvements to collection details (name, description, stamps to add/remove, etc.)...\n(Submitted anonymously)")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Suggest an edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendSuggestEdit) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Success!", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for your suggestion!")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendSuggestEdit() {
        let trimmedText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                // Submit to Firebase with collection info (works for both signed-in and anonymous users)
                let userId = authManager.userId ?? "anonymous"
                let editMessage = """
                Collection: \(collectionName) (ID: \(collectionId))
                
                Suggested Edit:
                \(trimmedText)
                """
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Collection Edit Suggestion",
                    message: editMessage
                )
                
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

/// Account deletion request view - For users who want to delete their account
struct AccountDeletionRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var reasonText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $reasonText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if reasonText.isEmpty {
                    Text("Sorry to see you go. Please tell us why.\n\nStampbook will manually delete your profile within 3 business days.")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendDeletionRequest) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(reasonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .alert("Request received", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("We'll delete your account within 3 business days.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendDeletionRequest() {
        let trimmedText = reasonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                guard let userId = authManager.userId else {
                    await MainActor.run {
                        isSending = false
                        errorMessage = "Not signed in"
                        showErrorAlert = true
                    }
                    return
                }
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Account Deletion Request",
                    message: trimmedText
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send request. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

/// Data download request view - For users who want to download their profile data
struct DataDownloadRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var requestText = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $requestText)
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
                
                // Placeholder
                if requestText.isEmpty {
                    Text("We'll prepare your profile data and email it to you within 3 business days.\n\nWe'll use the email associated with your Apple ID.\n\n(Optional: Let us know if you have any specific requests)")
                        .font(.body)
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Download my data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendDownloadRequest) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSending)
                }
            }
            .alert("Request received", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("We'll email your data within 3 business days.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func sendDownloadRequest() {
        isSending = true
        
        Task {
            do {
                guard let userId = authManager.userId else {
                    await MainActor.run {
                        isSending = false
                        errorMessage = "Not signed in"
                        showErrorAlert = true
                    }
                    return
                }
                
                let message = requestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User requested data download" : requestText
                
                try await FirebaseService.shared.submitFeedback(
                    userId: userId,
                    type: "Data Download Request",
                    message: message
                )
                
                await MainActor.run {
                    isSending = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send request. Please try again."
                    showErrorAlert = true
                }
            }
        }
    }
}

#Preview("Feedback") {
    SimpleFeedbackView()
        .environmentObject(AuthManager())
}

#Preview("Problem Report") {
    SimpleProblemReportView()
        .environmentObject(AuthManager())
}

#Preview("User Report") {
    SimpleUserReportView(reportedUserId: "testUserId", reportedUsername: "testuser")
        .environmentObject(AuthManager())
}

#Preview("Suggest Edit") {
    SuggestEditView(stampId: "test_stamp_id", stampName: "Mt. Fuji")
        .environmentObject(AuthManager())
}

#Preview("Account Deletion") {
    AccountDeletionRequestView()
        .environmentObject(AuthManager())
}

#Preview("Data Download") {
    DataDownloadRequestView()
        .environmentObject(AuthManager())
}

