import XCTest
@testable import Stampbook

/// Tests for profile statistics calculations
/// Critical for accurate user profiles (total stamps, unique countries)
class ProfileStatsTests: XCTestCase {
    
    var stampsManager: StampsManager!
    
    override func setUp() {
        super.setUp()
        stampsManager = StampsManager()
    }
    
    // MARK: - Unique Country Calculation
    
    func testUniqueCountriesWithMultipleCountries() {
        // Create stamps in different countries
        let stamps = [
            Stamp(id: "us1", name: "Golden Gate", latitude: 37.8199, longitude: -122.4783,
                  address: "Bridge\nSan Francisco, CA, USA 94129", collectionIds: [], about: "Bridge"),
            Stamp(id: "us2", name: "Statue of Liberty", latitude: 40.6892, longitude: -74.0445,
                  address: "Liberty Island\nNew York, NY, USA 10004", collectionIds: [], about: "Statue"),
            Stamp(id: "us3", name: "Hollywood Sign", latitude: 34.1341, longitude: -118.3215,
                  address: "Hollywood Hills\nLos Angeles, CA, USA 90068", collectionIds: [], about: "Sign"),
            Stamp(id: "jp1", name: "Tokyo Tower", latitude: 35.6586, longitude: 139.7454,
                  address: "4 Chome-2-8 Shibakoen\nTokyo, Japan", collectionIds: [], about: "Tower"),
            Stamp(id: "jp2", name: "Mount Fuji", latitude: 35.3606, longitude: 138.7274,
                  address: "Fuji-Hakone-Izu National Park\nFuji, Japan", collectionIds: [], about: "Mountain")
        ]
        
        // Calculate unique countries directly from stamps (no Firebase needed)
        let uniqueCountries = stampsManager.calculateUniqueCountries(from: stamps)
        
        // 3 USA stamps + 2 Japan stamps = 2 unique countries
        XCTAssertEqual(uniqueCountries, 2, "Should count 2 unique countries (USA and Japan)")
    }
    
    func testUniqueCountriesWithSingleCountry() {
        let stamps = [
            Stamp(id: "us1", name: "Test1", latitude: 0, longitude: 0,
                  address: "Street\nCity1, State1, USA", collectionIds: [], about: "Test"),
            Stamp(id: "us2", name: "Test2", latitude: 0, longitude: 0,
                  address: "Street\nCity2, State2, USA", collectionIds: [], about: "Test"),
            Stamp(id: "us3", name: "Test3", latitude: 0, longitude: 0,
                  address: "Street\nCity3, State3, USA", collectionIds: [], about: "Test")
        ]
        
        let uniqueCountries = stampsManager.calculateUniqueCountries(from: stamps)
        
        // All 3 stamps in USA = 1 unique country
        XCTAssertEqual(uniqueCountries, 1, "Should count 1 unique country when all stamps are in same country")
    }
    
    func testUniqueCountriesWithEmptyList() {
        let uniqueCountries = stampsManager.calculateUniqueCountries(from: [] as [Stamp])
        XCTAssertEqual(uniqueCountries, 0, "Empty stamp list should return 0 countries")
    }
    
    func testUniqueCountriesIgnoresInvalidAddresses() {
        let stamps = [
            Stamp(id: "valid", name: "Valid", latitude: 0, longitude: 0,
                  address: "Street\nCity, USA", collectionIds: [], about: "Valid stamp"),
            Stamp(id: "invalid1", name: "Invalid1", latitude: 0, longitude: 0,
                  address: "SingleLineAddress", collectionIds: [], about: "Invalid"),
            Stamp(id: "invalid2", name: "Invalid2", latitude: 0, longitude: 0,
                  address: "", collectionIds: [], about: "Invalid")
        ]
        
        let uniqueCountries = stampsManager.calculateUniqueCountries(from: stamps)
        
        // Only 1 valid country should be counted
        XCTAssertEqual(uniqueCountries, 1, "Should only count stamps with valid country parsing")
    }
    
    // MARK: - Country Parsing for Stats (Integration Test)
    
    func testCountryExtraction() {
        let usStamp = Stamp(id: "us", name: "Test", latitude: 0, longitude: 0,
                           address: "Street\nSan Francisco, CA, USA 94129", collectionIds: [], about: "Test")
        
        let japanStamp = Stamp(id: "jp", name: "Test", latitude: 0, longitude: 0,
                              address: "Street\nTokyo, Japan", collectionIds: [], about: "Test")
        
        let franceStamp = Stamp(id: "fr", name: "Test", latitude: 0, longitude: 0,
                               address: "Street\nParis, France 75007", collectionIds: [], about: "Test")
        
        // Extract city/country for display
        XCTAssertEqual(usStamp.cityCountry, "San Francisco, USA", "US address parsing")
        XCTAssertEqual(japanStamp.cityCountry, "Tokyo, Japan", "Japan address parsing")
        XCTAssertEqual(franceStamp.cityCountry, "Paris, France", "France address parsing (postal code should be stripped)")
    }
}

