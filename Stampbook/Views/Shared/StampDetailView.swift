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
    let stamp: Stamp
    let userLocation: CLLocation?
    let showBackButton: Bool
    @State private var showMemorySection = false
    @State private var showNotesEditor = false
    @State private var editingNotes = ""
    @State private var userRank: Int? // User's rank for this stamp (1st, 2nd, 3rd collector, etc.)
    @State private var collectionProgress: [String: Int] = [:] // collectionId -> collected count
    @State private var collectionTotals: [String: Int] = [:] // collectionId -> total ACTIVE stamps count
    @State private var showSuggestEdit = false
    @State private var showAddressOptions = false
    @State private var showCopyConfirmation = false
    @State private var showInviteCodeSheet = false
    @State private var imageScale: CGFloat = 1.5 // Start larger, shrinks to 1.0 on collection
    @State private var showStampImage = false // Controls stamp image visibility (animated)
    @State private var showLockIcon = true // Controls lock icon visibility (animated)
    @State private var isAnimatingCollection = false // Track if we're in collection animation
    @State private var displayStats: StampStatistics? = nil // Stats to display (frozen during animation)
    
    // Computed property to get live stampStats from StampsManager
    private var stampStats: StampStatistics? {
        // During collection animation, show frozen stats
        if isAnimatingCollection, let frozen = displayStats {
            return frozen
        }
        // Otherwise show live stats
        return stampsManager.stampStatistics[stamp.id]
    }
    
    // Computed property to get user rank from cached CollectedStamp
    // This updates automatically when userCollection changes
    private var cachedUserRank: Int? {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stamp.id })?.userRank
    }
    
    private var isCollected: Bool {
        stampsManager.isCollected(stamp)
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
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stamp.id })?.collectedDate
    }
    
    private var userNotes: String {
        stampsManager.userCollection.collectedStamps
            .first(where: { $0.stampId == stamp.id })?.userNotes ?? ""
    }
    
    private var formattedFullDate: String {
        guard let date = collectedDate else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
    
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
        
        return nil
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
                    
                    // Centered square stamp image with lock icon
                    ZStack {
                        // Lock icon - show when not collected
                        if showLockIcon {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 240, height: 240)
                            
                            Image(systemName: "lock.fill")
                                .font(.system(size: 75))
                                .foregroundColor(.gray)
                        }
                        
                        // Stamp image - always present, but hidden when not collected
                        ZStack {
                            if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                                CachedImageView.stampPhoto(
                                    imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                                    storagePath: stamp.imageStoragePath,
                                    stampId: stamp.id,
                                    size: CGSize(width: 300, height: 300),
                                    cornerRadius: 16,
                                    useFullResolution: true,
                                    imageUrl: imageUrl
                                )
                            } else if !stamp.imageName.isEmpty {
                                Image(stamp.imageName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 300, height: 300)
                            } else {
                                Image("empty")
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(width: 300, height: 300)
                            }
                        }
                        .scaleEffect(imageScale)
                        .opacity(showStampImage ? 1.0 : 0.0)
                        
                        // Copy confirmation checkmark overlay
                        if showCopyConfirmation {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 300, height: 300)
                            
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
                    .frame(width: 300, height: 300)
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Memory section - only visible after collection
                    if isCollected && showMemorySection {
                        VStack(alignment: .leading, spacing: 0) {
                            // Memory heading
                            Text("Memory")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 8)
                            
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
                            if stampsManager.userCollection.collectedStamps.first(where: { $0.stampId == stamp.id }) != nil {
                                // Always show photo gallery (it handles both empty and non-empty states)
                                PhotoGalleryView(
                                    stampId: stamp.id
                                )
                                .padding(.bottom, 16)
                            }
                            
                            // Add notes button
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                        .transition(.opacity)
                    }
                    
                    // Divider
                    if isCollected && showMemorySection {
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
                            
                            ForEach(stampCollections) { collection in
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
                                        completionPercentage: percentage
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
                            showInviteCodeSheet = true
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
            // Triple dot menu - hide for welcome stamp
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
            
            // X button - only shown in sheet mode (no back button)
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
        .presentationDetents([.fraction(0.75), .large])
        .onAppear {
            // Initialize states for already collected stamps
            if isCollected {
                showStampImage = true
                showLockIcon = false
                imageScale = 1.0  // Already collected stamps show at normal size
            }
            
            // Single task to load data sequentially (prevents race conditions)
            Task {
                // 0. Preload stamp image if not collected yet (so it's ready when user taps collect)
                // Don't block - just start downloading in background
                if !isCollected, let storagePath = stamp.imageStoragePath {
                    Task {
                    do {
                        _ = try await ImageManager.shared.downloadAndCacheThumbnail(
                            storagePath: storagePath,
                            stampId: stamp.id,
                            imageUrl: stamp.imageUrl
                        )
                        print("✅ Preloaded stamp image for: \(stamp.name)")
                    } catch {
                        print("⚠️ Failed to preload image: \(error.localizedDescription)")
                    }
                    }
                }
                
                // 1. Always fetch stamp statistics first (needed for "X people have this stamp")
                // Only fetch if cache is stale (older than 5 minutes) or doesn't exist
                if stampStats == nil || stampStats?.isCacheStale() == true {
                    _ = await stampsManager.fetchStampStatistics(stampId: stamp.id)
                }
                
                // 2. Then handle collected-specific logic
                if isCollected {
                    showMemorySection = true
                    
                    // Only fetch user rank if not cached (for old stamps collected before rank caching)
                    // Rank is permanent (your position in collector line), so cache is always valid
                    if cachedUserRank == nil, let userId = authManager.userId {
                        let fetchedRank = await stampsManager.getUserRankForStamp(stampId: stamp.id, userId: userId)
                        userRank = fetchedRank  // Already on MainActor
                    }
                    
                    // Calculate collection progress
                    await calculateCollectionProgress()
                }
            }
        }
        .onChange(of: isCollected) { _, newValue in
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
        .onChange(of: stampsManager.userCollection.collectedStamps.count) { _, _ in
            // Recalculate collection progress whenever the user collects any stamp
            // This ensures the collection counts stay up-to-date even when viewing one stamp
            // while collecting others in the same collection
            if isCollected {
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
        .sheet(isPresented: $showInviteCodeSheet) {
            InviteCodeSheet(isAuthenticated: $authManager.isSignedIn)
                .environmentObject(authManager)
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
        let location = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
        
        // Create MKMapItem with location and name
        let mapItem = MKMapItem(location: location, address: nil)
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
                
                // Extract filename from storage path
                let filename = (storagePath as NSString).lastPathComponent
                
                // Try to get from cache (memory or disk)
                imageToCopy = ImageCacheManager.shared.getFullImage(key: filename)
                    ?? ImageManager.shared.loadImage(named: filename)
                
                // If not cached yet, try downloading
                if imageToCopy == nil {
                    do {
                        imageToCopy = try await ImageManager.shared.downloadAndCacheImage(
                            storagePath: storagePath,
                            stampId: stamp.id
                        )
                    } catch {
                        print("⚠️ Failed to download image for copying: \(error.localizedDescription)")
                    }
                }
            }
            // Option 2: Bundled image (legacy)
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
