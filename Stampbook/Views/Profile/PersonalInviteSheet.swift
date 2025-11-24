import SwiftUI

/// Sheet that displays user's personal invite code and sharing options
struct PersonalInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var inviteManager = InviteManager()
    
    let userId: String
    let username: String
    
    // State
    @State private var code: String = ""
    @State private var usedCount: Int = 0
    @State private var maxUses: Int = 5
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    @State private var showCopied: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                loadingView
            } else if errorMessage != nil {
                errorView
            } else {
                contentView
            }
        }
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .task {
            await loadCode()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading your invite code...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                
                Text("Invite your friends")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Tell your friends to download the app and use your personal code to join (\(remainingText))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            // Code display - tap to copy
            Button(action: {
                copyCode()
            }) {
                ZStack {
                    // Code (hidden when copied)
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.primary)
                        .opacity(showCopied ? 0 : 1)
                    
                    // "COPIED" text (shown when copied)
                    if showCopied {
                        Text("COPIED")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(showCopied ? Color.green.opacity(0.1) : Color.clear)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray3), lineWidth: showCopied ? 0 : 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 32)
            
            // Share button
            Button(action: {
                shareCode()
            }) {
                Text("Share")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(remainingCount > 0 ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .disabled(remainingCount == 0)
        }
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Couldn't load your code")
                .font(.headline)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button("Try Again") {
                Task {
                    await loadCode()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var remainingCount: Int {
        maxUses - usedCount
    }
    
    private var remainingText: String {
        if remainingCount == 0 {
            return "0/5 left"
        } else {
            return "\(remainingCount)/5 left"
        }
    }
    
    // MARK: - Actions
    
    private func loadCode() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get user's personal code (always exists because it's generated at signup)
            if let existingCode = await inviteManager.getUserPersonalCode(userId: userId) {
                code = existingCode
                
                // Fetch usage stats
                let stats = try await inviteManager.getCodeUsageStats(code: existingCode)
                usedCount = stats.used
                maxUses = stats.max
            } else {
                // Fallback: generate code if somehow missing (shouldn't happen for new users)
                let newCode = try await inviteManager.generatePersonalCode(userId: userId, username: username)
                code = newCode
                usedCount = 0
                maxUses = 5
            }
            
            isLoading = false
        } catch {
            Logger.error("Failed to load personal code", error: error, category: "PersonalInviteSheet")
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    private func copyCode() {
        UIPasteboard.general.string = code
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // Show feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopied = true
        }
        
        // Hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopied = false
            }
        }
        
        Logger.info("Code copied to clipboard", category: "PersonalInviteSheet")
    }
    
    private func shareCode() {
        let message = """
        Join me on Stampbook! 🗺️
        
        Use my invite code: \(code)
        
        https://testflight.apple.com/join/rdfyeZnH
        """
        
        let activityController = UIActivityViewController(
            activityItems: [message],
            applicationActivities: nil
        )
        
        // Present share sheet from the currently presented view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            // Find the topmost presented view controller
            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            
            // iPad support
            if let popover = activityController.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            topController?.present(activityController, animated: true)
        }
        
        Logger.info("Opened share sheet", category: "PersonalInviteSheet")
    }
}

// MARK: - Preview

#Preview {
    PersonalInviteSheet(userId: "test123", username: "hiroo")
}

