import Foundation

struct Collection: Identifiable, Codable {
    let id: String
    let emoji: String
    let name: String
    let description: String
    let region: String
    let totalStamps: Int
    let parentId: String?
    let isParent: Bool
    
    // Custom decoding for backward compatibility with old Firebase data
    enum CodingKeys: String, CodingKey {
        case id, emoji, name, description, region, totalStamps, parentId, isParent
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
        totalStamps = try container.decodeIfPresent(Int.self, forKey: .totalStamps) ?? 0
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        isParent = try container.decodeIfPresent(Bool.self, forKey: .isParent) ?? false
    }
}

// MARK: - Collection Helpers
extension Collection {
    /// Check if this collection has child collections
    /// - Parameter allCollections: Array of all collections to search through
    /// - Returns: True if any collection has this collection as its parent
    func hasChildren(in allCollections: [Collection]) -> Bool {
        return allCollections.contains { $0.parentId == self.id }
    }
    
    /// Get all direct children of this collection
    /// - Parameter allCollections: Array of all collections to search through
    /// - Returns: Array of child collections
    func getChildren(from allCollections: [Collection]) -> [Collection] {
        return allCollections.filter { $0.parentId == self.id }
    }
    
    /// Get all descendants (children, grandchildren, etc.) recursively
    /// - Parameter allCollections: Array of all collections to search through
    /// - Returns: Array of all descendant collections
    func getAllDescendants(from allCollections: [Collection]) -> [Collection] {
        let children = getChildren(from: allCollections)
        let grandchildren = children.flatMap { $0.getAllDescendants(from: allCollections) }
        return children + grandchildren
    }
}

