import SwiftUI

// MARK: - Collection Detail View
// Available to both signed-in and signed-out users for browsing
// Signed-out users can view stamps but see lock icons on uncollected stamps
struct CollectionDetailView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @Environment(\.dismiss) private var dismiss
    let collection: Collection
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    private var stampsInCollection: [Stamp] {
        stampsManager.stampsInCollection(collection.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Collection name and description
                    VStack(spacing: 6) {
                        Text(collection.name)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(collection.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 64)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    
                    // Grid of stamps
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(stampsInCollection) { stamp in
                            NavigationLink(destination: 
                                StampDetailView(
                                    stamp: stamp,
                                    userLocation: nil,
                                    showBackButton: true
                                )
                                .environmentObject(stampsManager)
                            ) {
                                CollectionStampItem(stamp: stamp)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 48)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
    }
}

struct CollectionStampItem: View {
    @EnvironmentObject var stampsManager: StampsManager
    let stamp: Stamp
    
    private var isCollected: Bool {
        stampsManager.isCollected(stamp)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if isCollected {
                // Show the stamp image if collected
                Image(stamp.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Show gray box with lock icon if not collected
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 160)
                    
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                }
            }
            
            // Stamp name (centered, fixed height for 2 lines)
            Text(stamp.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
        }
    }
}



