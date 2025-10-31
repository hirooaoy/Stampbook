import Foundation

/// Date formatting extensions to consolidate duplicate formatDate functions
extension Date {
    /// Format date as "MMM d, yyyy" (e.g. "Oct 31, 2025")
    /// Used in feed posts, stamp details, and other date displays
    func formattedMedium() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: self)
    }
    
    /// Format date with custom format string
    func formatted(style: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = style
        return formatter.string(from: self)
    }
}

