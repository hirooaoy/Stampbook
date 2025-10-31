import SwiftUI
import MapKit
import Combine

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
    static let stampCollectionRadius: Double = 100 // 100m for production
    
    @StateObject private var locationManager = LocationManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var searchCompleter = LocationSearchCompleter()
    @EnvironmentObject var stampsManager: StampsManager
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedStamp: Stamp?
    @State private var shouldRecenterMap = false
    @State private var searchText = ""
    @State private var searchRegion: MKCoordinateRegion?
    @State private var isShowingSearch = false
    @State private var showSignInSheet = false  // Shows sign-in bottom sheet
    
    // LAZY LOADING: Only stamps visible in current region
    @State private var visibleStamps: [Stamp] = []
    @State private var isLoadingStamps = false
    @State private var currentMapRegion: MKCoordinateRegion?
    
    // SMART CACHING: Cache fetched regions to avoid redundant queries
    @State private var regionCache: [CachedRegion] = []
    private let maxCachedRegions = 10 // Light caching - keeps map responsive
    private let cacheExpirationSeconds: TimeInterval = 180 // 3 minutes
    
    // Connection transition states
    @State private var bannerState: BannerState = .hidden
    
    /// Cached region data
    struct CachedRegion {
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
        let stamps: [Stamp]
        let precision: Int
        let fetchedAt: Date
        
        /// Check if this cached region covers the target region
        func covers(_ region: MKCoordinateRegion, targetPrecision: Int) -> Bool {
            // Only use cache if precision matches or cached precision is lower (broader search)
            guard precision <= targetPrecision else { return false }
            
            // Check if the cached region fully contains the target region
            let latMin = center.latitude - span.latitudeDelta / 2
            let latMax = center.latitude + span.latitudeDelta / 2
            let lonMin = center.longitude - span.longitudeDelta / 2
            let lonMax = center.longitude + span.longitudeDelta / 2
            
            let targetLatMin = region.center.latitude - region.span.latitudeDelta / 2
            let targetLatMax = region.center.latitude + region.span.latitudeDelta / 2
            let targetLonMin = region.center.longitude - region.span.longitudeDelta / 2
            let targetLonMax = region.center.longitude + region.span.longitudeDelta / 2
            
            return targetLatMin >= latMin && targetLatMax <= latMax &&
                   targetLonMin >= lonMin && targetLonMax <= lonMax
        }
        
        /// Check if cache is still valid (not expired)
        func isValid() -> Bool {
            return Date().timeIntervalSince(fetchedAt) < 180 // 3 minutes
        }
    }
    
    enum BannerState {
        case hidden
        case offline
        case reconnecting
    }
    
    private var collectedStampIds: Set<String> {
        Set(stampsManager.userCollection.collectedStamps.map { $0.stampId })
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
        ZStack {
            NativeMapView(
                stamps: visibleStamps,  // ← LAZY LOADING: Pass only visible stamps
                collectedStampIds: collectedStampIds,
                userLocation: locationManager.location,
                isTrackingLocation: locationManager.isTrackingEnabled,
                selectedStamp: $selectedStamp,
                shouldRecenter: $shouldRecenterMap,
                searchRegion: $searchRegion,
                onRegionChange: { newRegion in
                    handleRegionChange(newRegion)
                }
            )
            .ignoresSafeArea()
            
            // Connection status banner at top
            VStack {
                if bannerState != .hidden {
                    HStack(alignment: .center, spacing: 10) {
                        // Icon on left (vertically centered)
                        bannerIcon
                            .font(.title3)
                            .foregroundColor(bannerIconColor)
                        
                        // Content on right (left-aligned)
                        VStack(alignment: .leading, spacing: 2) {
                            // Title
                            Text(bannerState == .offline ? "Offline" : "Reconnecting...")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            // Subtitle (only shows when offline)
                            if bannerState == .offline {
                                Text("You can still collect stamps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .background(bannerBackgroundColor)
                    .clipShape(Capsule())
                    .shadow(
                        color: .black.opacity(0.15),
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: bannerState)
            
            // Floating buttons stack
            VStack(spacing: 12) {
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
            SearchSheet(
                searchText: $searchText,
                searchCompleter: searchCompleter,
                onSelectResult: { completion in
                    selectSearchResult(completion)
                    isShowingSearch = false
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedStamp) { stamp in
            NavigationStack {
                StampDetailView(
                    stamp: stamp,
                    userLocation: locationManager.location,
                    showBackButton: false
                )
            }
        }
        .onAppear {
            // PRIVACY: Only request location permission if user is signed in
            // Anonymous users can browse the map without any location tracking
            if authManager.isSignedIn {
                locationManager.startTrackingForAuthenticatedUser()
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
        .sheet(isPresented: $showSignInSheet) {
            SignInSheet(
                title: "Sign In Required",
                message: "Sign in to see your location and start your stamp collection"
            )
            .environmentObject(authManager)
        }
    }
    
    // MARK: - Banner Helpers
    
    private var bannerIcon: Image {
        switch bannerState {
        case .offline:
            return Image(systemName: "wifi.slash")
        case .reconnecting:
            return Image(systemName: "wifi")
        case .hidden:
            return Image(systemName: "wifi")
        }
    }
    
    private var bannerIconColor: Color {
        switch bannerState {
        case .offline:
            return .orange
        case .reconnecting:
            return .green
        case .hidden:
            return .primary
        }
    }
    
    private var bannerText: String {
        switch bannerState {
        case .offline:
            return "Offline • You can still collect stamps"
        case .reconnecting:
            return "Reconnecting..."
        case .hidden:
            return ""
        }
    }
    
    private var bannerBackgroundColor: Color {
        switch bannerState {
        case .offline:
            return Color.yellow.opacity(0.2)
        case .reconnecting:
            return Color.green.opacity(0.15)
        case .hidden:
            return Color.clear
        }
    }
    
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
    
    // MARK: - Lazy Loading (Region-Based Queries)
    
    /// Handle map region changes with debouncing
    /// Fetches stamps only for visible region
    private func handleRegionChange(_ newRegion: MKCoordinateRegion) {
        // Debounce: Only update if region changed significantly
        guard shouldFetchForRegion(newRegion) else { return }
        
        currentMapRegion = newRegion
        
        Task {
            await loadStampsForRegion(newRegion)
            
            // DISABLED: Aggressive prefetching made map feel less responsive
            // Only cache what user actively views for better performance
            // await prefetchAdjacentRegions(newRegion)
        }
    }
    
    /// Check if we should fetch stamps for this region
    /// Prevents excessive queries on small pan/zoom changes
    private func shouldFetchForRegion(_ newRegion: MKCoordinateRegion) -> Bool {
        guard let currentRegion = currentMapRegion else {
            return true // First load
        }
        
        // Only fetch if moved significantly (>20% of span)
        let latDelta = abs(newRegion.center.latitude - currentRegion.center.latitude)
        let lonDelta = abs(newRegion.center.longitude - currentRegion.center.longitude)
        
        let significantLatChange = latDelta > (currentRegion.span.latitudeDelta * 0.2)
        let significantLonChange = lonDelta > (currentRegion.span.longitudeDelta * 0.2)
        
        // Also fetch if zoom changed significantly
        let zoomChanged = abs(newRegion.span.latitudeDelta - currentRegion.span.latitudeDelta) > (currentRegion.span.latitudeDelta * 0.3)
        
        return significantLatChange || significantLonChange || zoomChanged
    }
    
    /// Calculate optimal geohash precision based on zoom level
    /// - Returns appropriate precision for current zoom level
    /// - Stamps appear/disappear as you pan for responsive feel
    private func calculateGeohashPrecision(for region: MKCoordinateRegion) -> Int {
        let latSpan = region.span.latitudeDelta
        
        // Geohash precision guide:
        // 1 = ±2,500km (whole world)
        // 2 = ±630km (country)
        // 3 = ±78km (~48 miles) - covers entire metro areas
        // 4 = ±20km (~12 miles) - neighborhood
        // 5 = ±2.4km (~1.5 miles) - street
        // 6 = ±610m (~0.4 miles) - block
        
        switch latSpan {
        case 100...:
            return 1  // Whole world view
        case 10..<100:
            return 2  // Very zoomed out (whole country/region)
        case 2..<10:
            return 3  // City level - load metro area
        case 0.5..<2:
            return 4  // Neighborhood - responsive loading
        case 0.1..<0.5:
            return 5  // Street level - precise area
        case 0.02..<0.1:
            return 5  // Block level
        default:
            return 4  // Very zoomed in - broader to ensure stamps visible
        }
    }
    
    /// Fetch stamps for visible region using geohash
    /// Accumulates stamps - once loaded, they stay visible (no disappearing)
    private func loadStampsForRegion(_ region: MKCoordinateRegion) async {
        guard !isLoadingStamps else { return }
        
        // Dynamic precision based on zoom level
        let precision = calculateGeohashPrecision(for: region)
        
        // CHECK CACHE FIRST: See if we already have data for this region
        if let cachedRegion = findCachedRegion(for: region, precision: precision) {
            #if DEBUG
            print("💾 [MapView] Cache HIT: Using cached data for region (precision: \(cachedRegion.precision))")
            #endif
            
            // ACCUMULATE: Merge cached stamps with existing visible stamps
            await MainActor.run {
                let existingIds = Set(visibleStamps.map { $0.id })
                let newStamps = cachedRegion.stamps.filter { !existingIds.contains($0.id) }
                if !newStamps.isEmpty {
                    visibleStamps.append(contentsOf: newStamps)
                    #if DEBUG
                    print("➕ [MapView] Added \(newStamps.count) new stamps (total: \(visibleStamps.count))")
                    #endif
                }
            }
            return
        }
        
        // CACHE MISS: Fetch from Firestore
        isLoadingStamps = true
        
        #if DEBUG
        let startTime = Date()
        print("🗺️ [MapView] Cache MISS: Fetching stamps for region (span: \(region.span.latitudeDelta), precision: \(precision))")
        #endif
        
        // Fetch stamps in this region
        let stamps = await stampsManager.fetchStampsInRegion(region: region, precision: precision)
        
        #if DEBUG
        let duration = Date().timeIntervalSince(startTime)
        print("✅ [MapView] Loaded \(stamps.count) stamps in \(String(format: "%.2f", duration))s")
        #endif
        
        // Add to cache
        let cachedRegion = CachedRegion(
            center: region.center,
            span: region.span,
            stamps: stamps,
            precision: precision,
            fetchedAt: Date()
        )
        
        await MainActor.run {
            // Add to cache and trim if needed
            regionCache.append(cachedRegion)
            if regionCache.count > maxCachedRegions {
                // Remove oldest cached region
                regionCache.removeFirst()
            }
            
            // ACCUMULATE: Merge new stamps with existing visible stamps
            let existingIds = Set(visibleStamps.map { $0.id })
            let newStamps = stamps.filter { !existingIds.contains($0.id) }
            visibleStamps.append(contentsOf: newStamps)
            
            #if DEBUG
            print("➕ [MapView] Added \(newStamps.count) new stamps (total: \(visibleStamps.count))")
            #endif
            
            isLoadingStamps = false
        }
    }
    
    /// Find a cached region that covers the target region
    private func findCachedRegion(for region: MKCoordinateRegion, precision: Int) -> CachedRegion? {
        // Search cache in reverse order (most recent first)
        for cached in regionCache.reversed() {
            if cached.isValid() && cached.covers(region, targetPrecision: precision) {
                return cached
            }
        }
        return nil
    }
    
    /// Filter stamps to only include those within the visible region
    private func filterStampsInRegion(_ stamps: [Stamp], region: MKCoordinateRegion) -> [Stamp] {
        let latMin = region.center.latitude - region.span.latitudeDelta / 2
        let latMax = region.center.latitude + region.span.latitudeDelta / 2
        let lonMin = region.center.longitude - region.span.longitudeDelta / 2
        let lonMax = region.center.longitude + region.span.longitudeDelta / 2
        
        return stamps.filter { stamp in
            stamp.coordinate.latitude >= latMin &&
            stamp.coordinate.latitude <= latMax &&
            stamp.coordinate.longitude >= lonMin &&
            stamp.coordinate.longitude <= lonMax
        }
    }
    
    /// Prefetch adjacent regions in the background for smoother panning
    /// Only prefetches regions that aren't already cached
    private func prefetchAdjacentRegions(_ currentRegion: MKCoordinateRegion) async {
        // Wait a bit to ensure user has stopped moving
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Create 4 adjacent regions (north, south, east, west)
        let adjacentRegions = [
            // North
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: currentRegion.center.latitude + currentRegion.span.latitudeDelta * 0.8,
                    longitude: currentRegion.center.longitude
                ),
                span: currentRegion.span
            ),
            // South
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: currentRegion.center.latitude - currentRegion.span.latitudeDelta * 0.8,
                    longitude: currentRegion.center.longitude
                ),
                span: currentRegion.span
            ),
            // East
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: currentRegion.center.latitude,
                    longitude: currentRegion.center.longitude + currentRegion.span.longitudeDelta * 0.8
                ),
                span: currentRegion.span
            ),
            // West
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: currentRegion.center.latitude,
                    longitude: currentRegion.center.longitude - currentRegion.span.longitudeDelta * 0.8
                ),
                span: currentRegion.span
            )
        ]
        
        let precision = calculateGeohashPrecision(for: currentRegion)
        
        // Prefetch regions that aren't already cached
        for region in adjacentRegions {
            // Skip if already cached
            if findCachedRegion(for: region, precision: precision) != nil {
                continue
            }
            
            #if DEBUG
            print("🔮 [MapView] Prefetching adjacent region...")
            #endif
            
            // Fetch and cache in background
            let stamps = await stampsManager.fetchStampsInRegion(region: region, precision: precision)
            
            let cachedRegion = CachedRegion(
                center: region.center,
                span: region.span,
                stamps: stamps,
                precision: precision,
                fetchedAt: Date()
            )
            
            await MainActor.run {
                regionCache.append(cachedRegion)
                if regionCache.count > maxCachedRegions {
                    regionCache.removeFirst()
                }
            }
        }
        
        #if DEBUG
        print("✅ [MapView] Prefetch complete (\(regionCache.count) cached regions)")
        #endif
    }
}

// Native UIKit MKMapView wrapper with true heading support
struct NativeMapView: UIViewRepresentable {
    let stamps: [Stamp]
    let collectedStampIds: Set<String>
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
        
        // Set initial region
        let initialRegion = MKCoordinateRegion(
            center: Self.defaultCoordinate,
            span: Self.defaultSpan
        )
        mapView.setRegion(initialRegion, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
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
        context.coordinator.updateAnnotations(mapView: mapView, stamps: stamps, collectedStampIds: collectedStampIds, userLocation: userLocation)
        
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
        private var previousInRangeStampIds: Set<String> = []
        private var hostingControllers: [ObjectIdentifier: UIHostingController<StampPin>] = [:]
        
        // Constants
        private static let annotationSize = CGSize(width: 60, height: 60)
        private static let clusterZoomDivisor: Double = 2.5
        
        // Reuse identifiers
        private static let stampAnnotationIdentifier = "StampAnnotation"
        private static let collectedClusterIdentifier = "CollectedClusterAnnotation"
        private static let lockedClusterIdentifier = "LockedClusterAnnotation"
        
        // Clustering identifiers
        private static let collectedClusteringIdentifier = "collectedCluster"
        private static let lockedClusteringIdentifier = "lockedCluster"
        
        // Z-Priority for rendering order (higher = on top)
        private static let greyZPriority: MKAnnotationViewZPriority = MKAnnotationViewZPriority(rawValue: 100.0)
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
        
        func updateAnnotations(mapView: MKMapView, stamps: [Stamp], collectedStampIds: Set<String>, userLocation: CLLocation?) {
            let newStampIds = Set(stamps.map { $0.id })
            
            // Calculate which stamps are currently in range
            let currentInRangeStampIds: Set<String> = {
                guard let userLocation = userLocation else { return [] }
                return Set(stamps.filter { stamp in
                    let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
                    return userLocation.distance(from: stampLocation) <= MapView.stampCollectionRadius
                }.map { $0.id })
            }()
            
            // Recreate annotations if stamps data, collection status, or range status changed
            if currentStampIds != newStampIds || 
               collectedStampIds != previousCollectedStampIds ||
               currentInRangeStampIds != previousInRangeStampIds {
                // 🔧 FIX: Clean up hosting controllers for removed annotations to prevent memory leaks
                let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
                
                // Remove hosting controllers for annotations being removed
                for annotation in oldAnnotations {
                    let annotationId = ObjectIdentifier(annotation)
                    if let hostingController = hostingControllers[annotationId] {
                        // Remove view from superview and release controller
                        hostingController.view.removeFromSuperview()
                        hostingControllers.removeValue(forKey: annotationId)
                    }
                }
                
                // Remove old annotations
                mapView.removeAnnotations(oldAnnotations)
                
                // Add stamp annotations
                let annotations = stamps.map { stamp -> StampAnnotation in
                    let annotation = StampAnnotation(stamp: stamp)
                    
                    // Set collection status
                    annotation.isCollected = collectedStampIds.contains(stamp.id)
                    
                    // Check if within range
                    if let userLocation = userLocation {
                        let stampLocation = CLLocation(latitude: stamp.coordinate.latitude, longitude: stamp.coordinate.longitude)
                        let distance = userLocation.distance(from: stampLocation)
                        annotation.isWithinRange = distance <= MapView.stampCollectionRadius
                    }
                    
                    return annotation
                }
                mapView.addAnnotations(annotations)
                currentStampIds = newStampIds
                previousCollectedStampIds = collectedStampIds
                previousInRangeStampIds = currentInRangeStampIds
            } else {
                // Update status and refresh views if needed
                let stampAnnotations = mapView.annotations.compactMap { $0 as? StampAnnotation }
                
                for annotation in stampAnnotations {
                    let wasWithinRange = annotation.isWithinRange
                    let wasCollected = annotation.isCollected
                    
                    if let userLocation = userLocation {
                        let stampLocation = CLLocation(latitude: annotation.stamp.coordinate.latitude, longitude: annotation.stamp.coordinate.longitude)
                        let distance = userLocation.distance(from: stampLocation)
                        annotation.isWithinRange = distance <= MapView.stampCollectionRadius
                    } else {
                        annotation.isWithinRange = false
                    }
                    
                    // Update collection status
                    annotation.isCollected = collectedStampIds.contains(annotation.stamp.id)
                    
                    // If status changed, update the hosting controller directly
                    if wasWithinRange != annotation.isWithinRange || wasCollected != annotation.isCollected {
                        let annotationId = ObjectIdentifier(annotation)
                        if let hostingController = hostingControllers[annotationId] {
                            // Update the SwiftUI view directly - no remove/re-add needed!
                            let newPinView = StampPin(
                                stamp: annotation.stamp,
                                isWithinRange: annotation.isWithinRange,
                                isCollected: annotation.isCollected
                            )
                            hostingController.rootView = newPinView
                        }
                    }
                }
                
                // Update previous state
                previousCollectedStampIds = collectedStampIds
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
                // Determine cluster type by checking first member's collection status
                // Since we use separate identifiers (collectedCluster/lockedCluster), all members are the same type
                let firstStampAnnotation = cluster.memberAnnotations.first as? StampAnnotation
                let isCollectedCluster = firstStampAnnotation?.isCollected ?? false
                
                // Use different identifiers for different cluster types to prevent view reuse issues
                let identifier = isCollectedCluster ? Self.collectedClusterIdentifier : Self.lockedClusterIdentifier
                var clusterView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if clusterView == nil {
                    clusterView = MKAnnotationView(annotation: cluster, reuseIdentifier: identifier)
                    clusterView?.canShowCallout = false
                    clusterView?.centerOffset = CGPoint(x: 0, y: -30) // Anchor cluster pin tip to coordinate
                } else {
                    clusterView?.annotation = cluster
                }
                
                // Set display priority to required so clusters never get culled
                // This prevents disappearing when many annotations are visible at medium zoom
                clusterView?.displayPriority = .required
                
                // Set z-priority for layering: green clusters above grey clusters
                clusterView?.zPriority = isCollectedCluster ? Self.greenZPriority : Self.greyZPriority
                
                // Remove old subviews to prevent stacking
                clusterView?.subviews.forEach { $0.removeFromSuperview() }
                
                // Create custom cluster pin view
                let clusterPinView = ClusterPin(count: cluster.memberAnnotations.count, isCollected: isCollectedCluster)
                _ = configureHostingController(with: clusterPinView, in: clusterView!)
                
                return clusterView
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
            
            // Set clustering identifier and display priority based on stamp state
            let isCollected = stampAnnotation.isCollected
            let isWithinRange = stampAnnotation.isWithinRange
            
            if isCollected {
                // Collected stamps cluster together (green)
                annotationView?.clusteringIdentifier = Self.collectedClusteringIdentifier
                annotationView?.displayPriority = .required  // Prevent culling at medium zoom
                annotationView?.zPriority = Self.greenZPriority  // Green above grey
            } else if !isWithinRange {
                // Locked stamps cluster together (grey/white)
                annotationView?.clusteringIdentifier = Self.lockedClusteringIdentifier
                annotationView?.displayPriority = .required  // Prevent culling at medium zoom
                annotationView?.zPriority = Self.greyZPriority  // Grey below green
            } else {
                // Unlocked (blue) stamps don't cluster - highest priority, always on top
                annotationView?.clusteringIdentifier = nil
                annotationView?.displayPriority = .required
                annotationView?.zPriority = Self.blueZPriority  // Blue always on top
            }
            
            // Remove old subviews to prevent stacking
            annotationView?.subviews.forEach { $0.removeFromSuperview() }
            
            // Create the stamp pin view
            let stampPinView = StampPin(
                stamp: stampAnnotation.stamp,
                isWithinRange: isWithinRange,
                isCollected: isCollected
            )
            
            // Store the hosting controller so we can update it later
            let annotationId = ObjectIdentifier(stampAnnotation)
            let hostingController = configureHostingController(with: stampPinView, in: annotationView!)
            hostingControllers[annotationId] = hostingController
            
            return annotationView
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
            .navigationTitle("Search")
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

