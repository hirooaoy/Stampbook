import SwiftUI

/// SwiftUI View extensions for conditional modifiers
extension View {
    /// Conditionally applies a modifier to a view
    /// - Parameters:
    ///   - condition: Boolean condition to check
    ///   - transform: Closure that applies the modifier if condition is true
    /// - Returns: Modified or unmodified view based on condition
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Returns true if running on iPad
    var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    /// Adaptive horizontal padding - larger on iPad, standard on iPhone
    /// - Parameter iPhone: Padding for iPhone (default 24)
    /// - Returns: View with adaptive padding
    func adaptiveHorizontalPadding(_ iPhone: CGFloat = 24) -> some View {
        self.padding(.horizontal, isIPad ? iPhone * 2 : iPhone)
    }
    
    /// Adds appropriate background for sheet content with NavigationStack
    /// iOS 26+ has native semi-transparent sheet backgrounds (looks great!)
    /// iOS 18.6-25 have broken/missing backgrounds, so we add explicit background
    @ViewBuilder
    func sheetContentBackground() -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ handles sheet backgrounds automatically with nice semi-transparency
            self
        } else {
            // iOS 18.6-25: Fix missing background bug
            self.background(Color(uiColor: .systemBackground))
        }
    }
}

