import SwiftUI

/// Reusable sign-in bottom sheet with invite code gate
/// Shows when user needs to authenticate to access a feature
struct SignInSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var showInviteCodeSheet = false
    
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
        VStack(spacing: 20) {
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
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 16)
            
            // Get Started button
            Button(action: {
                showInviteCodeSheet = true
            }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
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
        .sheet(isPresented: $showInviteCodeSheet) {
            InviteCodeSheet(isAuthenticated: $authManager.isSignedIn)
                .environmentObject(authManager)
        }
        .onChange(of: authManager.isSignedIn) { oldValue, newValue in
            // Dismiss this sheet when user successfully signs in
            if newValue == true {
                dismiss()
            }
        }
    }
}

#Preview {
    Text("Map View")
        .sheet(isPresented: .constant(true)) {
            SignInSheet()
                .environmentObject(AuthManager())
        }
}

