import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var followManager: FollowManager
    @Environment(\.dismiss) private var dismiss
    @State private var displayedCount = 20 // Initial load
    @State private var bookmarkedStamps: [Stamp] = [] // Lazy-loaded stamps
    @State private var hasLoadedOnce = false
    
    // Optional parameters for viewing other users' bookmarks
    let viewingUserId: String?
    let viewingDisplayName: String?
    let isFollowing: Bool
    
    // Default initializer for current user (backward compatible)
    init(viewingUserId: String? = nil, viewingDisplayName: String? = nil, isFollowing: Bool = false) {
        self.viewingUserId = viewingUserId
        self.viewingDisplayName = viewingDisplayName
        self.isFollowing = isFollowing
    }
    
    // Are we viewing someone else's bookmarks?
    private var isViewingOtherUser: Bool {
        guard let viewingUserId = viewingUserId else { return false }
        return viewingUserId != authManager.userId
    }
    
    // Should we show the bookmarks? (following or own profile)
    private var shouldShowBookmarks: Bool {
        if !isViewingOtherUser {
            return true // Always show own bookmarks
        }
        return isFollowing // Show if following
    }
    
    // State for other users' bookmarks
    @State private var otherUserBookmarks: [BookmarkedStamp] = []
    
    // Adaptive grid: iPhone shows 2 columns, iPad shows 4-6 columns
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 4)
    ]
    
    // Get bookmarked stamp IDs sorted by date (latest first)
    private var sortedBookmarks: [(stampId: String, bookmarkedDate: Date)] {
        if isViewingOtherUser {
            // Viewing someone else's bookmarks
            return otherUserBookmarks
                .sorted { $0.bookmarkedDate > $1.bookmarkedDate }
                .map { ($0.stampId, $0.bookmarkedDate) }
        } else {
            // Viewing own bookmarks
            return stampsManager.userBookmarks.bookmarkedStamps
                .sorted { $0.bookmarkedDate > $1.bookmarkedDate }
                .map { ($0.stampId, $0.bookmarkedDate) }
        }
    }
    
    // Get stamps to display (paginated)
    private var displayedStamps: [Stamp] {
        let stampIds = sortedBookmarks.prefix(displayedCount).map { $0.stampId }
        return bookmarkedStamps.filter { stampIds.contains($0.id) }
            .sorted { stamp1, stamp2 in
                // Sort by bookmark date
                guard let date1 = sortedBookmarks.first(where: { $0.stampId == stamp1.id })?.bookmarkedDate,
                      let date2 = sortedBookmarks.first(where: { $0.stampId == stamp2.id })?.bookmarkedDate else {
                    return false
                }
                return date1 > date2
            }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Title and subtitle section (matching StampDetailView layout)
                    VStack(spacing: 6) {
                        Text("Bookmarks")
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(isViewingOtherUser ? "\(viewingDisplayName?.isEmpty == false ? viewingDisplayName! : "User")'s bucket list" : "Your personal bucket list")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    
                    if shouldShowBookmarks {
                        // Show bookmarks content
                        bookmarksContent
                    } else {
                        // Show locked state for non-followers
                        lockedBookmarksView
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !hasLoadedOnce else { return }
            await loadBookmarkedStamps()
        }
        .onChange(of: stampsManager.userBookmarks.bookmarkedStamps.count) { oldValue, newValue in
            // Reload when bookmarks change (only for own bookmarks)
            if !isViewingOtherUser && newValue != oldValue {
                Task {
                    await loadBookmarkedStamps()
                }
            }
        }
    }
    
    // MARK: - Bookmarks Content View
    
    @ViewBuilder
    private var bookmarksContent: some View {
        if stampsManager.isLoadingUserStamps && !hasLoadedOnce {
            // Skeleton loading state
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonStampGridItem()
                        .redacted(reason: .placeholder)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        } else if sortedBookmarks.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Image(systemName: "bookmark")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("No bookmarks yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text(isViewingOtherUser ? "This user hasn't bookmarked any stamps" : "Bookmark a stamp to visit later")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 80)
            .frame(maxWidth: .infinity)
        } else {
            // Grid view
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(Array(displayedStamps.enumerated()), id: \.element.id) { index, stamp in
                    NavigationLink(destination:
                                    StampDetailView(
                                        stamp: stamp,
                                        isCollected: stampsManager.isCollected(stamp),
                                        userLocation: nil,
                                        showBackButton: true
                                    )
                                        .environmentObject(stampsManager)
                    ) {
                        BookmarkStampGridItem(stamp: stamp)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onAppear {
                        // Load more when approaching the end
                        if index == displayedStamps.count - 1 && displayedCount < sortedBookmarks.count {
                            loadMoreStamps()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 48)
        }
    }
    
    // MARK: - Locked Bookmarks View (for non-followers)
    
    private var lockedBookmarksView: some View {
        VStack(spacing: 16) {
            // Blurred/placeholder area
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Follow to see bookmarks")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Places they want to visit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 20)
            
            // Follow button
            if let viewingUserId = viewingUserId {
                Button(action: {
                    guard let currentUserId = authManager.userId else { return }
                    followManager.toggleFollow(currentUserId: currentUserId, targetUserId: viewingUserId, profileManager: nil) { _ in
                        // After following, reload bookmarks
                        Task {
                            await loadOtherUserBookmarks(userId: viewingUserId)
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        if followManager.isProcessingFollow[viewingUserId] == true {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                                .tint(.white)
                        }
                        Text("Follow")
                    }
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(followManager.isProcessingFollow[viewingUserId] == true)
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 60)
    }
    
    private func loadBookmarkedStamps() async {
        guard !stampsManager.isLoadingUserStamps else {
            print("⏭️ [BookmarksView] Already loading, skipping")
            return
        }
        
        print("🔄 [BookmarksView] Loading bookmarked stamps...")
        
        await MainActor.run {
            stampsManager.isLoadingUserStamps = true
        }
        
        if isViewingOtherUser, let viewingUserId = viewingUserId {
            // Load other user's bookmarks
            await loadOtherUserBookmarks(userId: viewingUserId)
        } else {
            // Load own bookmarks
            // Fetch ONLY bookmarked stamps
            let bookmarkIds = stampsManager.userBookmarks.bookmarkedStamps.map { $0.stampId }
            print("🎯 [BookmarksView] Fetching \(bookmarkIds.count) bookmarked stamps")
            
            // Include removed stamps - users can still see stamps they bookmarked
            let stamps = await stampsManager.fetchStamps(ids: bookmarkIds, includeRemoved: true)
            
            await MainActor.run {
                bookmarkedStamps = stamps
                hasLoadedOnce = true
                stampsManager.isLoadingUserStamps = false
                
                print("✅ [BookmarksView] Loaded \(stamps.count) stamps")
            }
        }
    }
    
    private func loadOtherUserBookmarks(userId: String) async {
        do {
            // Fetch bookmarks from Firestore
            let bookmarks = try await FirebaseService.shared.fetchBookmarkedStamps(for: userId)
            
            await MainActor.run {
                otherUserBookmarks = bookmarks
            }
            
            // Fetch the actual stamp data
            let stampIds = bookmarks.map { $0.stampId }
            print("🎯 [BookmarksView] Fetching \(stampIds.count) bookmarked stamps for user \(userId)")
            
            let stamps = await stampsManager.fetchStamps(ids: stampIds, includeRemoved: true)
            
            await MainActor.run {
                bookmarkedStamps = stamps
                hasLoadedOnce = true
                stampsManager.isLoadingUserStamps = false
                
                print("✅ [BookmarksView] Loaded \(stamps.count) stamps for other user")
            }
        } catch {
            print("❌ [BookmarksView] Failed to load other user's bookmarks: \(error.localizedDescription)")
            await MainActor.run {
                hasLoadedOnce = true
                stampsManager.isLoadingUserStamps = false
            }
        }
    }
    
    private func loadMoreStamps() {
        let newCount = min(displayedCount + 20, sortedBookmarks.count)
        displayedCount = newCount
    }
}

// MARK: - Bookmark Stamp Grid Item (shows grey box with lock for uncollected stamps)

struct BookmarkStampGridItem: View {
    let stamp: Stamp
    @EnvironmentObject var stampsManager: StampsManager
    
    private var isCollected: Bool {
        stampsManager.isCollected(stamp)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if isCollected {
                // Show the stamp image if collected
                if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                    CachedImageView.stampPhoto(
                        imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                        storagePath: stamp.imageStoragePath,
                        stampId: stamp.id,
                        size: CGSize(width: 148, height: 148),
                        cornerRadius: 0,
                        imageUrl: imageUrl
                    )
                    .frame(width: 148, height: 148)
                } else if !stamp.imageName.isEmpty {
                    Image(stamp.imageName)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 148, height: 148)
                } else {
                    Image("empty")
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 148, height: 148)
                }
             } else {
                 // Show gray box with lock icon if not collected
                 ZStack {
                     RoundedRectangle(cornerRadius: 12)
                         .fill(Color.gray.opacity(0.3))
                         .frame(width: 148, height: 148)
                     
                     Image(systemName: "lock.fill")
                         .font(.system(size: 40))
                         .foregroundColor(.gray)
                 }
             }
            
            // Stamp name
            Text(stamp.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
        }
    }
}

// MARK: - Skeleton Loading View

struct SkeletonStampGridItem: View {
    var body: some View {
        VStack(spacing: 12) {
            // Stamp image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 160)
            
            // Stamp name placeholder (2 lines)
            VStack(spacing: 4) {
                Text("Placeholder Stamp Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Second Line")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40, alignment: .top)
        }
    }
}

