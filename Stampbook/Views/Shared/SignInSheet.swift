import SwiftUI
import AuthenticationServices

/// Reusable sign-in bottom sheet
/// Shows when user needs to authenticate to access a feature
struct SignInSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    let title: String
    let message: String
    
    init(
        title: String = "Sign In Required",
        message: String = "Sign in to see your location and start your stamp collection"
    ) {
        self.title = title
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 20) {  // Reduced from 24 to 20
            // Drag indicator (automatic with .presentationDragIndicator)
            
            Spacer()
                .frame(height: 8)
            
            // App logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .cornerRadius(16)
            
            // Content
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)  // Allow unlimited lines
                    .fixedSize(horizontal: false, vertical: true)  // Allow vertical expansion
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 16)  // 16pt spacing to Sign In button
            
            // Native Sign In with Apple button
            Button(action: {
                authManager.signInWithApple()
                dismiss()
            }) {
                SignInWithAppleButton(.signIn) { _ in }
                    onCompletion: { _ in }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .cornerRadius(12)
                    .allowsHitTesting(false) // Disable built-in handler, use our button action
            }
            .padding(.horizontal, 32)
            
            // Not Now button
            Button(action: {
                dismiss()
            }) {
                Text("Not Now")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 12)
        }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Text("Map View")
        .sheet(isPresented: .constant(true)) {
            SignInSheet()
                .environmentObject(AuthManager())
        }
}

