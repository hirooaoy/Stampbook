import Foundation
import CoreLocation
import MapKit

/// Geohash encoding for geographic coordinates
/// Used for efficient spatial queries in Firestore
///
/// Geohash is a geocoding system that encodes lat/long into a short string.
/// Nearby locations share common prefixes, enabling range queries.
///
/// Example: San Francisco Ferry Building
/// - Coordinates: 37.7956, -122.3933
/// - Geohash: "9q8yyk8y" (8 characters = ~19m precision)
/// - Prefix "9q8y" covers most of SF downtown area
///
/// Precision levels:
/// - 4 chars: ~20km (city level)
/// - 5 chars: ~5km (neighborhood level)  
/// - 6 chars: ~1km (street level)
/// - 7 chars: ~150m (block level)
/// - 8 chars: ~19m (building level)
struct Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    
    /// Encode coordinates to geohash string
    /// - Parameters:
    ///   - latitude: Latitude (-90 to 90)
    ///   - longitude: Longitude (-180 to 180)
    ///   - precision: Number of characters (default 8 for ~19m precision)
    /// - Returns: Geohash string
    static func encode(latitude: Double, longitude: Double, precision: Int = 8) -> String {
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var hash = ""
        var bits = 0
        var bit = 0
        var even = true
        
        while hash.count < precision {
            if even {
                // Longitude
                let mid = (lonRange.0 + lonRange.1) / 2
                if longitude > mid {
                    bit |= (1 << (4 - bits))
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                // Latitude
                let mid = (latRange.0 + latRange.1) / 2
                if latitude > mid {
                    bit |= (1 << (4 - bits))
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            
            even = !even
            bits += 1
            
            if bits == 5 {
                hash.append(base32[bit])
                bits = 0
                bit = 0
            }
        }
        
        return hash
    }
    
    /// Encode CLLocationCoordinate2D to geohash
    static func encode(coordinate: CLLocationCoordinate2D, precision: Int = 8) -> String {
        return encode(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
    }
    
    /// Get bounding box geohashes for a region
    /// Returns (minGeohash, maxGeohash) for Firestore range query
    ///
    /// Usage:
    /// ```
    /// let (min, max) = Geohash.bounds(for: mapRegion, precision: 5)
    /// // Query: WHERE geohash >= min AND geohash < max
    /// ```
    static func bounds(for region: MKCoordinateRegion, precision: Int = 5) -> (min: String, max: String) {
        let center = region.center
        let span = region.span
        
        // Calculate corners of visible region
        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLon = center.longitude - span.longitudeDelta / 2
        let maxLon = center.longitude + span.longitudeDelta / 2
        
        // Get geohash for corners
        let sw = encode(latitude: minLat, longitude: minLon, precision: precision)
        let ne = encode(latitude: maxLat, longitude: maxLon, precision: precision)
        
        // Find common prefix (this is the region's geohash prefix)
        var commonPrefix = ""
        for (c1, c2) in zip(sw, ne) {
            if c1 == c2 {
                commonPrefix.append(c1)
            } else {
                break
            }
        }
        
        // If no common prefix, return full range for this precision
        if commonPrefix.isEmpty {
            return (min: String(repeating: "0", count: precision), 
                    max: String(repeating: "z", count: precision))
        }
        
        // Return range that covers the region
        // We need to be conservative - include nearby geohashes
        let minHash = commonPrefix + String(repeating: "0", count: max(0, precision - commonPrefix.count))
        let maxHash = commonPrefix + String(repeating: "z", count: max(0, precision - commonPrefix.count))
        
        return (min: minHash, max: maxHash)
    }
}

