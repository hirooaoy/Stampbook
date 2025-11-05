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
    let stamp: Stamp
    let userLocation: CLLocation?
    let showBackButton: Bool
    @State private var showMemorySection = false
    @State private var showNotesEditor = false
    @State private var editingNotes = ""
    @State private var stampStats: StampStatistics?
    @State private var userRank: Int? // User's rank for this stamp (1st, 2nd, 3rd collector, etc.)
    @State private var collectionProgress: [String: Int] = [:] // collectionId -> collected count
    @State private var showSuggestEdit = false
    @State private var showAddressOptions = false
    
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
        return distance <= MapView.stampCollectionRadius
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
                        if isCollected {
                            // Show stamp image when collected
                            if let imageUrl = stamp.imageUrl, !imageUrl.isEmpty {
                                // Use CachedImageView with FULL RESOLUTION for detail view (crisp quality)
                                // Progressive loading: shows thumbnail instantly, then upgrades to full-res
                                CachedImageView.stampPhoto(
                                    imageName: stamp.imageName.isEmpty ? nil : stamp.imageName,
                                    storagePath: stamp.imageStoragePath,
                                    stampId: stamp.id,
                                    size: CGSize(width: 300, height: 300),
                                    cornerRadius: 16,
                                    useFullResolution: true
                                )
                                .transition(.scale.combined(with: .opacity))
                            } else if !stamp.imageName.isEmpty {
                                // Fallback to bundled image for backward compatibility
                                Image(stamp.imageName)
                                    .resizable()
                                    .renderingMode(.original)
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 300, height: 300)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                // No image available - show placeholder
                                Image("empty")
                                    .resizable()
                                    .renderingMode(.original)
                                    .scaledToFit()
                                    .frame(width: 300, height: 300)
                            }
                        } else {
                            // Show lock icon when not collected
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.gray.opacity(0.1))
                                .frame(width: 300, height: 300)
                            
                            Image(systemName: "lock.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.gray)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isCollected)
                    .padding(.bottom, 36)
                    
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
                                        
                                        if let rank = userRank {
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
                        .transition(.scale.combined(with: .opacity))
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
                    
                    // TODO: IMPLEMENT NOTES SECTION
                    // Phase 1: Add "Notes from following" section first (show notes from people you follow)
                    // Phase 2: Add "Notes from others" section after (show all public notes)
                    // UI Design:
                    // - Section heading: "Notes from others" or "Notes from following"
                    // - Each note shows: profile thumbnail (40x40 circle) + username + note text
                    // - "See all" button at bottom to navigate to full notes view
                    // - Only visible when signed in
                    // - Divider above section
                    
                    /*
                    // Notes from others section (only show when signed in)
                    if authManager.isSignedIn {
                        // Divider
                        Divider()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 36)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Notes from others")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(stamp.notesFromOthers, id: \.self) { note in
                                    HStack(alignment: .center, spacing: 12) {
                                        // Profile thumbnail
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 40, height: 40)
                                            .overlay(
                                                Image(systemName: "person.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundColor(.gray)
                                            )
                                        
                                        // Note text
                                        Text(note)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            
                            // See all button
                            Button(action: {
                                // TODO: Implement see all notes
                            }) {
                                Text("See all")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 36)
                    }
                    */
                    
                    // Collections section - only show if stamp belongs to at least one collection
                    let stampCollections = stampsManager.collections.filter { collection in
                        stamp.collectionIds.contains(collection.id)
                    }
                    
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
                                    let percentage = collection.totalStamps > 0 ? Double(collectedInCollection) / Double(collection.totalStamps) : 0.0
                                    
                                    CollectionCardView(
                                        name: collection.name,
                                        collectedCount: collectedInCollection,
                                        totalCount: collection.totalStamps,
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
                .padding(.bottom, 48)
                .animation(.spring(response: 0.4, dampingFraction: 1.0), value: isCollected)
            }
            
            // Sticky button at bottom
            VStack(spacing: 0) {
                Divider()
                
                if !authManager.isSignedIn {
                    // Not signed in - show text and native Sign In with Apple button
                    VStack(spacing: 16) {
                        Text("Start your stamp collection")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Button(action: {
                            authManager.signInWithApple()
                        }) {
                            SignInWithAppleButton(.signIn) { _ in }
                                onCompletion: { _ in }
                                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                                .frame(height: 50)
                                .cornerRadius(12)
                                .allowsHitTesting(false) // Disable built-in handler
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                } else if !isCollected {
                    Button(action: {
                        if isWithinRange, let userId = authManager.userId {
                            stampsManager.collectStamp(stamp, userId: userId)
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
            // Show Memory section immediately if stamp is already collected
            if isCollected {
                showMemorySection = true
            }
            
            // Fetch stamp statistics (one-time fetch on appear vs real-time listener: lower cost, simpler code, fresh enough for social proof)
            Task {
                stampStats = await stampsManager.fetchStampStatistics(stampId: stamp.id)
                
                // Load user's rank from cached CollectedStamp first (instant!)
                // Rank = position in collector list (1st, 2nd, 3rd...) - never changes!
                if isCollected, let userId = authManager.userId {
                    // FAST PATH: Try cached rank first
                    if let collectedStamp = stampsManager.userCollection.collectedStamps.first(where: { $0.stampId == stamp.id }),
                       let cachedRank = collectedStamp.userRank {
                        userRank = cachedRank
                    } else {
                        // FALLBACK: Fetch from Firebase (for old stamps collected before caching was added)
                        userRank = await stampsManager.getUserRankForStamp(stampId: stamp.id, userId: userId)
                    }
                }
                
                // Calculate collection progress for all collections this stamp belongs to
                await calculateCollectionProgress()
            }
        }
        .onChange(of: isCollected) { _, newValue in
            if newValue {
                withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                    showMemorySection = true
                }
                
                // Fetch statistics when stamp is collected
                Task {
                    stampStats = await stampsManager.fetchStampStatistics(stampId: stamp.id)
                    
                    // Rank is now set when stamp is collected (cached in CollectedStamp)
                    // Load it from cache immediately
                    if let collectedStamp = stampsManager.userCollection.collectedStamps.first(where: { $0.stampId == stamp.id }),
                       let cachedRank = collectedStamp.userRank {
                        userRank = cachedRank
                    }
                    
                    // Recalculate collection progress when stamp is collected
                    await calculateCollectionProgress()
                }
            } else {
                showMemorySection = false
                userRank = nil
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
            }
            return
        }
        
        // Fetch the actual stamp data (uses cache for efficiency)
        let collectedStamps = await stampsManager.fetchStamps(ids: collectedStampIds)
        
        // Calculate progress for each collection this stamp belongs to
        var progress: [String: Int] = [:]
        for collection in stampsManager.collections where stamp.collectionIds.contains(collection.id) {
            let count = collectedStamps.filter { stamp in
                stamp.collectionIds.contains(collection.id)
            }.count
            progress[collection.id] = count
        }
        
        await MainActor.run {
            collectionProgress = progress
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
}
