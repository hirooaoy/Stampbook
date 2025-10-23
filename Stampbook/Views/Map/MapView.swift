import SwiftUI
import MapKit
import Combine

struct MapView: View {
    /// The radius in meters within which a user can collect a stamp
    static let stampCollectionRadius: Double = 10000 // 10km - FOR TESTING (change back to 100 for production)
    
    @StateObject private var locationManager = LocationManager()
    @StateObject private var searchCompleter = LocationSearchCompleter()
    @EnvironmentObject var stampsManager: StampsManager
    @State private var selectedStamp: Stamp?
    @State private var shouldRecenterMap = false
    @State private var searchText = ""
    @State private var searchRegion: MKCoordinateRegion?
    @State private var isShowingSearch = false
    
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
        ZStack(alignment: .bottomTrailing) {
            NativeMapView(
                stamps: stampsManager.stamps,
                collectedStampIds: collectedStampIds,
                userLocation: locationManager.location,
                selectedStamp: $selectedStamp,
                shouldRecenter: $shouldRecenterMap,
                searchRegion: $searchRegion
            )
            .ignoresSafeArea()
            
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
                
                // Re-center button
                Button(action: {
                    shouldRecenterMap = true
                }) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.blue)
                        .clipShape(Circle())
                        .shadow(
                            color: .black.opacity(0.2),
                            radius: 4,
                            x: 0,
                            y: 2
                        )
                }
            }
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
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestPermission()
            } else if locationManager.authorizationStatus == .authorizedWhenInUse ||
                      locationManager.authorizationStatus == .authorizedAlways {
                locationManager.startUpdatingLocation()
            }
        }
    }
}

// Native UIKit MKMapView wrapper with true heading support
struct NativeMapView: UIViewRepresentable {
    let stamps: [Stamp]
    let collectedStampIds: Set<String>
    let userLocation: CLLocation?
    @Binding var selectedStamp: Stamp?
    @Binding var shouldRecenter: Bool
    @Binding var searchRegion: MKCoordinateRegion?
    
    // Constants
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    private static let sanFranciscoCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        
        // Configure map appearance
        let config = MKStandardMapConfiguration()
        config.emphasisStyle = .default
        config.pointOfInterestFilter = .excludingAll
        mapView.preferredConfiguration = config
        
        // Set initial region
        let initialRegion = MKCoordinateRegion(
            center: Self.sanFranciscoCoordinate,
            span: Self.defaultSpan
        )
        mapView.setRegion(initialRegion, animated: false)
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
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
            let region = MKCoordinateRegion(center: location.coordinate, span: Self.defaultSpan)
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
                // Remove old annotations (except user location)
                let oldAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
                mapView.removeAnnotations(oldAnnotations)
                
                // Clear hosting controllers for removed annotations
                hostingControllers.removeAll()
                
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
                let region = MKCoordinateRegion(center: location.coordinate, span: NativeMapView.defaultSpan)
                mapView.setRegion(region, animated: true)
                hasSetInitialRegion = true
            }
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
        completer.resultTypes = [.address]  // Only addresses - no POIs
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

