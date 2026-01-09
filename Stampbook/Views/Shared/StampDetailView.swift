import SwiftUI
import MapKit
import Contacts
import AuthenticationServices

struct StampDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var mapCoordinator: MapCoordinator
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @EnvironmentObject var followManager: FollowManager
    let stamp: Stamp
    let isCollectedAtInit: Bool  // Passed explicitly to avoid environment object dependency in init
    let userLocation: CLLocation?
    let showBackButton: Bool
    let viewingUserId: String?  // If viewing someone else's profile, this is their userId
    let viewingDisplayName: String?  // If viewing someone else's profile, this is their display name (for "Justin's Memory" heading)
    @State private var showMemorySection = false
    @State private var showNotesEditor = false
    @State private var editingNotes = ""
    @State private var userRank: Int? // User's rank for this stamp (1st, 2nd, 3rd collector, etc.)
    @State private var collectionProgress: [String: Int] = [:] // collectionId -> collected count
    @State private var collectionTotals: [String: Int] = [:] // collectionId -> total ACTIVE stamps count
    @State private var showSuggestEdit = false
    @State private var showAddressOptions = false
    @State private var showCopyConfirmation = false
    @State private var showDirectSignInSheet = false
    @State private var isAnimatingCollection = false // Track if we're in collection animation
    @State private var displayStats: StampStatistics? = nil // Stats to display (frozen during animation)
    @State private var viewingUserCollectedStamp: CollectedStamp? = nil // When viewing someone else's profile, their collected stamp data
    
    // Animation states (set correctly in init based on isCollected)
    @State private var imageScale: CGFloat
    @State private var showStampImage: Bool
    @State private var showLockIcon: Bool
    
    init(stamp: Stamp, isCollected: Bool, userLocation: CLLocation? = nil, showBackButton: Bool = false, viewingUserId: String? = nil, viewingDisplayName: String? = nil, initialCollectedStamp: CollectedStamp? = nil) {
        self.stamp = stamp
        self.isCollectedAtInit = isCollected
        self.userLocation = userLocation
        self.showBackButton = showBackButton
        self.viewingUserId = viewingUserId
        self.viewingDisplayName = viewingDisplayName
        
        // Pre-populate collected stamp data if provided (from FeedPost)
        if let initialStamp = initialCollectedStamp {
            _viewingUserCollectedStamp = State(initialValue: initialStamp)
            // Show memory section immediately if we have data (no animation needed - it's instant)
            _showMemorySection = State(initialValue: true)
        } else if isCollectedAtInit && viewingUserId == nil {
            // Viewing own collected stamp - show memory section immediately
            _showMemorySection = State(initialValue: true)
        } else {
            _showMemorySection = State(initialValue: false)
        }
        
        // Set correct initial animation states - no .onAppear updates needed!
        if isCollected {
            // Already collected: show at normal size
            _imageScale = State(initialValue: 1.0)
            _showStampImage = State(initialValue: true)
            _showLockIcon = State(initialValue: false)
        } else {
            // Not collected: show large with lock (ready for collection animation)
            _imageScale = State(initialValue: 1.5)
            _showStampImage = State(initialValue: false)
            _showLockIcon = State(initialValue: true)
        }
    }
    
    // Computed property to get live stampStats from StampsManager
    private var stampStats: StampStatistics? {
        // During collection animation, show frozen stats
        if isAnimatingCollection, let frozen = displayStats {
            return frozen
        }
        // Otherwise show live stats
        return stampsManager.stampStatistics[stamp.id]
    }
    
    // Are we viewing someone else's profile?
    private var isViewingOtherUser: Bool {
        guard let viewingUserId = viewingUserId else { return false }
        return viewingUserId != authManager.userId
    }
    
    // Check if current user is following the viewed user
    private var isFollowingViewedUser: Bool {
        guard let viewingUserId = viewingUserId else { return false }
        return followManager.isFollowing[viewingUserId] ?? false
    }
    
    // Should we show the full memory details (notes, photos)?
    // YES if: viewing own stamp OR following the user
    // NO if: viewing someone else's stamp and not following them
    private var shouldShowMemoryDetails: Bool {
        if !isViewingOtherUser {
            // Viewing own stamp - always show
            return true
        } else {
            // Viewing someone else's stamp - only show if following them
            return isFollowingViewedUser
        }
    }
    
    // Computed property to get user rank from cached CollectedStamp
    // This updates automatically when userCollection changes
    private var cachedUserRank: Int? {
        if isViewingOtherUser {
            // Viewing someone else's profile - use their rank
            return viewingUserCollectedStamp?.userRank
        } else {
            // Viewing own profile - use current user's rank
            return stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == stamp.id })?.userRank
        }
    }
    
    private var isCollected: Bool {
        stampsManager.isCollected(stamp)
    }
    
    // Should we show the Memory section?
    // - If viewing own profile: show if current user collected it
    // - If viewing someone else: show if THEY collected it (based on viewingUserCollectedStamp)
    private var shouldShowMemory: Bool {
        if isViewingOtherUser {
            return viewingUserCollectedStamp != nil
        } else {
            return isCollected
        }
    }
    
    // Check if there are photos or notes to display (affects padding)
    private var hasPhotosOrNotes: Bool {
        if isViewingOtherUser {
            // Viewing someone else - check if they have photos or notes
            let hasPhotos = !(viewingUserCollectedStamp?.userImageNames.isEmpty ?? true)
            let hasNotes = !userNotes.isEmpty
            return hasPhotos || hasNotes
        } else {
            // Viewing own profile - always has "Add Photos" and "Add Notes" buttons
            return true
        }
    }
    
    // Check if stamp should use full width (wide panoramas)
    private var isWideStamp: Bool {
        guard let aspectRatio = stamp.aspectRatio else { return false }
        return aspectRatio < 0.85
    }
    
    // Width for stamps (iPhone only)
    private var stampWidth: CGFloat {
        return isWideStamp ? 345 : 260  // Wide: full width minus padding (393-48), Standard: 260
    }
    
    // Dynamic stamp height based on aspect ratio
    private var stampHeight: CGFloat {
        let height = stampWidth * (stamp.aspectRatio ?? 1.0)
        return max(100, height)  // Ensure minimum 100px
    }
    
    private var isWithinRange: Bool {
        // Welcome stamp can be claimed from anywhere
        if stamp.isWelcomeStamp {
            return true
        }
        
        guard let userLocation = userLocation else { return false }
        let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
        let distance = userLocation.distance(from: stampLocation)
        return distance <= stamp.collectionRadiusInMeters
    }
    
    private var collectedDate: Date? {
        if isViewingOtherUser {
            // Viewing someone else's profile - use their date
            return viewingUserCollectedStamp?.collectedDate
        } else {
            // Viewing own profile - use current user's date
            return stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == stamp.id })?.collectedDate
        }
    }
    
    private var userNotes: String {
        if isViewingOtherUser {
            // Viewing someone else's profile - use their notes
            return viewingUserCollectedStamp?.userNotes ?? ""
        } else {
            // Viewing own profile - use current user's notes
            return stampsManager.userCollection.collectedStamps
                .first(where: { $0.stampId == stamp.id })?.userNotes ?? ""
        }
    }
    
    private var formattedFullDate: String {
        guard let date = collectedDate else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    
    // Track if we should show slow load warning (after 2 second delay)
    @State private var showSlowLoadWarning = false
    
    // Status message for unavailable stamps (removed or expired)
    private var statusBanner: (message: String, icon: String, color: Color)? {
        // Priority 1: Stamp was removed by admin
        if stamp.status == "removed" {
            return ("This stamp was removed by admin", "exclamationmark.triangle.fill", .orange)
        }
        
        // Priority 2: Event stamp has expired
        if let until = stamp.availableUntil, Date() > until {
            let dateStr = until.formatted(.dateTime.month(.abbreviated).day().year())
            return ("This event stamp expired on \(dateStr)", "calendar.badge.exclamationmark", .orange)
        }
        
        // Priority 3: Collected but image taking a long time to load (4+ seconds)
        // Only show after delay to avoid flash on fast connections
        if isCollected && showSlowLoadWarning && !isStampImageCached {
            return ("Image will load when you have a strong connection", "wifi.exclamationmark", .blue)
        }
        
        return nil
    }
    
    // Check if stamp image is already cached
    private var isStampImageCached: Bool {
        // If stamp has no remote image, it's using a bundled asset (always "cached")
        guard let imageUrl = stamp.imageUrl, !imageUrl.isEmpty else {
            return true
        }
        
        // Generate the same cache key used by ImageManager when downloading
        let urlHash = abs(imageUrl.hashValue)
        let cacheKey = "\(stamp.id)_\(urlHash).png"
        
        // Check both memory cache and disk cache
        if ImageCacheManager.shared.getFullImage(key: cacheKey) != nil {
            return true
        }
        
        // Also check disk cache by attempting to load
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(cacheKey)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return true
        }
        
        return false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Stamp name and collection count
                    VStack(spacing: 6) {
                        Text(stamp.name)
                            .font(.system(size: 28, weight: .bold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        collectionCountView
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    
                    // Centered stamp image with flexible height for different aspect ratios
                    ZStack {
                        // Lock icon - show when not collected
                        if showLockIcon {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: stampWidth, height: stampHeight)
                            
                            Image(systemName: "lock.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.gray)
                        }
                        
                        // Stamp image - always in view tree so scale animation works
                        ZStack {
                            if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                                CachedImageView.stampPhoto(
                                    imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                                    storagePath: stamp.imageStoragePath,
                                    stampId: stamp.id,
                                    size: CGSize(width: stampWidth, height: stampHeight),
                                    cornerRadius: 0,
                                    useFullResolution: true,
                                    imageUrl: imageUrl
                                )
                                .frame(width: stampWidth, height: stampHeight)
                            } else if !stamp.imageName.isEmpty {
                                Image(stamp.imageName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: stampWidth, height: stampHeight)
                            } else {
                                Image("empty")
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(maxWidth: 260, maxHeight: 400)
                            }
                        }
                        .scaleEffect(imageScale)
                        .opacity(showStampImage ? 1.0 : 0.0)
                        
                        // Copy confirmation checkmark overlay
                        if showCopyConfirmation {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.6))
                                .frame(width: stampWidth, height: stampHeight)
                            
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.white)
                                Text("Copied!")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(height: stampHeight)
                    .contextMenu {
                        if isCollected {
                            Button(action: {
                                copyStampImage()
                            }) {
                                Label("Copy Image", systemImage: "doc.on.doc")
                            }
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showCopyConfirmation)
                    .padding(.bottom, 36)
                    
                    // Status banner - shows offline sync, removed, or expired status
                    if let banner = statusBanner {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: banner.icon)
                                .foregroundColor(banner.color)
                                .font(.system(size: 20))
                            
                            Text(banner.message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(banner.color.opacity(0.1))
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.3), value: statusBanner != nil)
                    }
                    
                    // Memory section - only visible after collection
                    if shouldShowMemory && showMemorySection {
                        VStack(alignment: .leading, spacing: 0) {
                            // Memory heading - show username if viewing someone else's profile
                            Text(isViewingOtherUser ? "\(viewingDisplayName?.isEmpty == false ? viewingDisplayName! : "User")'s memory" : "Memory")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
                            // Check if we should show full memory details or privacy placeholder
                            if shouldShowMemoryDetails {
                                // FULL MEMORY: Show rank, date, photos, and notes
                                // Memory cards showing rank and date
                                HStack(spacing: 12) {
                                    // Rank card - shows what number collector the user was (like being #23 in line - permanent!)
                                    HStack(spacing: 12) {
                                        Image(systemName: "medal.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.yellow)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Number")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            if let rank = cachedUserRank ?? userRank {
                                                Text("#\(rank)")
                                                    .font(.body)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.5)
                                            } else {
                                                Text("...")
                                                    .font(.body)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.5)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 70)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                    
                                    // Date card
                                    HStack(spacing: 12) {
                                        Image(systemName: "calendar")
                                            .font(.system(size: 24))
                                            .foregroundColor(.red)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Date")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(formattedFullDate)
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.5)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 70)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                }
                                .padding(.bottom, 24)
                                
                                // Photo section
                                if stampsManager.userCollection.collectedStamps.first(where: { $0.stampId == stamp.id }) != nil || isViewingOtherUser {
                                    // Always show photo gallery (it handles both empty and non-empty states)
                                    PhotoGalleryView(
                                        stampId: stamp.id,
                                        userId: isViewingOtherUser ? viewingUserId : nil,
                                        userPhotos: isViewingOtherUser ? (viewingUserCollectedStamp?.userImageNames ?? []) : nil,
                                        userPhotoPaths: isViewingOtherUser ? (viewingUserCollectedStamp?.userImagePaths ?? []) : nil
                                    )
                                    .padding(.bottom, hasPhotosOrNotes ? 16 : 0)
                                }
                                
                                // Add notes button - only show if NOT viewing someone else's profile
                                if !isViewingOtherUser {
                                    Button(action: {
                                        editingNotes = userNotes
                                        showNotesEditor = true
                                    }) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Image(systemName: "note.text")
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .frame(width: 18, height: 18, alignment: .center)
                                            
                                            if userNotes.isEmpty {
                                                Text("Add Notes")
                                                    .font(.body)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                            } else {
                                                Text(userNotes)
                                                    .font(.body)
                                                    .foregroundColor(.primary)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            
                                            Spacer(minLength: 6)
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(minHeight: 44)              // Larger tap target
                                        .contentShape(Rectangle())         // Make entire frame tappable
                                    }
                                } else if !userNotes.isEmpty {
                                    // Viewing someone else's notes - show as read-only text
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Image(systemName: "note.text")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(width: 18, height: 18, alignment: .center)
                                        
                                        Text(userNotes)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(minHeight: 44)
                                }
                            } else {
                                // PRIVACY PLACEHOLDER: Show "Follow to see memory"
                                VStack(spacing: 16) {
                                    // Blurred/placeholder area
                                    HStack(spacing: 12) {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 28))
                                            .foregroundColor(.gray)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Follow to see memory")
                                                .font(.body)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            
                                            Text("Photos, notes, and collection date")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(12)
                                    
                                    // Follow button
                                    if let viewingUserId = viewingUserId {
                                        Button(action: {
                                            guard let currentUserId = authManager.userId else { return }
                                            followManager.followUser(currentUserId: currentUserId, targetUserId: viewingUserId) { _ in
                                                // After following, the view will automatically update
                                                // because followManager.isFollowing will change
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
                                    }
                                }
                                .padding(.bottom, 16)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, hasPhotosOrNotes && shouldShowMemoryDetails ? 36 : 24)
                        .transition(.opacity)
                    }
                    
                    // Divider
                    if shouldShowMemory && showMemorySection {
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                    }
                    
                    // About section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text(stamp.about)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                    
                    // Divider - only show if location section is visible
                    if !stamp.isWelcomeStamp {
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                    }
                    
                    // Location section - hide for welcome stamp
                    if !stamp.isWelcomeStamp {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Location")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Button(action: {
                                showAddressOptions = true
                            }) {
                                HStack(spacing: 12) {
                                    Text(stamp.address)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                    
                                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    }
                    
                    // Things to do section
                    if !stamp.thingsToDoFromEditors.isEmpty {
                        // Divider
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Things to do")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(stamp.thingsToDoFromEditors, id: \.self) { tip in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        Text(tip)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    }
                    
                    // Collections section - only show if stamp belongs to at least one collection
                    // Hide collections for removed stamps to prevent confusion
                    // (User keeps stamp in profile, but it's no longer part of collections)
                    if !stampCollections.isEmpty {
                        // Divider
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Collections")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            // Only show leaf collections (collections that actually contain stamps)
                            // Filter out container collections (Japan, Osaka, etc.) - only show the final level (Osaka Must Visits, etc.)
                            ForEach(stampCollections.filter { !$0.hasChildren(in: stampsManager.collections) }) { collection in
                                NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                    // Use pre-calculated progress from state
                                    let collectedInCollection = collectionProgress[collection.id] ?? 0
                                    // Use dynamic total (only active stamps) instead of static collection.totalStamps
                                    let totalActiveStamps = collectionTotals[collection.id] ?? collection.totalStamps
                                    let percentage = totalActiveStamps > 0 ? Double(collectedInCollection) / Double(totalActiveStamps) : 0.0
                                    
                                    CollectionCardView(
                                        emoji: collection.emoji,
                                        name: collection.name,
                                        collectedCount: collectedInCollection,
                                        totalCount: totalActiveStamps,
                                        completionPercentage: percentage,
                                        isParent: false  // Leaf collections only
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, !stampCollections.isEmpty ? 48 : 24)
                .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isCollected)
            }
            
            // Sticky button at bottom
            VStack(spacing: 0) {
                Divider()
                
                if !authManager.isSignedIn {
                    // Not signed in - show text and Get Started button
                    VStack(spacing: 16) {
                        Text("Start your stamp collection")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Button(action: {
                            showDirectSignInSheet = true
                        }) {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                } else if !isCollected {
                    Button(action: {
                        if isWithinRange, let userId = authManager.userId {
                                Task {
                                await collectStampWithAnimation(userId: userId)
                            }
                        }
                    }) {
                            Text(isWithinRange ? "Collect Stamp" : "You are too far")
                                .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(isWithinRange ? Color.blue : Color.clear)
                        .foregroundColor(isWithinRange ? .white : .secondary)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                .opacity(isWithinRange ? 0 : 1)
                        )
                    }
                    .disabled(!isWithinRange)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                } else {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("Collected")
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .toolbar {
            // Bookmark button - leftmost, only show for signed-in users
            if !stamp.isWelcomeStamp && authManager.isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        if let userId = authManager.userId {
                            stampsManager.toggleBookmark(stamp.id, userId: userId)
                        }
                    }) {
                        Image(systemName: stampsManager.isBookmarked(stamp.id) ? "bookmark.fill" : "bookmark")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(stampsManager.isBookmarked(stamp.id) ? .yellow : .secondary)
                    }
                }
            }
            
            // Triple dot menu - middle, hide for welcome stamp
            if !stamp.isWelcomeStamp {
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
            
            // Close/dismiss button - rightmost, always show when not using back button
            if !showBackButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        // .toolbar(.hidden, for: .tabBar)
        .if(!showBackButton) { view in
            view.presentationDetents([.fraction(0.78), .large])
        }
        .onAppear {
            // Animation states are now set correctly in init() - no updates needed!
            
            // Check follow status if viewing someone else's profile
            if isViewingOtherUser, let viewingUserId = viewingUserId, let currentUserId = authManager.userId {
                followManager.checkFollowStatus(currentUserId: currentUserId, targetUserId: viewingUserId)
            }
            
            // Start slow-load warning timer (only if collected and not cached)
            // Shows banner after 4 seconds to avoid flash on fast WiFi
            if isCollected && !isStampImageCached {
                Task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                    await MainActor.run {
                        // Only show if image still not cached after 4 seconds
                        if !isStampImageCached {
                            showSlowLoadWarning = true
                        }
                    }
                }
            }
            
            // If we have initial collected stamp data (from FeedPost), memory is already shown
            // (set in init, no animation needed since it's instant)
            
            // Single task to load data sequentially (prevents race conditions)
            Task {
                // 1. If viewing someone else's profile, fetch their collected stamp data
                // (Only fetch if we don't already have it from FeedPost)
                if isViewingOtherUser, let viewingUserId = viewingUserId, viewingUserCollectedStamp == nil {
                    do {
                        let fetchedStamp = try await FirebaseService.shared.fetchCollectedStamp(userId: viewingUserId, stampId: stamp.id)
                        await MainActor.run {
                            viewingUserCollectedStamp = fetchedStamp
                            // Show memory section if we just fetched it
                            if shouldShowMemory {
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    showMemorySection = true
                                }
                            }
                        }
                    } catch {
                        print("⚠️ Error fetching viewing user's collected stamp: \(error)")
                    }
                }
                
                // 2. Always fetch stamp statistics first (needed for "X people have this stamp")
                // Only fetch if cache is stale (older than 5 minutes) or doesn't exist
                if stampStats == nil || stampStats?.isCacheStale() == true {
                    _ = await stampsManager.fetchStampStatistics(stampId: stamp.id)
                }
                
                // 3. Fetch userRank in background if we have initial data but missing rank
                // (FeedPost doesn't include userRank, so fetch it separately)
                if isViewingOtherUser, let currentStamp = viewingUserCollectedStamp, currentStamp.userRank == nil, let viewingUserId = viewingUserId {
                    do {
                        let fetchedStamp = try await FirebaseService.shared.fetchCollectedStamp(userId: viewingUserId, stampId: stamp.id)
                        await MainActor.run {
                            // Update with rank if we got it
                            if let fetchedStamp = fetchedStamp, fetchedStamp.userRank != nil {
                                // Replace the stamp with one that has rank
                                viewingUserCollectedStamp = fetchedStamp
                            }
                        }
                    } catch {
                        print("⚠️ Error fetching userRank: \(error)")
                    }
                }
                
                // 4. Then handle collected-specific logic (for own profile or if we just fetched)
                if shouldShowMemory, !isViewingOtherUser || viewingUserCollectedStamp != nil {
                    // Only fetch user rank if not cached (for old stamps collected before rank caching)
                    // Rank is permanent (your position in collector line), so cache is always valid
                    if isViewingOtherUser {
                        // Viewing someone else - rank already loaded or being fetched above
                    } else if cachedUserRank == nil, let userId = authManager.userId {
                        let fetchedRank = await stampsManager.getUserRankForStamp(stampId: stamp.id, userId: userId)
                        userRank = fetchedRank  // Already on MainActor
                    }
                    
                    // Calculate collection progress (only for own profile)
                    if !isViewingOtherUser {
                        await calculateCollectionProgress()
                    }
                }
            }
        }
        .onChange(of: isCollected) { _, newValue in
            // Don't update when viewing someone else's profile
            guard !isViewingOtherUser else { return }
            
            if newValue {
                // Memory section and stats will be shown by collectStampWithAnimation()
                // with proper delay and animation (don't update immediately here)
                
                // Fetch other data when just collected
                Task {
                    // Rank should already be cached by collectStamp(), but fallback just in case
                    if cachedUserRank == nil, let userId = authManager.userId {
                        let fetchedRank = await stampsManager.getUserRankForStamp(stampId: stamp.id, userId: userId)
                        userRank = fetchedRank  // Already on MainActor
                    }
                    
                    // Recalculate collection progress
                    await calculateCollectionProgress()
                }
            } else {
                showMemorySection = false
                userRank = nil
            }
        }
        .onDisappear {
            // Reset slow load warning state when view dismisses
            showSlowLoadWarning = false
        }
        .onChange(of: stampsManager.userCollection.collectedStamps.count) { _, _ in
            // Don't update when viewing someone else's profile
            guard !isViewingOtherUser else { return }
            
            // Recalculate collection progress whenever the user collects any stamp
            // This ensures the collection counts stay up-to-date even when viewing one stamp
            // while collecting others in the same collection
            if shouldShowMemory {
                Task {
                    await calculateCollectionProgress()
                }
            }
        }
        .fullScreenCover(isPresented: $showNotesEditor) {
            NotesEditorView(notes: $editingNotes) { savedNotes in
                stampsManager.userCollection.updateNotes(for: stamp.id, notes: savedNotes)
            }
        }
        .sheet(isPresented: $showSuggestEdit) {
            SuggestEditView(stampId: stamp.id, stampName: stamp.name)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showDirectSignInSheet) {
            NavigationStack {
                DirectSignInSheet(isAuthenticated: $authManager.isSignedIn)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showAddressOptions) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    // Google Maps button
                    Button(action: {
                        showAddressOptions = false
                        openInGoogleMaps()
                    }) {
                        Text("Open in Google Maps")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Apple Maps button
                    Button(action: {
                        showAddressOptions = false
                        openInAppleMaps()
                    }) {
                        Text("Open in Apple Maps")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Stampbook Maps button
                    Button(action: {
                        showAddressOptions = false
                        openInStampbookMaps()
                    }) {
                        Text("Open in Stampbook Maps")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Copy address button
                    Button(action: {
                        UIPasteboard.general.string = stamp.address
                        showAddressOptions = false
                    }) {
                        Text("Copy address")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                    
                    // Cancel button (no background)
                    Button(action: {
                        showAddressOptions = false
                    }) {
                        Text("Cancel")
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, 32)
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Collection Animation
    
    private func collectStampWithAnimation(userId: String) async {
        // 1. IN-MEMORY UPDATE & HIDE LOCK (instant, button re-enables immediately)
        await MainActor.run {
            // Freeze current stats so they don't update during animation
            displayStats = stampsManager.stampStatistics[stamp.id]
            isAnimatingCollection = true
            
            stampsManager.userCollection.addStampToCollection(stamp.id, userId: userId, userRank: nil)
            
            // Hide lock immediately (no animation needed)
            showLockIcon = false
        }
        
        // 2. Let SwiftUI render the 1.5 scale state (wait one frame)
        try? await Task.sleep(nanoseconds: 16_000_000) // 16ms = 1 frame at 60fps
        
        // 3. NOW animate to 1.0
        await MainActor.run {
            // Animate stamp in: fade + scale down
            withAnimation(.easeInOut(duration: 0.6)) {
                showStampImage = true  // Fade in (opacity 0 → 1)
                imageScale = 1.0       // Scale down (1.5 → 1.0)
            }
        }
        // Button is already re-enabled, animation is playing
        
        // 4. SAVE TO DISK (still on main thread, but doesn't block button)
        await MainActor.run {
            stampsManager.userCollection.saveCollectedStamps()
        }
        
        // 5. FIREBASE SYNC (background, best effort)
        Task.detached(priority: .userInitiated) {
            await stampsManager.syncStampCollectionToFirebase(stampId: stamp.id, userId: userId)
        }
        
        // 6. WAIT FOR ANIMATION + PAUSE (0.6s animation + 0.3s pause = 0.9s total)
        try? await Task.sleep(for: .seconds(0.9))
        
        // 7. UPDATE UI ELEMENTS SMOOTHLY (together, at the same time)
        await MainActor.run {
            isAnimatingCollection = false // Unfreeze - allow stats to update now
            
            // Fetch fresh statistics (updates "X people have this stamp")
            Task {
                _ = await stampsManager.fetchStampStatistics(stampId: stamp.id)
            }
            
            // Show memory section with gentle fade
            withAnimation(.easeInOut(duration: 0.6)) {
                showMemorySection = true
            }
        }
    }
    
    private func openInStampbookMaps() {
        #if DEBUG
        print("🗺️ [StampDetailView] openInStampbookMaps called for: \(stamp.name)")
        #endif
        
        // Request the map to center on this stamp
        mapCoordinator.centerOnStamp(stamp, switchTab: true)
        
        // Dismiss the current sheet first if we're in a sheet context
        if !showBackButton {
            #if DEBUG
            print("🗺️ [StampDetailView] Dismissing sheet")
            #endif
            dismiss()
        }
    }
    
    private func calculateCollectionProgress() async {
        // Fetch only the user's collected stamps (same approach as StampsView)
        let collectedStampIds = stampsManager.userCollection.collectedStamps.map { $0.stampId }
        guard !collectedStampIds.isEmpty else {
            // No collected stamps - progress is 0 for all
            await MainActor.run {
                collectionProgress = [:]
                collectionTotals = [:]
            }
            return
        }
        
        // Fetch the actual stamp data (uses cache for efficiency)
        // Include removed stamps so we can filter them ourselves
        let collectedStamps = await stampsManager.fetchStamps(ids: collectedStampIds, includeRemoved: true)
        
        // Calculate progress for each collection this stamp belongs to
        var progress: [String: Int] = [:]
        var totals: [String: Int] = [:]
        
        for collection in stampsManager.collections where stamp.collectionIds.contains(collection.id) {
            // Fetch ALL stamps in this collection to get accurate total
            let allCollectionStamps = await stampsManager.fetchStampsInCollection(collectionId: collection.id)
            
            // IMPORTANT: Only count ACTIVE stamps in both numerator and denominator
            // This prevents showing weird progress like "10/9" when stamps are removed
            // 
            // Example: User collected 10 stamps, you removed 1:
            // - Without filter: Shows 10/9 (numerator > denominator) ❌
            // - With filter: Shows 9/9 (only active stamps) ✅
            
            // Numerator: Count user's collected stamps that are STILL ACTIVE
            let activeCollectedCount = collectedStamps.filter { stamp in
                stamp.collectionIds.contains(collection.id) && stamp.isCurrentlyAvailable
            }.count
            
            // Denominator: Total ACTIVE stamps in collection (what's available NOW)
            let totalActiveCount = allCollectionStamps.count // Already filtered by fetchStampsInCollection
            
            progress[collection.id] = activeCollectedCount
            totals[collection.id] = totalActiveCount
        }
        
        await MainActor.run {
            collectionProgress = progress
            collectionTotals = totals
        }
    }
    
    private func openInAppleMaps() {
        // Create MKMapItem with coordinate and name (iOS 17+ compatible)
        let placemark = MKPlacemark(coordinate: stamp.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = stamp.name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
    
    private func openInGoogleMaps() {
        // Use place name in query for better recognition
        let placeName = stamp.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let address = stamp.address.replacingOccurrences(of: "\n", with: ",").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try with place name and address as query, with coordinates as fallback
        let googleMapsURL = URL(string: "comgooglemaps://?q=\(placeName),\(address)&directionsmode=walking")!
        let googleMapsWebURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(placeName),\(address)&travelmode=walking")!
        
        if UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
        } else {
            // Fallback to web version if Google Maps app not installed
            UIApplication.shared.open(googleMapsWebURL)
        }
    }
    
    // Computed property for stamp collections (extracted to fix type-checking issue)
    private var stampCollections: [Collection] {
        stampsManager.collections.filter { collection in
            stamp.collectionIds.contains(collection.id) && stamp.isCurrentlyAvailable
        }
    }
    
    // Extracted to fix type-checking performance issue
    @ViewBuilder
    private var collectionCountView: some View {
        // Show real collection count from Firebase
        if let stats = stampStats {
            let count = stats.totalCollectors
            Text(count == 1 ? "1 person has this stamp" : "\(count) people have this stamp")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else {
            // Loading or no stats yet
            Text("Loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Copy Image
    
    private func copyStampImage() {
        Task {
            // Try to get the cached image
            var imageToCopy: UIImage?
            
            // Option 1: Firebase Storage image (most common)
            if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty,
               let storagePath = stamp.imageStoragePath {
                
                // Generate the same cache key used by ImageManager when downloading
                let urlHash = abs(imageUrl.hashValue)
                let cacheKey = "\(stamp.id)_\(urlHash).png"
                
                // Try to get from cache (memory or disk)
                imageToCopy = ImageCacheManager.shared.getFullImage(key: cacheKey)
                    ?? ImageManager.shared.loadImage(named: cacheKey)
                
                // If not cached yet, try downloading
                if imageToCopy == nil {
                    do {
                        imageToCopy = try await ImageManager.shared.downloadAndCacheImage(
                            storagePath: storagePath,
                            stampId: stamp.id,
                            imageUrl: imageUrl
                        )
                    } catch {
                        print("⚠️ Failed to download image for copying: \(error.localizedDescription)")
                    }
                }
            }
            // Fallback to bundled image for backward compatibility
            else if !stamp.imageName.isEmpty {
                imageToCopy = UIImage(named: stamp.imageName)
            }
            // Option 3: Placeholder image
            else {
                imageToCopy = UIImage(named: "empty")
            }
            
            // Copy to pasteboard on main thread
            await MainActor.run {
                if let image = imageToCopy {
                    UIPasteboard.general.image = image
                    
                    // Show confirmation feedback
                    withAnimation {
                        showCopyConfirmation = true
                    }
                    
                    // Hide confirmation after 1 second
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                showCopyConfirmation = false
                            }
                        }
                    }
                    
                    print("✅ Stamp image copied to clipboard")
                } else {
                    print("⚠️ No image available to copy")
                }
            }
        }
    }
}

