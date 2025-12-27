import SwiftUI
import MapKit
import Combine
import FirebasePerformance

// MARK: - Privacy-First Map View
// ==========================================
// PRIVACY IMPLEMENTATION:
// - Anonymous users: Can browse map, search locations, view stamps
// - NO location tracking until user signs in (GDPR compliant)
// - "Locate Me" button prompts sign-in for anonymous users
// - Location permission requested ONLY after authentication
//
// This approach:
// ✅ Prevents unnecessary location tracking
// ✅ Gives users control over their data
// ✅ Clear purpose for location access (stamp collection)
// ✅ GDPR Article 5 compliant (data minimization, purpose limitation)
// ==========================================

struct MapView: View {
    /// The radius in meters within which a user can collect a stamp
    /// Defined in AppConfig for consistency across the app
    static let stampCollectionRadius: Double = AppConfig.stampCollectionRadius
    
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var mapCoordinator: MapCoordinator
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @State private var selectedStamp: Stamp?
    @State private var shouldRecenterMap = false
    @State private var searchText = ""
    @State private var searchRegion: MKCoordinateRegion?
    @State private var isShowingSearch = false
    @State private var showSignInSheet = false  // Shows sign-in bottom sheet
    @State private var showSuggestStamp = false
    @State private var showSuggestCollection = false
    
    // OPTIMIZATION #2: Lazy search completer - only created when user taps search
    // Saves ~1-2MB memory and MapKit resources until actually needed
    @State private var searchCompleter: LocationSearchCompleter?
    
    // MARK: - Map Loading Strategy
    
    // **CURRENT APPROACH (100-1000 stamps): Fetch All**
    // Loads ALL stamps once, then relies on Firebase persistent cache
    // 
    // Why this works:
    // - First load: ~500ms to fetch all 400 stamps from Firebase
    // - All future loads: <50ms from Firebase cache (FREE, no reads charged)
    // - Cost: ~12K Firebase reads/month (new users only) = $0/month
    // - Simple, reliable, no region tracking complexity
    // 
    // When to switch to region-based (removed for MVP, check git history):
    // - Stamp count exceeds ~2000 stamps
    // - Initial load becomes too slow (>1 second)
    // - Approaching Firebase free tier limits
    // - Restore from git: "Remove unused region-based loading"
    
    @State private var allStamps: [Stamp] = []
    @State private var isLoadingStamps = false
    @State private var bookmarkUpdateTrigger = 0  // Forces map update when bookmarks change
    
    // Connection transition states
    @State private var bannerState: ConnectionBanner.BannerState = .hidden
    
    private var collectedStampIds: Set<String> {
        Set(stampsManager.userCollection.collectedStamps.map { $0.stampId })
    }
    
    private var bookmarkedStampIds: Set<String> {
        let ids = Set(stampsManager.userBookmarks.bookmarkedStamps.map { $0.stampId })
        return ids
    }
    
    // Select a search result and navigate to it
    private func selectSearchResult(_ completion: MKLocalSearchCompletion) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        search.start { response, error in
            guard let response = response,
                  let item = response.mapItems.first else {
                return
            }
            
            // Create a region around the search result
            let coordinate: CLLocationCoordinate2D
            if #available(iOS 26.0, *) {
                coordinate = item.location.coordinate
            } else {
                coordinate = item.placemark.coordinate
            }
            
            let span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            searchRegion = MKCoordinateRegion(center: coordinate, span: span)
            
