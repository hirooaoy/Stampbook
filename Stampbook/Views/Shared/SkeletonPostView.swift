import SwiftUI

/// Native iOS skeleton post loader
/// Shows placeholder content with iOS native redacted shimmer effect
struct SkeletonPostView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header (profile pic + text)
            HStack(alignment: .top, spacing: 12) {
                // Profile picture skeleton
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                // Text lines skeleton
                VStack(alignment: .leading, spacing: 6) {
                    // Name + stamp name line (longer)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 16)
                        .frame(maxWidth: .infinity)
                    
                    // Location line (shorter)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 14)
                    
                    // Date line (shorter)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 14)
                }
            }
            
            // Photo gallery skeleton - horizontal scroll with 120x120 squares
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Show 3 skeleton photo squares to match PhotoGalleryView layout
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 120, height: 120)
                    }
                }
            }
            
            // Like/comment row skeleton
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 16)
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            SkeletonPostView()
            Divider()
            SkeletonPostView()
            Divider()
            SkeletonPostView()
        }
        .padding(.horizontal, 20)
    }
}

