import WidgetKit
import SwiftUI

/// Timeline entry for widget
struct StampEntry: TimelineEntry {
    let date: Date
    let stamp: WidgetStamp?
}

/// Provides timeline for widget updates
struct StampProvider: TimelineProvider {
    
    // MARK: - Timeline Provider Protocol
    
    /// Placeholder shown while widget loads for the first time
    func placeholder(in context: Context) -> StampEntry {
        StampEntry(date: Date(), stamp: nil)
    }

    /// Snapshot for widget gallery (when user adds widget)
    func getSnapshot(in context: Context, completion: @escaping (StampEntry) -> ()) {
        // Show a random stamp or placeholder
        let stamp = WidgetDataManager.shared.getRandomStamp()
        let entry = StampEntry(date: Date(), stamp: stamp)
        completion(entry)
    }

    /// Generate timeline for widget updates
    /// Refreshes every 6 hours with a new random stamp
    func getTimeline(in context: Context, completion: @escaping (Timeline<StampEntry>) -> ()) {
        let currentDate = Date()
        
        // Get random stamp from collected stamps
        let stamp = WidgetDataManager.shared.getRandomStamp()
        let entry = StampEntry(date: currentDate, stamp: stamp)
        
        // Schedule next refresh in 6 hours
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 6, to: currentDate)!
        
        // Create timeline with single entry
        // iOS will call getTimeline again after the refresh date
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        
        completion(timeline)
    }
}


