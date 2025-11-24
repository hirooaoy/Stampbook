import WidgetKit
import SwiftUI

/// Main widget entry point
struct StampbookWidget: Widget {
    let kind: String = "StampbookWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StampProvider()) { entry in
            if #available(iOS 17.0, *) {
                StampWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StampWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("My Stamps")
        .description("See your collected stamps rotate throughout the day")
        .supportedFamilies([.systemSmall]) // Small widget only
    }
}

/// Widget preview for Xcode canvas
#Preview(as: .systemSmall) {
    StampbookWidget()
} timeline: {
    StampEntry(
        date: Date(),
        stamp: WidgetStamp(
            id: "us-ca-san-francisco-golden-gate-bridge",
            name: "Golden Gate Bridge",
            collectedDate: Date(),
            imageFileName: "preview.png"
        )
    )
    StampEntry(date: Date(), stamp: nil)
}
