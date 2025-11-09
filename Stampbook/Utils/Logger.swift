import Foundation

/// Centralized logging system for the app
/// Provides consistent log formatting and makes it easy to add external logging services later
enum Logger {
    
    // MARK: - Log Levels
    
    /// Debug logs - only shown in DEBUG builds
    /// Use for detailed debugging information during development
    nonisolated static func debug(_ message: String, file: String = #file, line: Int = #line) {
        #if DEBUG
        let fileName = extractFileName(from: file)
        print("🔍 [\(fileName):\(line)] \(message)")
        #endif
    }
    
    /// Info logs - general informational messages
    /// Use for important state changes and flow tracking
    nonisolated static func info(_ message: String, category: String? = nil) {
        let prefix = category != nil ? "ℹ️ [\(category!)]" : "ℹ️"
        print("\(prefix) \(message)")
    }
    
    /// Warning logs - something unexpected but not critical
    /// Use for recoverable errors or deprecated code paths
    nonisolated static func warning(_ message: String, category: String? = nil) {
        let prefix = category != nil ? "⚠️ [\(category!)]" : "⚠️"
        print("\(prefix) \(message)")
    }
    
    /// Error logs - something went wrong
    /// Use for failures that affect functionality
    nonisolated static func error(_ message: String, error: Error? = nil, category: String? = nil) {
        let prefix = category != nil ? "❌ [\(category!)]" : "❌"
        print("\(prefix) \(message)")
        if let error = error {
            print("   → \(error.localizedDescription)")
        }
    }
    
    /// Success logs - important successful operations
    /// Use sparingly for key milestones
    nonisolated static func success(_ message: String, category: String? = nil) {
        let prefix = category != nil ? "✅ [\(category!)]" : "✅"
        print("\(prefix) \(message)")
    }
    
    // MARK: - Performance Tracking
    
    /// Log operation timing for performance monitoring
    nonisolated static func timing(_ operation: String, duration: TimeInterval, category: String? = nil) {
        let prefix = category != nil ? "⏱️ [\(category!)]" : "⏱️"
        print("\(prefix) \(operation): \(String(format: "%.3f", duration))s")
    }
    
    // MARK: - Private Helpers
    
    private nonisolated static func extractFileName(from path: String) -> String {
        let components = path.components(separatedBy: "/")
        return components.last?.replacingOccurrences(of: ".swift", with: "") ?? path
    }
}
