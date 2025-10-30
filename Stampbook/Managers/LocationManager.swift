import Foundation
import CoreLocation
import Combine

// MARK: - Privacy-First Location Manager
// ==========================================
// IMPORTANT: This LocationManager implements privacy-first location tracking.
//
// PRIVACY COMPLIANCE:
// - Only tracks location for AUTHENTICATED users (GDPR/privacy compliant)
// - Anonymous users can browse the app without any location tracking
// - Location permission is requested ONLY when user signs in
// - Location data is cleared when user signs out
//
// WHY THIS MATTERS:
// - Prevents unnecessary data collection (GDPR Article 5 - Data Minimization)
// - Clear purpose for location tracking (stamp collection requires auth)
// - No "anonymous tracking" concerns
// - Respects user privacy before they commit to the app
//
// USAGE:
// - Call startTrackingForAuthenticatedUser() when user signs in
// - Call stopTracking() when user signs out
// - Check isTrackingEnabled to see if tracking is active
//
// ==========================================

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    /// Tracks if location tracking is enabled (only true for authenticated users)
    /// This is the key privacy control - prevents tracking for anonymous users
    @Published var isTrackingEnabled = false
    
    override init() {
        self.authorizationStatus = locationManager.authorizationStatus
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.headingFilter = 5 // Update when heading changes by 5 degrees
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading() // Start tracking heading
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading() // Stop tracking heading
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        
        // PRIVACY: Only auto-start if tracking is enabled (user is authenticated)
        // This prevents the old behavior where location would start immediately on app launch
        if isTrackingEnabled && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) {
            startUpdatingLocation()
        }
    }
    
    // MARK: - Privacy-Safe Methods
    
    /// Request location permission and start tracking (for authenticated users only)
    /// PRIVACY: This should ONLY be called when user is signed in
    /// - Call this when user signs in or when authenticated user opens Map
    /// - This ensures location is only tracked with clear purpose (stamp collection)
    func startTrackingForAuthenticatedUser() {
        isTrackingEnabled = true
        
        if authorizationStatus == .notDetermined {
            requestPermission()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            startUpdatingLocation()
        }
    }
    
    /// Stop tracking and clear location data
    /// PRIVACY: Called when user signs out to stop all location tracking
    /// Also clears cached location data (right to erasure)
    func stopTracking() {
        isTrackingEnabled = false
        stopUpdatingLocation()
        location = nil  // Clear cached location (privacy - don't keep user data after sign-out)
        heading = nil   // Clear cached heading
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}

