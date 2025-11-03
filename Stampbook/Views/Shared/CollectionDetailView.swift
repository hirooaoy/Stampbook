import SwiftUI

// MARK: - Collection Detail View
// Available to both signed-in and signed-out users for browsing
// Signed-out users can view stamps but see lock icons on uncollected stamps
struct CollectionDetailView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @Environment(\.dismiss) private var dismiss
    let collection: Collection
    
    @State private var collectionStamps: [Stamp] = []
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
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
                    
                    if isLoading {
                        // Loading skeleton
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(0..<6, id: \.self) { _ in
                                VStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 160)
                                    
                                    Text("Loading...")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
                                }
                                .redacted(reason: .placeholder)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 48)
                    } else {
                        // Grid of stamps
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(collectionStamps) { stamp in
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
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .onAppear {
            loadCollectionStamps()
        }
    }
    
    private func loadCollectionStamps() {
        guard isLoading else { return }
        
        Task {
            // LAZY LOADING: Fetch ONLY stamps in this collection
            print("🎯 [CollectionDetailView] Fetching stamps for collection: \(collection.id)")
            let stamps = await stampsManager.fetchStampsInCollection(collectionId: collection.id)
            
            await MainActor.run {
                collectionStamps = stamps
                isLoading = false
            }
        }
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
                if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                    // Load from Firebase Storage
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure, .empty:
                            // Fallback to placeholder
                            Image("empty")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else if !stamp.imageName.isEmpty {
                    // Fallback to bundled image for backward compatibility
                    Image(stamp.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // No image - show placeholder
                    Image("empty")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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



