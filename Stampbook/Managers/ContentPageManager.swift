import Foundation
import Combine
import FirebaseFirestore

/// Manager for fetching content pages from Firestore
/// Content pages can be local businesses, creator profiles, or app information
@MainActor
class ContentPageManager: ObservableObject {
    private let db = Firestore.firestore()
    
    @Published var isLoading = false
    @Published var error: Error?
    
    // Cache for content pages to avoid redundant fetches
    private var cache: [String: ContentPage] = [:]
    
    /// Fetch a content page by ID from Firestore
    /// - Parameter id: The content page ID
    /// - Returns: ContentPage if found, nil otherwise
    func fetchContentPage(id: String) async -> ContentPage? {
        // Check cache first
        if let cached = cache[id] {
            return cached
        }
        
        isLoading = true
        error = nil
        
        do {
            let doc = try await db.collection("contentPages").document(id).getDocument()
            
            guard doc.exists else {
                print("ContentPage not found: \(id)")
                isLoading = false
                return nil
            }
            
            guard var data = doc.data() else {
                print("ContentPage has no data: \(id)")
                isLoading = false
                return nil
            }
            
            // Add the document ID to the data for decoding
            data["id"] = doc.documentID
            
            // Convert lastUpdated timestamp if it exists
            if let timestamp = data["lastUpdated"] as? Timestamp {
                data["lastUpdated"] = timestamp.dateValue().timeIntervalSince1970
            }
            
            // Sort sections by order
            if var sections = data["sections"] as? [[String: Any]] {
                sections.sort { (a, b) in
                    let orderA = a["order"] as? Int ?? 0
                    let orderB = b["order"] as? Int ?? 0
                    return orderA < orderB
                }
                data["sections"] = sections
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let contentPage = try JSONDecoder().decode(ContentPage.self, from: jsonData)
            
            // Cache the result
            cache[id] = contentPage
            
            isLoading = false
            return contentPage
            
        } catch {
            print("Error fetching content page: \(error.localizedDescription)")
            self.error = error
            isLoading = false
            return nil
        }
    }
    
    /// Clear the cache (useful for testing or force refresh)
    func clearCache() {
        cache.removeAll()
    }
}

