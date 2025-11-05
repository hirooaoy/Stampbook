import SwiftUI

/// Reusable connection status banner
/// Used in MapView and FeedView to show offline/reconnecting states
struct ConnectionBanner: View {
    let state: BannerState
    let context: BannerContext
    
    enum BannerState {
        case hidden
        case offline
        case reconnecting
    }
    
    enum BannerContext {
        case map        // "You can still collect stamps"
        case feed       // "Showing cached posts"
    }
    
    var body: some View {
        if state != .hidden {
            HStack(alignment: .center, spacing: 10) {
                // Icon on left (vertically centered)
                bannerIcon
                    .font(.title3)
                    .foregroundColor(bannerIconColor)
                
                // Content on right (left-aligned)
                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(state == .offline ? "Offline" : "Reconnecting...")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Subtitle (only shows for map context when offline)
                    if state == .offline && context == .map {
                        Text(subtitleText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .background(bannerBackgroundColor)
            .clipShape(Capsule())
            .shadow(
                color: .black.opacity(0.15),
                radius: 8,
                x: 0,
                y: 4
            )
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    // MARK: - Helpers
    
    private var bannerIcon: Image {
        switch state {
        case .offline:
            return Image(systemName: "wifi.slash")
        case .reconnecting:
            return Image(systemName: "wifi")
        case .hidden:
            return Image(systemName: "wifi")
        }
    }
    
    private var bannerIconColor: Color {
        switch state {
        case .offline:
            return .orange
        case .reconnecting:
            return .green
        case .hidden:
            return .primary
        }
    }
    
    private var subtitleText: String {
        switch context {
        case .map:
            return "You can still collect stamps"
        case .feed:
            return "Showing cached posts"
        }
    }
    
    private var bannerBackgroundColor: Color {
        switch state {
        case .offline:
            return Color.yellow.opacity(0.2)
        case .reconnecting:
            return Color.green.opacity(0.15)
        case .hidden:
            return Color.clear
        }
    }
}

