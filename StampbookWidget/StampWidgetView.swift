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
                    .clipped()
            } else {
                // Fallback: Beautiful branded placeholder when image not yet cached
                ZStack {
                    // Gradient background (subtle stamp-like colors)
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.94, blue: 0.92),
                            Color(red: 0.98, green: 0.97, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    VStack(spacing: 8) {
                        // Stamp icon
                        Image(systemName: "map.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.4, green: 0.45, blue: 0.5), Color(red: 0.5, green: 0.55, blue: 0.6)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        // Stamp name (shorter for better readability)
                        Text(stamp.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(red: 0.3, green: 0.35, blue: 0.4))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 8)
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


