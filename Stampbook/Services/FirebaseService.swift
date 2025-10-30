import Foundation
import FirebaseFirestore
import FirebaseStorage

/// Service to handle all Firebase operations (Firestore & Storage)
class FirebaseService {
    static let shared = FirebaseService()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    private init() {
        // Enable offline persistence
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        db.settings = settings
    }
    
    // MARK: - Collected Stamps Sync
    
    /// Fetch all collected stamps for a user from Firestore
    func fetchCollectedStamps(for userId: String) async throws -> [CollectedStamp] {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .getDocuments()
        
        let stamps = snapshot.documents.compactMap { doc -> CollectedStamp? in
            try? doc.data(as: CollectedStamp.self)
        }
        
        return stamps
    }
    
    /// Save a single collected stamp to Firestore
    func saveCollectedStamp(_ stamp: CollectedStamp, for userId: String) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stamp.stampId)
        
        try docRef.setData(from: stamp, merge: true)
    }
    
    /// Update notes for a collected stamp
    func updateStampNotes(stampId: String, userId: String, notes: String) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stampId)
        
        try await docRef.updateData([
            "userNotes": notes
        ])
    }
    
    /// Update images for a collected stamp
    func updateStampImages(stampId: String, userId: String, imageNames: [String], imagePaths: [String]) async throws {
        let docRef = db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .document(stampId)
        
        try await docRef.updateData([
            "userImageNames": imageNames,
            "userImagePaths": imagePaths
        ])
    }
    
    /// Delete all collected stamps for a user (used in resetAll)
    func deleteAllCollectedStamps(for userId: String) async throws {
        let snapshot = try await db
            .collection("users")
            .document(userId)
            .collection("collected_stamps")
            .getDocuments()
        
        // Delete in batches
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }
    
    // MARK: - Photo Upload (for Step 3)
    // NOTE: Limit to 5 photos per stamp to control Firebase Storage costs
    // Requires Blaze plan (pay-as-you-go) to use Storage
    
    /// Upload a photo to Firebase Storage
    /// Returns the download URL
    func uploadStampPhoto(userId: String, stampId: String, imageData: Data) async throws -> String {
        let photoId = UUID().uuidString
        let path = "users/\(userId)/stamp_photos/\(stampId)_\(photoId).jpg"
        let storageRef = storage.reference().child(path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await storageRef.downloadURL()
        
        return downloadURL.absoluteString
    }
    
    /// Delete a photo from Firebase Storage
    func deleteStampPhoto(url: String) async throws {
        let storageRef = storage.reference(forURL: url)
        try await storageRef.delete()
    }
}

