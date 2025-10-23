import SwiftUI

struct ClusterPin: View {
    let count: Int
    let isCollected: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Cluster circle with count
            ZStack {
                Circle()
                    .fill(isCollected ? Color.green : Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                
                // White text for collected (green bg), gray text for locked (white bg)
                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isCollected ? .white : .gray)
            }
            
            // Pointer triangle (matching StampPin)
            Triangle()
                .fill(isCollected ? Color.green : Color.white)
                .frame(width: 12, height: 8)
                .offset(y: -1)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
    }
}