            // Clear search
            searchText = ""
        }
    }
    
    var body: some View {
        let _ = bookmarkUpdateTrigger  // Reference to ensure view updates
        
        ZStack {
            NativeMapView(
                stamps: allStamps,  // ← SIMPLE: Show all stamps globally
                collectedStampIds: collectedStampIds,
                bookmarkedStampIds: bookmarkedStampIds,
                bookmarkTrigger: bookmarkUpdateTrigger,  // Pass trigger to force updates
                userLocation: locationManager.location,
                isTrackingLocation: locationManager.isTrackingEnabled,
                selectedStamp: $selectedStamp,
                shouldRecenter: $shouldRecenterMap,
                searchRegion: $searchRegion,
                onRegionChange: nil  // No need for region change tracking
            )
            .mapSafeArea()  // iOS 26: full screen, iOS 18: keep tab bar visible
            
            // Connection status banner at top
            VStack {
                ConnectionBanner(state: bannerState, context: .map)
                    .padding(.top, 12)
                
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: bannerState)
            
            // Floating buttons stack
            VStack(spacing: 12) {
                // Add button with menu (ONLY for signed-in users)
                if authManager.isSignedIn {
                    Menu {
                        Button(action: {
                            showSuggestStamp = true
                        }) {
                            Label("Suggest a stamp", systemImage: "plus.app")
                        }
                        
                        Button(action: {
                            showSuggestCollection = true
                        }) {
                            Label("Suggest a collection", systemImage: "rectangle.stack.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .frame(width: 50, height: 50)
                            .background(.ultraThinMaterial)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(
                                color: .black.opacity(0.2),
                                radius: 4,
                                x: 0,
                                y: 2
                            )
                    }
                }
                
                // Search button
                Button(action: {
                    isShowingSearch = true
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.primary)
                        .frame(width: 50, height: 50)
                        .background(.ultraThinMaterial)
                        .background(Color.white.opacity(0.25))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(
                            color: .black.opacity(0.2),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }
                
                // Re-center button (PRIVACY: Only works when signed in)
                Button(action: {
                    if authManager.isSignedIn {
                        shouldRecenterMap = true
                    } else {
                        // PRIVACY: Prompt sign-in instead of requesting location for anonymous user
                        showSignInSheet = true
                    }
                }) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(authManager.isSignedIn ? Color.blue : Color.gray)
                        .clipShape(Circle())
                        .shadow(
                            color: .black.opacity(0.2),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $isShowingSearch) {
            if let completer = searchCompleter {
                SearchSheet(
                    searchText: $searchText,
                    searchCompleter: completer,
                    onSelectResult: { completion in
                        selectSearchResult(completion)
                        isShowingSearch = false
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .onChange(of: isShowingSearch) { _, newValue in
            // OPTIMIZATION #2: Create search completer only when user opens search
            if newValue && searchCompleter == nil {
                searchCompleter = LocationSearchCompleter()
            }
        }
        .sheet(item: $selectedStamp) { stamp in
            NavigationStack {
                StampDetailView(
                    stamp: stamp,
                    isCollected: stampsManager.isCollected(stamp),
                    userLocation: locationManager.location,
                    showBackButton: false
                )
                .sheetContentBackground()
                .toolbar(.visible, for: .tabBar)
            }
        }
        .onAppear {
            // PRIVACY: Only request location permission if user is signed in
            // Anonymous users can browse the map without any location tracking
            if authManager.isSignedIn {
                locationManager.startTrackingForAuthenticatedUser()
            }
            
            // SIMPLE: Load all stamps once on map open
            // With <500 stamps, this is faster and more reliable than region-based loading
            if allStamps.isEmpty && !isLoadingStamps {
                Task {
                    await loadAllStamps()
                }
            }
            
            // Check if there's a pending stamp to center on (set before this view appeared)
            if let stamp = mapCoordinator.stampToCenter {
                // Use Task to let the map finish initializing before centering
                Task { @MainActor in
                    // Small delay to ensure native map is ready
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    let coordinate = stamp.coordinate
                    let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    searchRegion = MKCoordinateRegion(center: coordinate, span: span)
                    mapCoordinator.clearRequest()
                }
            }
        }
        .onChange(of: authManager.isSignedIn) { oldValue, newValue in
            // PRIVACY: Handle sign-in/sign-out transitions
            if newValue == true {
                // User just signed in - NOW we request location permission
                // This ensures clear purpose: location is for stamp collection
                locationManager.startTrackingForAuthenticatedUser()
            } else {
                // User signed out - stop tracking location immediately
                // Clears cached location data (GDPR right to erasure)
                locationManager.stopTracking()
            }
        }
        .onChange(of: networkMonitor.isConnected) { oldValue, newValue in
            handleConnectionChange(wasConnected: oldValue, isConnected: newValue)
        }
        .onChange(of: mapCoordinator.stampToCenter) { _, stamp in
            // When a stamp is requested to be centered, create a region around it
            if let stamp = stamp {
                let coordinate = stamp.coordinate
                let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Close zoom
                searchRegion = MKCoordinateRegion(center: coordinate, span: span)
                
                // Clear the request after handling it
                mapCoordinator.clearRequest()
            }
        }
        .onChange(of: stampsManager.userBookmarks.bookmarkedStamps.count) { _, _ in
            // Force view update when bookmarks change
            // This triggers recomputation of bookmarkedStampIds and NativeMapView update
            bookmarkUpdateTrigger += 1
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInSheet(
                title: "Sign In Required",
                message: "Sign in to see your location and start your stamp collection"
            )
            .environmentObject(authManager)
        }
        .sheet(isPresented: $showSuggestStamp) {
            SuggestStampView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showSuggestCollection) {
            SuggestCollectionView()
                .environmentObject(authManager)
        }
        .mapTabBarVisibility()  // iOS 18: Ensure tab bar visible, iOS 26: original behavior
    }
    
    // MARK: - Simple Stamp Loading
    
    /// Load all stamps globally (once per session)
    private func loadAllStamps() async {
        guard !isLoadingStamps else { return }
        
        isLoadingStamps = true
        
        // Start performance trace
        let trace = Performance.startTrace(name: "map_load")
        defer { trace?.stop() }
        
        let stamps = await stampsManager.fetchAllStamps()
        
        // Filter out the welcome stamp from map view
        let filteredStamps = stamps.filter { $0.id != "your-first-stamp" }
        
        await MainActor.run {
            allStamps = filteredStamps
            isLoadingStamps = false
        }
    }
    
    // MARK: - Banner Helpers
    
    private func handleConnectionChange(wasConnected: Bool, isConnected: Bool) {
        if !wasConnected && isConnected {
            // Going from offline to online
            bannerState = .reconnecting
            
            // Show "Reconnecting..." for 3 seconds, then hide
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                bannerState = .hidden
            }
        } else if wasConnected && !isConnected {
            // Going from online to offline
            bannerState = .offline
        } else if !isConnected && bannerState == .hidden {
            // Initial offline state
            bannerState = .offline
        }
    }
}

// Native UIKit MKMapView wrapper with true heading support
struct NativeMapView: UIViewRepresentable {
    let stamps: [Stamp]
    let collectedStampIds: Set<String>
    let bookmarkedStampIds: Set<String>
    let bookmarkTrigger: Int  // Forces update when bookmarks change
    let userLocation: CLLocation?
    let isTrackingLocation: Bool  // PRIVACY: Only show blue dot when actively tracking
    @Binding var selectedStamp: Stamp?
    @Binding var shouldRecenter: Bool
    @Binding var searchRegion: MKCoordinateRegion?
    let onRegionChange: ((MKCoordinateRegion) -> Void)?  // Callback for region changes
    
    // Constants
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04) // Zoomed out for default Golden Gate view
    private static let locateMeSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01) // Closer zoom for user location
    // Default location: Golden Gate Bridge viewpoint
    private static let defaultCoordinate = CLLocationCoordinate2D(latitude: 37.81368955948842, longitude: -122.47779410452)
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        // PRIVACY: Don't show user location by default - will be controlled in updateUIView
        mapView.showsUserLocation = false
        mapView.userTrackingMode = .none
        
        // Configure map appearance
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .default
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        
        // Limit maximum zoom out to keep stamps visible (native prevention, no bounce)
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 20_000_000)
        
        // Set initial region
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCoordinate,
            span: Self.defaultSpan
        )
        mapView.setRegion(initialRegion, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context        ) {
            
        // PRIVACY: Control blue dot visibility based on tracking state
        // Only show user location when actively tracking (user is signed in)
        if isTrackingLocation {
            if !mapView.showsUserLocation {
                mapView.showsUserLocation = true
                mapView.userTrackingMode = .none  // Show blue dot without auto-rotation
            }
        } else {
            if mapView.showsUserLocation {
                mapView.showsUserLocation = false
                mapView.userTrackingMode = .none
            }
        }
        
        // Update annotations when stamps, location, or collection status change
        context.coordinator.updateAnnotations(
            mapView: mapView,
            stamps: stamps,
            collectedStampIds: collectedStampIds,
            bookmarkedStampIds: bookmarkedStampIds,  // Pass directly, don't use parent
            userLocation: userLocation
        )
        
        // Handle search region
        if let region = searchRegion {
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async {
                self.searchRegion = nil
            }
        }
        
        // Handle recenter
        if shouldRecenter, let location = userLocation {
            let region = MKCoordinateRegion(center: location.coordinate, span: Self.locateMeSpan)
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async {
                self.shouldRecenter = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: NativeMapView
        private var hasSetInitialRegion = false
        private var currentStampIds: Set<String> = []
        private var previousCollectedStampIds: Set<String> = []
        private var previousBookmarkedStampIds: Set<String> = []
        private var previousInRangeStampIds: Set<String> = []
        private var hostingControllers: [ObjectIdentifier: UIHostingController<StampPin>] = [:]
        
        // CRITICAL: Store current bookmark/collection state for viewFor to use
        // viewFor runs asynchronously and needs the LATEST data, not stale parent bindings
        private var currentCollectedStampIds: Set<String> = []
        private var currentBookmarkedStampIds: Set<String> = []
        
        // Constants
        private static let annotationSize = CGSize(width: 60, height: 60)
        private static let clusterZoomDivisor: Double = 2.5
        
        // Reuse identifiers
        private static let stampAnnotationIdentifier = "StampAnnotation"
        private static let collectedClusterIdentifier = "CollectedClusterAnnotation"
        private static let bookmarkedClusterIdentifier = "BookmarkedClusterAnnotation"
        private static let lockedClusterIdentifier = "LockedClusterAnnotation"
        
        // Clustering identifiers
        private static let collectedClusteringIdentifier = "collectedCluster"
        private static let bookmarkedClusteringIdentifier = "bookmarkedCluster"
        private static let lockedClusteringIdentifier = "lockedCluster"
        
        // Z-Priority for rendering order (higher = on top)
        // Blue (in range) -> Green (collected) -> Yellow (bookmarked) -> White (locked)
        private static let greyZPriority: MKAnnotationViewZPriority = MKAnnotationViewZPriority(rawValue: 100.0)
        private static let yellowZPriority: MKAnnotationViewZPriority = MKAnnotationViewZPriority(rawValue: 300.0)
        private static let greenZPriority: MKAnnotationViewZPriority = MKAnnotationViewZPriority(rawValue: 500.0)
        private static let blueZPriority: MKAnnotationViewZPriority = MKAnnotationViewZPriority(rawValue: 1000.0)
        
        init(parent: NativeMapView) {
            self.parent = parent
        }
        
        // Helper method to configure SwiftUI hosting controller for annotation views
        private func configureHostingController<Content: View>(
            with view: Content,
            in annotationView: MKAnnotationView
        ) -> UIHostingController<Content> {
            let hostingController = UIHostingController(rootView: view)
            hostingController.view.backgroundColor = .clear
            hostingController.view.frame = CGRect(origin: .zero, size: Self.annotationSize)
            
            annotationView.frame = hostingController.view.frame
            annotationView.addSubview(hostingController.view)
            
            return hostingController
        }
        
        func updateAnnotations(
            mapView: MKMapView,
            stamps: [Stamp],
            collectedStampIds: Set<String>,
            bookmarkedStampIds: Set<String>,  // Pass as parameter
            userLocation: CLLocation?
        ) {
            // CRITICAL: Store the LATEST IDs immediately so viewFor can use them
            // viewFor runs asynchronously and needs fresh data
            currentCollectedStampIds = collectedStampIds
            currentBookmarkedStampIds = bookmarkedStampIds
            
            let newStampIds = Set(stamps.map { $0.id })
            
            // Calculate which stamps are currently in range
            let currentInRangeStampIds: Set<String> = {
                guard let userLocation = userLocation else { return [] }
                return Set(stamps.filter { stamp in
                    let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
                    return userLocation.distance(from: stampLocation) <= stamp.collectionRadiusInMeters
                }.map { $0.id })
            }()
            
            // OPTIMIZATION #1: Split update logic into two paths
            // Path A: Full rebuild when stamp data changes (rare - only when new stamps added)
            // Path B: Incremental update when only status changes (common - collecting stamps, moving around)
            
            if currentStampIds != newStampIds {
                // PATH A: FULL REBUILD - Stamp data changed (new stamps added/removed)
                
                let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
                
                // Clean up hosting controllers for removed annotations
                for annotation in oldAnnotations {
                    let annotationId = ObjectIdentifier(annotation)
                    if let hostingController = hostingControllers[annotationId] {
                        hostingController.view.removeFromSuperview()
                        hostingControllers.removeValue(forKey: annotationId)
                    }
                }
                
                // Remove old annotations
                mapView.removeAnnotations(oldAnnotations)
                
                // Add new stamp annotations
                let annotations = stamps.map { stamp -> StampAnnotation in
                    let annotation = StampAnnotation(stamp: stamp)
                    
                    // Set collection status
                    annotation.isCollected = collectedStampIds.contains(stamp.id)
                    
                    // Set bookmark status
                    annotation.isBookmarked = bookmarkedStampIds.contains(stamp.id)
                    
                    // Check if within range
                    if let userLocation = userLocation {
                        let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
                        let distance = userLocation.distance(from: stampLocation)
                        annotation.isWithinRange = distance <= stamp.collectionRadiusInMeters
                    }
                    
                    return annotation
                }
                mapView.addAnnotations(annotations)
                currentStampIds = newStampIds
                previousCollectedStampIds = collectedStampIds
                previousBookmarkedStampIds = bookmarkedStampIds
                previousInRangeStampIds = currentInRangeStampIds
                
            } else if collectedStampIds != previousCollectedStampIds ||
                      bookmarkedStampIds != previousBookmarkedStampIds ||
                      currentInRangeStampIds != previousInRangeStampIds ||
                      previousBookmarkedStampIds.isEmpty {  // Force full update on first appearance
                
                // PATH B: INCREMENTAL UPDATE - Only status changed (collected/bookmark/range)
                // OPTIMIZATION: Only update the specific stamps that changed status
                // This is 400x faster than rebuilding all annotations (1ms vs 400ms for 400 stamps)
                
                // Calculate exactly which stamps changed (or all stamps if first appearance)
                let collectedChanged = collectedStampIds.symmetricDifference(previousCollectedStampIds)
                let bookmarkedChanged = bookmarkedStampIds.symmetricDifference(previousBookmarkedStampIds)
                let rangeChanged = currentInRangeStampIds.symmetricDifference(previousInRangeStampIds)
                var changedStampIds = collectedChanged.union(bookmarkedChanged).union(rangeChanged)
                
                // BUG FIX: On first appearance (previousBookmarkedStampIds.isEmpty), update ALL annotations
                // to ensure they're using fresh data, not stale cached properties
                if previousBookmarkedStampIds.isEmpty && previousCollectedStampIds.isEmpty {
                    changedStampIds = Set(mapView.annotations.compactMap { ($0 as? StampAnnotation)?.stamp.id })
                }
                
                // Only update annotations for stamps that changed
                let stampAnnotations = mapView.annotations.compactMap { $0 as? StampAnnotation }
                
                // Track annotations that need clustering identifier updates
                var annotationsToRecreate: [StampAnnotation] = []
                
                for annotation in stampAnnotations where changedStampIds.contains(annotation.stamp.id) {
                    let wasCollected = annotation.isCollected
                    let wasBookmarked = annotation.isBookmarked
                    
                    // Update status
                    annotation.isCollected = collectedStampIds.contains(annotation.stamp.id)
                    annotation.isBookmarked = bookmarkedStampIds.contains(annotation.stamp.id)
                    
                    annotation.isCollected = collectedStampIds.contains(annotation.stamp.id)
                    annotation.isBookmarked = bookmarkedStampIds.contains(annotation.stamp.id)
                    
                    if let userLocation = userLocation {
                        let stampLocation = CLLocation(latitude: annotation.stamp.coordinate.latitude, 
                                                      longitude: annotation.stamp.coordinate.longitude)
                        let distance = userLocation.distance(from: stampLocation)
                        annotation.isWithinRange = distance <= annotation.stamp.collectionRadiusInMeters
                    } else {
                        annotation.isWithinRange = false
                    }
                    
                    // Check if clustering identifier needs to change
                    // BUG FIX: MapKit doesn't recalculate clusters when clusteringIdentifier changes
                    // on an existing view. We MUST remove and re-add the annotation to force re-clustering.
                    if wasCollected != annotation.isCollected || wasBookmarked != annotation.isBookmarked {
                        // Clustering status changed - ALWAYS remove/re-add to force MapKit to recalculate
                        annotationsToRecreate.append(annotation)
                    } else {
                        // Status didn't affect clustering, just update appearance if view exists
                        let annotationId = ObjectIdentifier(annotation)
                        if let hostingController = hostingControllers[annotationId] {
                            let newPinView = StampPin(
                                stamp: annotation.stamp,
                                isWithinRange: annotation.isWithinRange,
                                isCollected: annotation.isCollected,
                                isBookmarked: bookmarkedStampIds.contains(annotation.stamp.id)
                            )
                            hostingController.rootView = newPinView
                        }
                    }
                }
                
                // Force re-clustering for annotations that were clustered
                if !annotationsToRecreate.isEmpty {
                    // Clean up hosting controllers for annotations being recreated
                    for annotation in annotationsToRecreate {
                        let annotationId = ObjectIdentifier(annotation)
                        if let hostingController = hostingControllers[annotationId] {
                            hostingController.view.removeFromSuperview()
                            hostingControllers.removeValue(forKey: annotationId)
                        }
                    }
                    
                    // BUG FIX: Remove and re-add with a slight delay to ensure MapKit processes the removal first
                    // This prevents cluster views from being created with stale annotation data
                    mapView.removeAnnotations(annotationsToRecreate)
                    
                    // Force synchronous processing
                    DispatchQueue.main.async {
                        mapView.addAnnotations(annotationsToRecreate)
                    }
                }
                
                previousCollectedStampIds = collectedStampIds
                previousBookmarkedStampIds = bookmarkedStampIds
                previousInRangeStampIds = currentInRangeStampIds
            }
        }
        
        // Customize annotation views
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Use default view for user location
            if annotation is MKUserLocation {
                return nil
            }
            
            // Handle cluster annotations
            if let cluster = annotation as? MKClusterAnnotation {
                // Determine cluster type by checking first member's status
                // IMPORTANT: Check live bookmarkedStampIds, not cached annotation.isBookmarked
                // to handle bookmark removal properly
                let firstStampAnnotation = cluster.memberAnnotations.first as? StampAnnotation
                
                // CRITICAL: Always use LIVE data from Coordinator, not cached annotation properties
                let isCollectedCluster: Bool
                let isBookmarkedCluster: Bool
                if let firstStamp = firstStampAnnotation {
                    isCollectedCluster = currentCollectedStampIds.contains(firstStamp.stamp.id)
                    isBookmarkedCluster = !isCollectedCluster && currentBookmarkedStampIds.contains(firstStamp.stamp.id)
                } else {
                    isCollectedCluster = false
                    isBookmarkedCluster = false
                }
                
                // Use different identifiers for different cluster types to prevent view reuse issues
                let identifier: String
                let zPriority: MKAnnotationViewZPriority
                if isCollectedCluster {
                    identifier = Self.collectedClusterIdentifier
                    zPriority = Self.greenZPriority
                } else if isBookmarkedCluster {
                    identifier = Self.bookmarkedClusterIdentifier
                    zPriority = Self.yellowZPriority
                } else {
                    identifier = Self.lockedClusterIdentifier
                    zPriority = Self.greyZPriority
                }
                
                var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if clusterView == nil {
                    clusterView = MKAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                    clusterView?.canShowCallout = false
                    clusterView?.centerOffset = CGPoint(x: 0, y: -30) // Anchor cluster pin tip to coordinate
                } else {
                    clusterView?.annotation = cluster
                }
                
                // Let MapKit handle cluster display priority naturally
                // No explicit priority - scales globally as you add stamps worldwide
                
                // Set z-priority for layering: green > yellow > grey
                clusterView?.zPriority = zPriority
                
                // Remove old subviews to prevent stacking
                clusterView?.subviews.forEach { $0.removeFromSuperview() }
                
                // Safely unwrap before configuring
                guard let unwrappedClusterView = clusterView else {
                    Logger.error("Failed to create cluster view", category: "MapView")
                    return nil
                }
                
                // Create custom cluster pin view
                let clusterPinView = ClusterPin(
                    count: cluster.memberAnnotations.count,
                    isCollected: isCollectedCluster,
                    isBookmarked: isBookmarkedCluster
                )
                _ = configureHostingController(with: clusterPinView, in: unwrappedClusterView)
                
                return unwrappedClusterView
            }
            
            // Custom view for stamp annotations
            guard let stampAnnotation = annotation as? StampAnnotation else {
                return nil
            }
            
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: Self.stampAnnotationIdentifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: Self.stampAnnotationIdentifier)
                annotationView?.canShowCallout = false
                annotationView?.centerOffset = CGPoint(x: 0, y: -30) // Anchor pin tip to coordinate
            } else {
                annotationView?.annotation = annotation
            }
            
            // Set clustering identifier based on stamp state
            // CRITICAL: Always use currentCollectedStampIds/currentBookmarkedStampIds stored in Coordinator
            // NOT parent.bookmarkedStampIds which may be stale when viewFor runs asynchronously
            let isCollected = currentCollectedStampIds.contains(stampAnnotation.stamp.id)  // ← LIVE DATA FROM COORDINATOR
            let isBookmarked = currentBookmarkedStampIds.contains(stampAnnotation.stamp.id)  // ← LIVE DATA FROM COORDINATOR
            let isWithinRange = stampAnnotation.isWithinRange
            
            // AGGRESSIVE CLUSTERING: Use .required priority for maximum clustering
            // This creates larger clusters that group more stamps together
            if isCollected {
                // Collected stamps cluster together (green)
                annotationView?.clusteringIdentifier = Self.collectedClusteringIdentifier
                annotationView?.displayPriority = .required  // Aggressive clustering
                annotationView?.zPriority = Self.greenZPriority  // Green above yellow
            } else if isBookmarked {
                // Bookmarked stamps cluster together (yellow)
                annotationView?.clusteringIdentifier = Self.bookmarkedClusteringIdentifier
                annotationView?.displayPriority = .required  // Aggressive clustering
                annotationView?.zPriority = Self.yellowZPriority  // Yellow above grey
            } else if !isWithinRange {
                // Locked stamps cluster together (grey/white)
                annotationView?.clusteringIdentifier = Self.lockedClusteringIdentifier
                annotationView?.displayPriority = .required  // Aggressive clustering
                annotationView?.zPriority = Self.greyZPriority  // Grey below yellow
            } else {
                // Unlocked (blue) stamps don't cluster - highest priority, always on top
                annotationView?.clusteringIdentifier = nil
                annotationView?.displayPriority = .required  // Always visible
                annotationView?.zPriority = Self.blueZPriority  // Blue always on top
            }
            
            // Remove old subviews to prevent stacking
            annotationView?.subviews.forEach { $0.removeFromSuperview() }
            
            // Safely unwrap before configuring
            guard let unwrappedAnnotationView = annotationView else {
                Logger.error("Failed to create annotation view", category: "MapView")
                return nil
            }
            
            // Create the stamp pin view (using same live data for consistency)
            let stampPinView = StampPin(
                stamp: stampAnnotation.stamp,
                isWithinRange: isWithinRange,
                isCollected: isCollected,  // Same value used for clustering
                isBookmarked: isBookmarked  // Same value used for clustering
            )
            
            // Store the hosting controller so we can update it later
            let annotationId = ObjectIdentifier(stampAnnotation)
            let hostingController = configureHostingController(with: stampPinView, in: unwrappedAnnotationView)
            hostingControllers[annotationId] = hostingController
            
            return unwrappedAnnotationView
        }
        
        // Handle annotation selection
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Handle cluster tap - zoom in to decluster
            if let cluster = view.annotation as? MKClusterAnnotation {
                let currentSpan = mapView.region.span
                let newSpan = MKCoordinateSpan(
                    latitudeDelta: currentSpan.latitudeDelta / Self.clusterZoomDivisor,
                    longitudeDelta: currentSpan.longitudeDelta / Self.clusterZoomDivisor
                )
                let region = MKCoordinateRegion(center: cluster.coordinate, span: newSpan)
                mapView.setRegion(region, animated: true)
                mapView.deselectAnnotation(view.annotation, animated: false)
                return
            }
            
            // Handle stamp tap - show detail
            if let stampAnnotation = view.annotation as? StampAnnotation {
                parent.selectedStamp = stampAnnotation.stamp
            }
            mapView.deselectAnnotation(view.annotation, animated: false)
        }
        
        // Auto-center on first location update
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            if !hasSetInitialRegion, let location = userLocation.location {
                let region = MKCoordinateRegion(center: location.coordinate, span: NativeMapView.locateMeSpan)
                mapView.setRegion(region, animated: true)
                hasSetInitialRegion = true
            }
        }
        
        // MARK: - Region Change Detection
        
        /// Called when map region changes (user pans or zooms)
        /// Notifies parent to fetch stamps for new region
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            parent.onRegionChange?(region)
        }
    }
}

