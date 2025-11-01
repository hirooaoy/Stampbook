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
            .navigationTitle("Send Feedback")
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
                    errorMessage = error.localizedDescription
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
            .navigationTitle("Report a Problem")
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
                    errorMessage = error.localizedDescription
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

