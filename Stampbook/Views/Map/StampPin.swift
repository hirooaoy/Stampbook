import SwiftUI

struct StampPin: View {
    let stamp: Stamp
    let isWithinRange: Bool
    let isCollected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Stamp icon
            ZStack {
                Circle()
                    .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                if isCollected {
                    // Green background + checkmark icon when collected
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                } else if isWithinRange {
                    // Blue background + unlock icon when in range
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                } else {
                    // White background + lock icon when too far
                    Image(systemName: "lock.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                }
            }
            
            // Pointer triangle
            Triangle()
                .fill(isCollected ? Color.green : isWithinRange ? Color.blue : Color.white)
                .frame(width: 12, height: 8)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
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
