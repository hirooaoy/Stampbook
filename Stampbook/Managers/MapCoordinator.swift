import SwiftUI
import MapKit
import Combine

/// Coordinates map navigation across different views
/// Used to center the map on a specific stamp from anywhere in the app
class MapCoordinator: ObservableObject {
    @Published var stampToCenter: Stamp?
    @Published var shouldSwitchToMapTab = false
    
    /// Request to center the map on a specific stamp
    /// This will trigger the map to center and optionally switch tabs
    func centerOnStamp(_ stamp: Stamp, switchTab: Bool = true) {
        #if DEBUG
        print("🗺️ [MapCoordinator] centerOnStamp called: \(stamp.name), switchTab: \(switchTab)")
        #endif
        self.stampToCenter = stamp
        self.shouldSwitchToMapTab = switchTab
    }
    
    /// Clear the centering request after it's been handled
    func clearRequest() {
        #if DEBUG
        print("🗺️ [MapCoordinator] clearRequest called")
        #endif
        self.stampToCenter = nil
        self.shouldSwitchToMapTab = false
    }
}

