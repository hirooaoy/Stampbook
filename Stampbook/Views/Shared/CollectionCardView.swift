import SwiftUI

/// A card view that displays collection information with a progress indicator
/// Shows collection name, completion status, and visual progress bar
struct CollectionCardView: View {
    let name: String
    let collectedCount: Int
    let totalCount: Int
    let completionPercentage: Double
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Base gray background
            Color(.secondarySystemBackground)
            
            // Progress fill (matches segmented control selected state)
            GeometryReader { geometry in
                Rectangle()
                    .fill(colorScheme == .dark ? Color(.systemGray4) : Color(.systemGray5))
                    .frame(width: geometry.size.width * completionPercentage)
            }
            
            // Content on top
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("\(collectedCount) out of \(totalCount) stamp\(totalCount == 1 ? "" : "s") collected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 32)
            .padding(.horizontal, 20)
        }
        .cornerRadius(12)
    }
}

