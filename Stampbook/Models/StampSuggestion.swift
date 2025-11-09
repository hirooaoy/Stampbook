import Foundation
import FirebaseFirestore

/// User-submitted suggestion for a new stamp or collection
struct StampSuggestion: Codable {
    let userId: String
    let username: String
    let userDisplayName: String
    let type: SuggestionType
    
    // Single stamp fields
    let googleMapLink: String?
    let description: String?
    
    // Collection fields (if type = collection)
    let collectionName: String?
    let stamps: [StampData]? // All stamps in collection (minimum 3)
    
    let createdAt: Date
    
    enum SuggestionType: String, Codable {
        case singleStamp = "single_stamp"
        case collection = "collection"
    }
}

/// Individual stamp data within a collection suggestion
struct StampData: Identifiable, Codable {
    var id = UUID()
    let googleMapLink: String
    let description: String
    
    /// Check if all fields are filled (for validation)
    var isComplete: Bool {
        !googleMapLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
