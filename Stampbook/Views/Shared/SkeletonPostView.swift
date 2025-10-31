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
            
            // Photo skeleton (square-ish)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(1.2, contentMode: .fit)
            
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

