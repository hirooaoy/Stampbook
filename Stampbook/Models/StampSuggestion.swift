import Foundation
import FirebaseFirestore

/// User-submitted suggestion for a new stamp or collection
struct StampSuggestion: Codable {
    let userId: String
    let username: String
    let userDisplayName: String
    let type: SuggestionType
    
    // Single stamp fields
    let stampName: String
    let fullAddress: String
    let additionalNotes: String
    
    // Collection fields (if type = collection)
    let collectionName: String?
    let additionalStamps: [StampData]? // 2+ more stamps for collection
    
    let createdAt: Date
    
    enum SuggestionType: String, Codable {
        case singleStamp = "single_stamp"
        case collection = "collection"
    }
}

/// Individual stamp data within a collection suggestion
struct StampData: Identifiable, Codable {
    var id = UUID()
    let name: String
    let fullAddress: String
    let additionalNotes: String
    
    /// Check if all fields are filled (for validation)
    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !fullAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !additionalNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
