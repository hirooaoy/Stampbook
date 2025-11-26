import SwiftUI

struct ClusterPin: View {
    let count: Int
    let isCollected: Bool
    let isBookmarked: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Cluster circle with count
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                // Text color based on cluster type
                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(textColor)
            }
            
            // Pointer triangle (matching StampPin)
            Triangle()
                .fill(circleColor)
                .frame(width: 12, height: 8)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
    
    private var circleColor: Color {
        if isCollected {
            return .green
        } else if isBookmarked {
            return .yellow
        } else {
            return .white
        }
    }
    
    private var textColor: Color {
        if isCollected {
            return .white  // White text on green
        } else if isBookmarked {
            return .white  // White text on yellow
        } else {
            return .gray  // Gray text on white
        }
    }
}