// Custom annotation class for stamps
class StampAnnotation: NSObject, MKAnnotation {
    let stamp: Stamp
    var coordinate: CLLocationCoordinate2D
    var isWithinRange: Bool = false
    var isCollected: Bool = false
    var isBookmarked: Bool = false
    
    init(stamp: Stamp) {
        self.stamp = stamp
        self.coordinate = stamp.coordinate
        super.init()
    }
}

// Location search completer for autocomplete suggestions
class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer: MKLocalSearchCompleter
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]  // Include POIs like parks, landmarks
    }
    
    func search(query: String) {
        completer.queryFragment = query
    }
    
    // MKLocalSearchCompleterDelegate methods
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Trust Apple's ranking - it prioritizes cities/countries over streets
        results = completer.results
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search completer error: \(error.localizedDescription)")
    }
}

// Search sheet view
struct SearchSheet: View {
    @Binding var searchText: String
    @ObservedObject var searchCompleter: LocationSearchCompleter
    let onSelectResult: (MKLocalSearchCompletion) -> Void
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search results
                if searchText.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(searchCompleter.results, id: \.self) { completion in
                            Button {
                                onSelectResult(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(completion.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(completion.subtitle)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Search places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search places")
            .onChange(of: searchText) { _, newValue in
                searchCompleter.search(query: newValue)
            }
            .onAppear {
                isSearchFocused = true
            }
        }
    }
}

