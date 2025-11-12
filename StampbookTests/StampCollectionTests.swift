import XCTest
import CoreLocation
@testable import Stampbook

/// Tests for stamp collection distance and radius logic
/// Critical because GPS accuracy and collection radius determine core gameplay
class StampCollectionTests: XCTestCase {
    
    // MARK: - Distance Tests
    
    func testStampWithinRegularRadius() {
        // Golden Gate Bridge stamp location
        let stampLat = 37.8199
        let stampLong = -122.4783
        
        // User 100 meters away (well within 150m regular radius)
        let userLocation = CLLocation(latitude: 37.8209, longitude: -122.4783)
        let stampLocation = CLLocation(latitude: stampLat, longitude: stampLong)
        
        let distance = userLocation.distance(from: stampLocation)
        
        XCTAssertLessThan(distance, 150, "User at 100m should be able to collect stamp with regular radius (150m)")
    }
    
    func testStampOutsideRegularRadius() {
        // Golden Gate Bridge stamp location
        let stampLat = 37.8199
        let stampLong = -122.4783
        
        // User 200 meters away (outside 150m radius)
        let userLocation = CLLocation(latitude: 37.8217, longitude: -122.4783)
        let stampLocation = CLLocation(latitude: stampLat, longitude: stampLong)
        
        let distance = userLocation.distance(from: stampLocation)
        
        XCTAssertGreaterThan(distance, 150, "User at 200m should NOT be able to collect stamp with regular radius (150m)")
    }
    
    func testStampAtExactRadius() {
        // Test edge case: exactly at 150m boundary
        let stampLat = 37.8199
        let stampLong = -122.4783
        
        // Calculate a point approximately 150m north
        // 1 degree latitude ≈ 111km, so 150m ≈ 0.00135 degrees
        let userLocation = CLLocation(latitude: stampLat + 0.00135, longitude: stampLong)
        let stampLocation = CLLocation(latitude: stampLat, longitude: stampLong)
        
        let distance = userLocation.distance(from: stampLocation)
        
        // Should be very close to 150m (within 5m tolerance for GPS accuracy)
        XCTAssertEqual(distance, 150, accuracy: 5, "Distance calculation should be accurate at 150m boundary")
    }
    
    // MARK: - Collection Radius Types
    
    func testRegularCollectionRadius() {
        let stamp = Stamp(
            id: "test-regular",
            name: "Test Landmark",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Test stamp",
            collectionRadius: "regular"
        )
        
        XCTAssertEqual(stamp.collectionRadiusInMeters, 150, "Regular stamps should have 150m radius")
    }
    
    func testRegularPlusCollectionRadius() {
        let stamp = Stamp(
            id: "test-regularplus",
            name: "Test Park",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Test stamp",
            collectionRadius: "regularplus"
        )
        
        XCTAssertEqual(stamp.collectionRadiusInMeters, 500, "RegularPlus stamps should have 500m radius")
    }
    
    func testLargeCollectionRadius() {
        let stamp = Stamp(
            id: "test-large",
            name: "Test Large Park",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Test stamp",
            collectionRadius: "large"
        )
        
        XCTAssertEqual(stamp.collectionRadiusInMeters, 1500, "Large stamps should have 1500m radius")
    }
    
    func testXLargeCollectionRadius() {
        let stamp = Stamp(
            id: "test-xlarge",
            name: "Test Airport",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Test stamp",
            collectionRadius: "xlarge"
        )
        
        XCTAssertEqual(stamp.collectionRadiusInMeters, 3000, "XLarge stamps should have 3000m radius")
    }
    
    func testUnknownCollectionRadiusDefaultsToRegular() {
        let stamp = Stamp(
            id: "test-unknown",
            name: "Test",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Test stamp",
            collectionRadius: "unknown_type"
        )
        
        XCTAssertEqual(stamp.collectionRadiusInMeters, 150, "Unknown radius types should default to regular (150m)")
    }
    
    // MARK: - Special Cases
    
    func testWelcomeStampIdentification() {
        let welcomeStamp = Stamp(
            id: "your-first-stamp",
            name: "Welcome Stamp",
            latitude: 0,
            longitude: 0,
            address: "",
            collectionIds: [],
            about: "Welcome to Stampbook!"
        )
        
        XCTAssertTrue(welcomeStamp.isWelcomeStamp, "Welcome stamp should be identified by id")
        XCTAssertFalse(welcomeStamp.requiresLocation, "Welcome stamp should not require location")
    }
    
    func testRegularStampRequiresLocation() {
        let stamp = Stamp(
            id: "golden-gate",
            name: "Golden Gate Bridge",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Golden Gate Bridge\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Iconic bridge"
        )
        
        XCTAssertTrue(stamp.requiresLocation, "Regular stamps should require location")
    }
}

