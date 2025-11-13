import SwiftUI

// MARK: - Collection Detail View
// Available to both signed-in and signed-out users for browsing
// Signed-out users can view stamps but see lock icons on uncollected stamps
struct CollectionDetailView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    let collection: Collection
    
    @State private var collectionStamps: [Stamp] = []
    @State private var isLoading = true
    @State private var showSuggestEdit = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Collection emoji, name and description
                    VStack(spacing: 12) {
                        // Display emoji (if exists)
                        if !collection.emoji.isEmpty {
                            Text(collection.emoji)
                                .font(.system(size: 64))
                        }
                        
                        // Display title
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {
                        showSuggestEdit = true
                    }) {
                        Label("Suggest an edit", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSuggestEdit) {
            SuggestCollectionEditView(collectionId: collection.id, collectionName: collection.name)
                .environmentObject(authManager)
        }
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
                    // Load from Firebase Storage with caching (prevents blink on repeat views)
                    CachedImageView.stampPhoto(
                        imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                        storagePath: stamp.imageStoragePath,
                        stampId: stamp.id,
                        size: CGSize(width: 160, height: 160),
                        cornerRadius: 12,
                        imageUrl: imageUrl
                    )
                    .frame(height: 160)
                } else if !stamp.imageName.isEmpty {
                    // Fallback to bundled image for backward compatibility
                    Image(stamp.imageName)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // No image - show placeholder
                    Image("empty")
                        .resizable()
                        .renderingMode(.original)
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



