import SwiftUI

/// Shared menu content used across FeedView and StampsView
/// Provides common app settings, feedback, and business options
struct AppMenuContent {
    /// Common menu items shared between FeedView and StampsView
    @ViewBuilder
    static func commonItems(
        showAboutStampbook: Binding<Bool>,
        showForLocalBusiness: Binding<Bool>,
        showProblemReport: Binding<Bool>,
        showFeedback: Binding<Bool>
    ) -> some View {
        Button(action: {
            showAboutStampbook.wrappedValue = true
        }) {
            Label("About Stampbook", systemImage: "info.circle")
        }
        
        Divider()
        
        Button(action: {
            showForLocalBusiness.wrappedValue = true
        }) {
            Label("For local business", systemImage: "storefront")
        }
        
        Divider()
        
        Button(action: {
            showProblemReport.wrappedValue = true
        }) {
            Label("Report a problem", systemImage: "exclamationmark.bubble")
        }
        
        Button(action: {
            showFeedback.wrappedValue = true
        }) {
            Label("Send feedback", systemImage: "envelope")
        }
    }
}

