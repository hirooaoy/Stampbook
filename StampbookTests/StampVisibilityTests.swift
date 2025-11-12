import XCTest
@testable import Stampbook

/// Tests for stamp visibility and moderation system
/// Critical for content moderation and managing removed/hidden stamps
class StampVisibilityTests: XCTestCase {
    
    // MARK: - Status-Based Visibility
    
    func testActiveStampIsAvailable() {
        let stamp = Stamp(
            id: "test-active",
            name: "Test Stamp",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active"
        )
        
        XCTAssertTrue(stamp.isCurrentlyAvailable, "Active stamps should be available")
    }
    
    func testHiddenStampIsNotAvailable() {
        let stamp = Stamp(
            id: "test-hidden",
            name: "Hidden Stamp",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "hidden"
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Hidden stamps should NOT be available")
    }
    
    func testRemovedStampIsNotAvailable() {
        let stamp = Stamp(
            id: "test-removed",
            name: "Removed Stamp",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "removed"
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Removed stamps should NOT be available")
    }
    
    func testNilStatusDefaultsToActive() {
        let stamp = Stamp(
            id: "test-nil",
            name: "Old Stamp",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: nil
        )
        
        XCTAssertTrue(stamp.isCurrentlyAvailable, "Stamps with nil status should default to active (backward compatibility)")
    }
    
    // MARK: - Date-Based Visibility (Future Events)
    
    func testStampNotYetAvailable() {
        let futureDate = Date().addingTimeInterval(86400) // Tomorrow
        
        let stamp = Stamp(
            id: "test-future",
            name: "Future Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: futureDate,
            availableUntil: nil
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Stamps with future availableFrom date should NOT be available yet")
    }
    
    func testStampAvailableNow() {
        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        
        let stamp = Stamp(
            id: "test-available",
            name: "Available Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: pastDate,
            availableUntil: nil
        )
        
        XCTAssertTrue(stamp.isCurrentlyAvailable, "Stamps with past availableFrom date should be available")
    }
    
    func testStampExpired() {
        let pastDate = Date().addingTimeInterval(-86400) // Yesterday
        
        let stamp = Stamp(
            id: "test-expired",
            name: "Expired Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: nil,
            availableUntil: pastDate
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Stamps with past availableUntil date should be expired")
    }
    
    func testStampWithinDateRange() {
        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)
        
        let stamp = Stamp(
            id: "test-current",
            name: "Current Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: yesterday,
            availableUntil: tomorrow
        )
        
        XCTAssertTrue(stamp.isCurrentlyAvailable, "Stamps within their date range should be available")
    }
    
    func testStampWithNilDatesIsAlwaysAvailable() {
        let stamp = Stamp(
            id: "test-permanent",
            name: "Permanent Stamp",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: nil,
            availableUntil: nil
        )
        
        XCTAssertTrue(stamp.isCurrentlyAvailable, "Stamps with no date restrictions should always be available")
    }
    
    // MARK: - Combined Status and Date Validation
    
    func testHiddenStampWithValidDatesIsStillNotAvailable() {
        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)
        
        let stamp = Stamp(
            id: "test-hidden-dates",
            name: "Hidden Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "hidden",
            availableFrom: yesterday,
            availableUntil: tomorrow
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Hidden stamps should NOT be available even with valid dates")
    }
    
    func testActiveStampOutsideDateRangeIsNotAvailable() {
        let pastStart = Date().addingTimeInterval(-172800) // 2 days ago
        let pastEnd = Date().addingTimeInterval(-86400) // Yesterday
        
        let stamp = Stamp(
            id: "test-active-expired",
            name: "Past Event",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Test Address\nSan Francisco, CA, USA",
            collectionIds: [],
            about: "Test",
            status: "active",
            availableFrom: pastStart,
            availableUntil: pastEnd
        )
        
        XCTAssertFalse(stamp.isCurrentlyAvailable, "Active stamps outside their date range should NOT be available")
    }
}

