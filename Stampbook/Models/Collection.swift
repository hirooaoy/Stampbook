import Foundation

struct Collection: Identifiable, Codable {
    let id: String
    let emoji: String
    let name: String
    let description: String
    let region: String
    let totalStamps: Int
    
    // Custom decoding for backward compatibility with old Firebase data
    enum CodingKeys: String, CodingKey {
        case id, emoji, name, description, region, totalStamps
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? ""
        totalStamps = try container.decodeIfPresent(Int.self, forKey: .totalStamps) ?? 0
    }
}

