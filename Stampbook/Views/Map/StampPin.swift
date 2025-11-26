import SwiftUI

struct StampPin: View {
    let stamp: Stamp
    let isWithinRange: Bool
    let isCollected: Bool
    let isBookmarked: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Stamp icon
            ZStack {
                Circle()
                    .fill(pinColor)
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                Image(systemName: pinIcon)
                    .font(.system(size: 30))
                    .foregroundColor(pinIconColor)
            }
            
            // Pointer triangle
            Triangle()
                .fill(pinColor)
                .frame(width: 12, height: 8)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
    
    // Pin color based on state (priority order: collected > bookmarked > in-range > locked)
    private var pinColor: Color {
        if isCollected {
            return .green
        } else if isBookmarked {
            return .yellow
        } else if isWithinRange {
            return .blue
        } else {
            return .white
        }
    }
    
    // Pin icon based on state
    private var pinIcon: String {
        if isCollected {
            return "checkmark.seal.fill"
        } else if isBookmarked {
            return "bookmark.fill"
        } else if isWithinRange {
            return "lock.open.fill"
        } else {
            return "lock.fill"
        }
    }
    
    // Icon color (white for filled pins, gray for locked)
    private var pinIconColor: Color {
        if isCollected || isBookmarked || isWithinRange {
            return .white
        } else {
            return .gray
        }
    }
}

// Triangle shape for the pin pointer
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
