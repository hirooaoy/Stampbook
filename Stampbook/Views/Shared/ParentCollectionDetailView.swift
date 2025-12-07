import SwiftUI

// MARK: - Parent Collection Detail View
// Shows child collections within a parent collection (e.g., US National Parks)
struct ParentCollectionDetailView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    let parentCollection: Collection
    
    @State private var childCollections: [Collection] = []
    @State private var collectionMetadata: [String: (total: Int, collected: Int)] = [:]
    @State private var isLoadingMetadata = false
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Parent collection emoji, name and description
                    VStack(spacing: 12) {
                        // Display emoji (if exists)
                        if !parentCollection.emoji.isEmpty {
                            Text(parentCollection.emoji)
                                .font(.system(size: 64))
                        }
                        
                        // Display title
                        Text(parentCollection.name)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(parentCollection.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 64)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    
                    // List of child collections
                    VStack(spacing: 20) {
                        if isLoadingMetadata {
                            // Skeleton loading state
                            ForEach(0..<3, id: \.self) { _ in
                                SkeletonCollectionCard()
                                    .redacted(reason: .placeholder)
                            }
                        } else {
                            ForEach(sortedChildCollections()) { collection in
                                // Smart navigation: check if this child has children of its own
                                if collection.hasChildren(in: stampsManager.collections) {
                                    // This child is also a container - navigate to another ParentCollectionDetailView
                                    NavigationLink(destination: ParentCollectionDetailView(parentCollection: collection)) {
                                        let metadata = collectionMetadata[collection.id] ?? (total: 0, collected: 0)
                                        let percentage = metadata.total > 0 ? Double(metadata.collected) / Double(metadata.total) : 0.0
                                        
                                        CollectionCardView(
                                            emoji: collection.emoji,
                                            name: collection.name,
                                            collectedCount: metadata.collected,
                                            totalCount: metadata.total,
                                            completionPercentage: percentage,
                                            isParent: true  // Show as container
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                } else {
                                    // This child is a leaf collection - navigate to CollectionDetailView (stamps)
                                    NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                        let metadata = collectionMetadata[collection.id] ?? (total: 0, collected: 0)
                                        let percentage = metadata.total > 0 ? Double(metadata.collected) / Double(metadata.total) : 0.0
                                        
                                        CollectionCardView(
                                            emoji: collection.emoji,
                                            name: collection.name,
                                            collectedCount: metadata.collected,
                                            totalCount: metadata.total,
                                            completionPercentage: percentage,
                                            isParent: false  // Show as leaf
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
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
        .onAppear {
            loadChildCollections()
            loadCollectionMetadata()
        }
    }
    
    private func loadChildCollections() {
        // Filter child collections based on parentId
        childCollections = stampsManager.collections.filter { $0.parentId == parentCollection.id }
        print("🎯 [ParentCollectionDetailView] Found \(childCollections.count) child collections for \(parentCollection.name)")
    }
    
    private func loadCollectionMetadata() {
        guard !isLoadingMetadata else { return }
        
        print("🔄 [ParentCollectionDetailView] Starting metadata load for child collections")
        isLoadingMetadata = true
        
        Task {
            let startTime = Date()
            
            let collectedStampIds = stampsManager.userCollection.collectedStamps.map { $0.stampId }
            print("🎯 [ParentCollectionDetailView] User has \(collectedStampIds.count) collected stamps")
            
            let collectedStamps = await stampsManager.fetchStamps(ids: collectedStampIds)
            
            var metadata: [String: (total: Int, collected: Int)] = [:]
            
            // Calculate metadata for each child collection
            for collection in childCollections {
                let (total, collected) = calculateMetadataForCollection(
                    collection: collection,
                    collectedStamps: collectedStamps,
                    allCollections: stampsManager.collections,
                    metadata: &metadata
                )
                
                metadata[collection.id] = (total: total, collected: collected)
                let collectionType = collection.hasChildren(in: stampsManager.collections) ? "container" : "leaf"
                print("✅ [ParentCollectionDetailView] \(collection.name) (\(collectionType)): \(collected)/\(total)")
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("✅ [ParentCollectionDetailView] Metadata load complete in \(String(format: "%.2f", totalTime))s")
            
            await MainActor.run {
                collectionMetadata = metadata
                isLoadingMetadata = false
            }
        }
    }
    
    /// Calculate metadata for a collection (works for both leaf and container collections)
    private func calculateMetadataForCollection(
        collection: Collection,
        collectedStamps: [Stamp],
        allCollections: [Collection],
        metadata: inout [String: (total: Int, collected: Int)]
    ) -> (total: Int, collected: Int) {
        // If it's a leaf collection (has stamps, no children), count directly
        if !collection.hasChildren(in: allCollections) {
            let total = collection.totalStamps
            let collected = collectedStamps.filter { stamp in
                stamp.collectionIds.contains(collection.id)
            }.count
            return (total: total, collected: collected)
        }
        
        // If it's a container (has children), aggregate from descendants
        let children = collection.getChildren(from: allCollections)
        return children.reduce((0, 0)) { sum, child in
            // Check if we already calculated this child
            if let childData = metadata[child.id] {
                return (sum.0 + childData.total, sum.1 + childData.collected)
            }
            
            // Recursively calculate child's metadata
            let childData = calculateMetadataForCollection(
                collection: child,
                collectedStamps: collectedStamps,
                allCollections: allCollections,
                metadata: &metadata
            )
            
            // Cache it
            metadata[child.id] = childData
            return (sum.0 + childData.total, sum.1 + childData.collected)
        }
    }
    
    private func sortedChildCollections() -> [Collection] {
        childCollections.sorted { collection1, collection2 in
            let metadata1 = collectionMetadata[collection1.id] ?? (total: 0, collected: 0)
            let metadata2 = collectionMetadata[collection2.id] ?? (total: 0, collected: 0)
            
            let completion1 = metadata1.total > 0 ? Double(metadata1.collected) / Double(metadata1.total) : 0.0
            let completion2 = metadata2.total > 0 ? Double(metadata2.collected) / Double(metadata2.total) : 0.0
            
            if completion1 != completion2 {
                return completion1 > completion2  // Higher completion first
            } else {
                return collection1.name < collection2.name  // Alphabetical tiebreaker
            }
        }
    }
}

// Skeleton card for loading state
private struct SkeletonCollectionCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack(alignment: .leading) {
            Color(.secondarySystemBackground)
            
            HStack(alignment: .center, spacing: 8) {
                Text("🏔️")
                    .font(.system(size: 26))
                    .frame(width: 34, height: 34)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Loading Collection")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("0 out of 0 stamps collected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 24)
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
        .cornerRadius(12)
    }
}

