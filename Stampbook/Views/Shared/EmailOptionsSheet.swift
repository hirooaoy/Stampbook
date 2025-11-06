import SwiftUI

/// Reusable bottom sheet for email contact options
/// Shows "Open Mail App" and "Copy Email" options with a Cancel button
struct EmailOptionsSheet: View {
    let email: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                // Open email button
                Button(action: {
                    onDismiss()
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Open Mail App")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                
                // Copy email button
                Button(action: {
                    UIPasteboard.general.string = email
                    onDismiss()
                }) {
                    Text("Copy Email")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.gray.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                
                // Cancel button (no background)
                Button(action: {
                    onDismiss()
                }) {
                    Text("Cancel")
                        .font(.body)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 32)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Text("Tap to show sheet")
        .sheet(isPresented: .constant(true)) {
            EmailOptionsSheet(email: "example@email.com") {}
        }
}

