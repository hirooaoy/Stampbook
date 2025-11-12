import XCTest
@testable import Stampbook

/// Tests for address parsing and country extraction
/// Critical for profile stats (unique countries visited)
class CountryParsingTests: XCTestCase {
    
    // MARK: - US Address Format
    
    func testUSAddressFormat() {
        let stamp = Stamp(
            id: "test-us",
            name: "Golden Gate Bridge",
            latitude: 37.8199,
            longitude: -122.4783,
            address: "Golden Gate Bridge\nSan Francisco, CA, USA 94129",
            collectionIds: [],
            about: "Iconic bridge"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "San Francisco, USA", "US address should parse city and country correctly")
    }
    
    func testUSAddressWithoutZipCode() {
        let stamp = Stamp(
            id: "test-us-nozip",
            name: "Test Location",
            latitude: 40.7128,
            longitude: -74.0060,
            address: "Test Street\nNew York, NY, USA",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "New York, USA", "US address without zip should still parse correctly")
    }
    
    // MARK: - International Address Formats
    
    func testJapanAddressFormat() {
        let stamp = Stamp(
            id: "test-japan",
            name: "Tokyo Tower",
            latitude: 35.6586,
            longitude: 139.7454,
            address: "4 Chome-2-8 Shibakoen\nTokyo, Japan",
            collectionIds: [],
            about: "Famous tower"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "Tokyo, Japan", "Japanese address should parse correctly")
    }
    
    func testUKAddressFormat() {
        let stamp = Stamp(
            id: "test-uk",
            name: "Big Ben",
            latitude: 51.5007,
            longitude: -0.1246,
            address: "Westminster\nLondon, England, UK SW1A 0AA",
            collectionIds: [],
            about: "Clock tower"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "London, UK", "UK address should parse correctly")
    }
    
    func testFranceAddressFormat() {
        let stamp = Stamp(
            id: "test-france",
            name: "Eiffel Tower",
            latitude: 48.8584,
            longitude: 2.2945,
            address: "Champ de Mars\nParis, France 75007",
            collectionIds: [],
            about: "Iron lattice tower"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "Paris, France", "French address should parse correctly")
    }
    
    // MARK: - Edge Cases
    
    func testSingleLineAddress() {
        let stamp = Stamp(
            id: "test-single",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "Single Line Address",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "Location not included", "Single line address should return fallback")
    }
    
    func testEmptyAddress() {
        let stamp = Stamp(
            id: "test-empty",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "Location not included", "Empty address should return fallback")
    }
    
    func testAddressWithExtraCommas() {
        let stamp = Stamp(
            id: "test-extra-commas",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "123 Street\nCity, State, Country, ExtraField",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        // Should still parse first and third parts
        XCTAssertTrue(cityCountry.contains("City"), "Should extract city even with extra commas")
    }
    
    func testAddressWithNoCommas() {
        let stamp = Stamp(
            id: "test-no-commas",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "123 Street\nSingleLocation",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "Location not included", "Address without commas should return fallback")
    }
    
    // MARK: - Whitespace Handling
    
    func testAddressWithExtraWhitespace() {
        let stamp = Stamp(
            id: "test-whitespace",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "123 Street\nSan Francisco  ,  CA  ,  USA  94102",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "San Francisco, USA", "Should handle extra whitespace correctly")
    }
    
    // MARK: - Country Code Extraction
    
    func testCountryCodeWithZipCode() {
        let stamp = Stamp(
            id: "test-country-zip",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "Street\nCity, State, USA 12345",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        // Should extract "USA" even though there's a zip code after it
        XCTAssertTrue(cityCountry.hasSuffix("USA"), "Should extract country code before zip")
    }
    
    func testCountryCodeWithoutZipCode() {
        let stamp = Stamp(
            id: "test-country-nozip",
            name: "Test",
            latitude: 0,
            longitude: 0,
            address: "Street\nCity, Japan",
            collectionIds: [],
            about: "Test"
        )
        
        let cityCountry = stamp.cityCountry
        XCTAssertEqual(cityCountry, "City, Japan", "Should handle addresses without zip codes")
    }
}

