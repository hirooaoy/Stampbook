import Foundation

// MARK: - ContentPage Model
/// Represents a content page that can be displayed in a native sheet
/// Used for local businesses, creator profiles, and app information
struct ContentPage: Identifiable, Codable {
    let id: String
    let title: String
    let type: ContentType
    let relatedStampId: String? // Optional link to a stamp
    let sections: [ContentSection]
    let lastUpdated: Date?
    
    enum ContentType: String, Codable {
        case localBusiness = "local_business"
        case creator = "creator"
        case about = "about"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, type, relatedStampId, sections, lastUpdated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(ContentType.self, forKey: .type)
        relatedStampId = try container.decodeIfPresent(String.self, forKey: .relatedStampId)
        sections = try container.decode([ContentSection].self, forKey: .sections)
        
        // Handle Firestore timestamp conversion
        if let timestamp = try? container.decode(Double.self, forKey: .lastUpdated) {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        } else {
            lastUpdated = nil
        }
    }
}

// MARK: - ContentSection
/// Represents a section within a content page
/// Each section has a type and associated data
struct ContentSection: Codable, Identifiable {
    let id: String
    let type: SectionType
    let order: Int // For sorting sections
    
    // Content fields (populated based on type)
    let content: String? // For text, html
    let imageUrl: String? // For image
    let linkUrl: String? // For link
    let linkLabel: String? // For link
    let hoursData: [String: String]? // For hours (e.g., "Monday": "9am-5pm")
    
    enum SectionType: String, Codable {
        case text = "text"
        case image = "image"
        case link = "link"
        case hours = "hours"
        case divider = "divider"
    }
    
    // Generate ID from order if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let decodedId = try? container.decode(String.self, forKey: .id) {
            id = decodedId
        } else {
            // Generate ID from order
            let orderValue = try container.decode(Int.self, forKey: .order)
            id = "section-\(orderValue)"
        }
        
        type = try container.decode(SectionType.self, forKey: .type)
        order = try container.decode(Int.self, forKey: .order)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        linkUrl = try container.decodeIfPresent(String.self, forKey: .linkUrl)
        linkLabel = try container.decodeIfPresent(String.self, forKey: .linkLabel)
        hoursData = try container.decodeIfPresent([String: String].self, forKey: .hoursData)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, order, content, imageUrl, linkUrl, linkLabel, hoursData
    }
}

