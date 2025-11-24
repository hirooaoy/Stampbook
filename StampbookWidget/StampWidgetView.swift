import SwiftUI
import WidgetKit

/// Main widget view - shows collected stamp (with future space for penguin overlay)
struct StampWidgetView: View {
    let entry: StampEntry
    
    @Environment(\.widgetFamily) var widgetFamily
    
    var body: some View {
        ZStack {
            if let stamp = entry.stamp {
                // Has collected stamps - show stamp with deep link
                Link(destination: deepLinkURL(for: stamp.id)) {
                    stampCard(stamp: stamp)
                }
            } else {
                // No stamps collected yet - show placeholder
                placeholderView
            }
        }
    }
    
    // MARK: - Stamp Card View
    
    @ViewBuilder
    private func stampCard(stamp: WidgetStamp) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background: Stamp Image (full stamp visible, .fit not .fill)
            if let imageURL = WidgetDataManager.shared.loadImageFromSharedContainer(fileName: stamp.imageFileName),
               let uiImage = UIImage(contentsOfFile: imageURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit) // Shows full stamp without cropping
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Fallback: Show app logo if stamp image not available
                if let logoImage = UIImage(named: "AppLogo") {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Final fallback
                    Color.blue.opacity(0.3)
                        .overlay(
                            Image(systemName: "map.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        )
                }
            }
            
            // FUTURE: Penguin overlay will go here (bottom-right corner)
        }
    }
    
    // MARK: - Placeholder View
    
    private var placeholderView: some View {
        // Just text, no background
        Text("Collect a stamp\nto display")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Deep Linking
    
    /// Generate deep link URL for stamp detail view
    private func deepLinkURL(for stampId: String) -> URL {
        URL(string: "stampbook://stamp/\(stampId)")!
    }
}

// MARK: - Previews

struct StampWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview with stamp
            StampWidgetView(entry: StampEntry(
                date: Date(),
                stamp: WidgetStamp(
                    id: "us-ca-san-francisco-golden-gate-bridge",
                    name: "Golden Gate Bridge",
                    collectedDate: Date(),
                    imageFileName: "preview.png"
                )
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("With Stamp")
            
            // Preview with no stamps
            StampWidgetView(entry: StampEntry(
                date: Date(),
                stamp: nil
            ))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .previewDisplayName("No Stamps")
        }
    }
}


