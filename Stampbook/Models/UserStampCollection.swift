import Foundation
import Combine

// TODO: BACKEND - Consider adding collectionLocation (lat/long where user actually collected it)
struct CollectedStamp: Codable, Identifiable, Equatable {
    var id: String { stampId } // Make it Identifiable for Firestore
    let stampId: String
    let userId: String
    let collectedDate: Date
    var userNotes: String
    var userImageNames: [String] // References to locally saved images
    var userImagePaths: [String] // Firebase Storage paths for cloud images
    var likeCount: Int // Number of likes on this post
    var commentCount: Int // Number of comments on this post
    
    // Future fields:
    // var collectionLocation: CLLocationCoordinate2D?
    // var isPublic: Bool = false (for social features)
    
    // MARK: - Backward Compatibility
    
    enum CodingKeys: String, CodingKey {
        case stampId, userId, collectedDate, userNotes, userImageNames, userImagePaths, likeCount, commentCount
    }
    
    init(stampId: String, userId: String, collectedDate: Date, userNotes: String, userImageNames: [String], userImagePaths: [String], likeCount: Int = 0, commentCount: Int = 0) {
        self.stampId = stampId
        self.userId = userId
        self.collectedDate = collectedDate
        self.userNotes = userNotes
        self.userImageNames = userImageNames
        self.userImagePaths = userImagePaths
        self.likeCount = likeCount
        self.commentCount = commentCount
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stampId = try container.decode(String.self, forKey: .stampId)
        userId = try container.decode(String.self, forKey: .userId)
        collectedDate = try container.decode(Date.self, forKey: .collectedDate)
        userNotes = try container.decode(String.self, forKey: .userNotes)
        userImageNames = try container.decode([String].self, forKey: .userImageNames)
        // Decode userImagePaths with default empty array if not present (backward compatibility)
        userImagePaths = try container.decodeIfPresent([String].self, forKey: .userImagePaths) ?? []
        // Decode social features with default 0 if not present (backward compatibility)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
    }
}

// MARK: - Backend Integration Notes
// This class currently uses UserDefaults for local persistence
// When adding backend, consider creating a protocol:
//
// protocol UserDataService {
//     func fetchCollectedStamps() async throws -> [CollectedStamp]
//     func saveCollectedStamp(_ stamp: CollectedStamp) async throws
//     func updateStampNotes(stampId: String, notes: String) async throws
//     func deleteAllCollectedStamps() async throws
// }
//
// Then create:
// - LocalUserDataService (current UserDefaults implementation)
// - CloudUserDataService (Firebase/Supabase implementation)
// - Inject the service into this class

class UserStampCollection: ObservableObject {
    @Published private(set) var collectedStamps: [CollectedStamp] = []
    
    // Track which photos are currently uploading (stampId -> Set of filenames)
    @Published var uploadingPhotos: [String: Set<String>] = [:]
    
    // Track failed deletions for retry (storage paths that failed to delete)
    @Published private var pendingDeletions: Set<String> = []
    
    private let userDefaultsKey = "collectedStamps"
    private let pendingDeletionsKey = "pendingDeletions"
    private(set) var currentUserId: String?
    private var allStamps: [CollectedStamp] = [] // Store all stamps, filter by user
    private let firebaseService = FirebaseService.shared
    
    init() {
        loadCollectedStamps()
        loadPendingDeletions()
    }
    
    /// Set the current user and filter stamps to show only their collected stamps
    func setCurrentUser(_ userId: String?) {
        currentUserId = userId
        filterStampsForCurrentUser()
        
        // Fetch from Firestore when user changes
        if let userId = userId {
            Task {
                await syncFromFirestore(userId: userId)
                // Retry any pending deletions when user signs in
                await retryPendingDeletions()
            }
        }
    }
    
    /// Refresh collected stamps from server (pull-to-refresh)
    func refresh(userId: String) async {
        await syncFromFirestore(userId: userId)
        await retryPendingDeletions()
    }
    
    /// Filter stamps to only show current user's stamps
    private func filterStampsForCurrentUser() {
        if let userId = currentUserId {
            collectedStamps = allStamps.filter { $0.userId == userId }
        } else {
            // No user signed in - show nothing
            collectedStamps = []
        }
    }
    
    func isCollected(_ stampId: String) -> Bool {
        collectedStamps.contains { $0.stampId == stampId }
    }
    
    func collectStamp(_ stampId: String, userId: String) {
        guard !isCollected(stampId) else { return }
        
        let newCollection = CollectedStamp(
            stampId: stampId,
            userId: userId,
            collectedDate: Date(),
            userNotes: "",
            userImageNames: [],
            userImagePaths: []
        )
        
        // Optimistic update: Save locally first (instant UX)
        allStamps.append(newCollection)
        collectedStamps.append(newCollection)
        saveCollectedStamps()
        
        // Sync to Firestore in background
        Task {
            do {
                try await firebaseService.saveCollectedStamp(newCollection, for: userId)
                print("✅ Stamp synced to Firestore: \(stampId)")
            } catch {
                print("⚠️ Failed to sync stamp to Firestore: \(error.localizedDescription)")
                // Stamp is still saved locally, will retry on next app launch
            }
        }
    }
    
    func updateNotes(for stampId: String, notes: String) {
        // Update in allStamps
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }) {
            allStamps[allIndex].userNotes = notes
        }
        // Update in filtered collectedStamps
        if let index = collectedStamps.firstIndex(where: { $0.stampId == stampId }) {
            collectedStamps[index].userNotes = notes
        }
        saveCollectedStamps()
        
        // Sync to Firestore
        if let userId = currentUserId {
            Task {
                do {
                    try await firebaseService.updateStampNotes(stampId: stampId, userId: userId, notes: notes)
                    print("✅ Notes synced to Firestore")
                } catch {
                    print("⚠️ Failed to sync notes: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func addImage(for stampId: String, imageName: String, storagePath: String? = nil) {
        // Update in allStamps
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }) {
            allStamps[allIndex].userImageNames.append(imageName)
            if let path = storagePath {
                allStamps[allIndex].userImagePaths.append(path)
            }
        }
        // Update in filtered collectedStamps
        if let index = collectedStamps.firstIndex(where: { $0.stampId == stampId }) {
            collectedStamps[index].userImageNames.append(imageName)
            if let path = storagePath {
                collectedStamps[index].userImagePaths.append(path)
            }
        }
        saveCollectedStamps()
        
        // Sync to Firestore
        if let userId = currentUserId {
            Task {
                do {
                    try await firebaseService.updateStampImages(stampId: stampId, userId: userId, imageNames: collectedStamps.first(where: { $0.stampId == stampId })?.userImageNames ?? [], imagePaths: collectedStamps.first(where: { $0.stampId == stampId })?.userImagePaths ?? [])
                    print("✅ Images synced to Firestore")
                } catch {
                    print("⚠️ Failed to sync images: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Update the storage path for an existing image (called after Firebase upload completes)
    func updateImagePath(for stampId: String, imageName: String, storagePath: String) {
        // Update in allStamps
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }),
           let imageIndex = allStamps[allIndex].userImageNames.firstIndex(of: imageName) {
            // Ensure imagePaths array is large enough
            while allStamps[allIndex].userImagePaths.count <= imageIndex {
                allStamps[allIndex].userImagePaths.append("")
            }
            allStamps[allIndex].userImagePaths[imageIndex] = storagePath
        }
        
        // Update in filtered collectedStamps
        if let index = collectedStamps.firstIndex(where: { $0.stampId == stampId }),
           let imageIndex = collectedStamps[index].userImageNames.firstIndex(of: imageName) {
            // Ensure imagePaths array is large enough
            while collectedStamps[index].userImagePaths.count <= imageIndex {
                collectedStamps[index].userImagePaths.append("")
            }
            collectedStamps[index].userImagePaths[imageIndex] = storagePath
        }
        
        saveCollectedStamps()
        
        // Sync to Firestore
        if let userId = currentUserId {
            Task {
                do {
                    try await firebaseService.updateStampImages(
                        stampId: stampId,
                        userId: userId,
                        imageNames: collectedStamps.first(where: { $0.stampId == stampId })?.userImageNames ?? [],
                        imagePaths: collectedStamps.first(where: { $0.stampId == stampId })?.userImagePaths ?? []
                    )
                    print("✅ Image path synced to Firestore: \(storagePath)")
                } catch {
                    print("⚠️ Failed to sync image path: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func removeImage(for stampId: String, imageName: String) async throws {
        // Get the storage path BEFORE removing from arrays
        var storagePath: String?
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }),
           let imageIndex = allStamps[allIndex].userImageNames.firstIndex(of: imageName),
           imageIndex < allStamps[allIndex].userImagePaths.count {
            storagePath = allStamps[allIndex].userImagePaths[imageIndex]
        }
        
        // STEP 1: Delete from Firebase Storage FIRST (blocking operation)
        if let storagePath = storagePath, !storagePath.isEmpty {
            do {
                try await ImageManager.shared.deleteImageFromFirebase(path: storagePath)
                print("✅ Deleted image from Firebase Storage: \(storagePath)")
                // Remove from pending deletions if it was there
                pendingDeletions.remove(storagePath)
                savePendingDeletions()
            } catch {
                print("⚠️ Failed to delete from Firebase Storage: \(error.localizedDescription)")
                
                // Check if it's a network error - if so, add to pending deletions
                let nsError = error as NSError
                let isNetworkError = nsError.domain == NSURLErrorDomain || 
                                   (nsError.domain == "FIRStorageErrorDomain" && nsError.code == -13030)
                
                if isNetworkError {
                    print("📝 Network error detected - adding to pending deletions for retry")
                    pendingDeletions.insert(storagePath)
                    savePendingDeletions()
                    // Don't throw - allow local deletion to proceed
                    // Will retry when network is available
                } else {
                    // Re-throw non-network errors (permissions, etc)
                    throw error
                }
            }
        } else {
            print("⚠️ No storage path found for image: \(imageName) - skipping Firebase deletion")
        }
        
        // STEP 2: Only after Firebase deletion succeeds (or is queued), update local state
        // Update in allStamps
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }) {
            if let imageIndex = allStamps[allIndex].userImageNames.firstIndex(of: imageName) {
                allStamps[allIndex].userImageNames.remove(at: imageIndex)
                // Remove corresponding storage path if exists
                if imageIndex < allStamps[allIndex].userImagePaths.count {
                    allStamps[allIndex].userImagePaths.remove(at: imageIndex)
                }
            }
        }
        
        // Update in filtered collectedStamps
        if let index = collectedStamps.firstIndex(where: { $0.stampId == stampId }) {
            if let imageIndex = collectedStamps[index].userImageNames.firstIndex(of: imageName) {
                collectedStamps[index].userImageNames.remove(at: imageIndex)
                // Remove corresponding storage path if exists
                if imageIndex < collectedStamps[index].userImagePaths.count {
                    collectedStamps[index].userImagePaths.remove(at: imageIndex)
                }
            }
        }
        
        // STEP 3: Delete local file
        ImageManager.shared.deleteImage(named: imageName)
        saveCollectedStamps()
        
        // STEP 4: Sync to Firestore
        if let userId = currentUserId {
            do {
                try await firebaseService.updateStampImages(
                    stampId: stampId, 
                    userId: userId, 
                    imageNames: collectedStamps.first(where: { $0.stampId == stampId })?.userImageNames ?? [], 
                    imagePaths: collectedStamps.first(where: { $0.stampId == stampId })?.userImagePaths ?? []
                )
                print("✅ Image removal synced to Firestore")
            } catch {
                print("⚠️ Failed to sync image removal to Firestore: \(error.localizedDescription)")
                // Don't throw - local deletion already happened, Firestore will sync later
            }
        }
    }
    
    /// ⚠️ DEVELOPMENT PURPOSES ONLY - Resets all collected stamps
    /// This function is NOT accessible from the UI and should only be used for testing/debugging
    func resetAll() {
        allStamps.removeAll()
        collectedStamps.removeAll()
        uploadingPhotos.removeAll()
        saveCollectedStamps()
        
        // Delete from Firestore
        if let userId = currentUserId {
            Task {
                do {
                    try await firebaseService.deleteAllCollectedStamps(for: userId)
                    print("✅ All stamps deleted from Firestore")
                } catch {
                    print("⚠️ Failed to delete stamps from Firestore: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Uploading Photos Tracking
    
    func addUploadingPhoto(stampId: String, filename: String) {
        if uploadingPhotos[stampId] == nil {
            uploadingPhotos[stampId] = []
        }
        uploadingPhotos[stampId]?.insert(filename)
    }
    
    func removeUploadingPhoto(stampId: String, filename: String) {
        uploadingPhotos[stampId]?.remove(filename)
        if uploadingPhotos[stampId]?.isEmpty == true {
            uploadingPhotos.removeValue(forKey: stampId)
        }
    }
    
    func getUploadingPhotos(for stampId: String) -> Set<String> {
        return uploadingPhotos[stampId] ?? []
    }
    
    // MARK: - Firestore Sync
    
    /// Retry pending deletions (called when network becomes available)
    func retryPendingDeletions() async {
        guard !pendingDeletions.isEmpty else {
            print("✅ No pending deletions to retry")
            return
        }
        
        print("🔄 Retrying \(pendingDeletions.count) pending deletions...")
        
        let pathsToRetry = Array(pendingDeletions)
        for path in pathsToRetry {
            do {
                try await ImageManager.shared.deleteImageFromFirebase(path: path)
                print("✅ Successfully deleted previously failed image: \(path)")
                pendingDeletions.remove(path)
            } catch {
                print("⚠️ Still unable to delete \(path): \(error.localizedDescription)")
                // Keep in pending deletions for next retry
            }
        }
        
        savePendingDeletions()
        
        if pendingDeletions.isEmpty {
            print("✅ All pending deletions completed")
        } else {
            print("⚠️ \(pendingDeletions.count) deletions still pending")
        }
    }
    
    /// Fetch stamps from Firestore and merge with local data
    private func syncFromFirestore(userId: String) async {
        do {
            let firestoreStamps = try await firebaseService.fetchCollectedStamps(for: userId)
            
            await MainActor.run {
                // Merge strategy: Firestore is source of truth
                // Keep local stamps that aren't in Firestore (pending sync)
                // Add Firestore stamps that aren't local
                
                var mergedStamps = allStamps.filter { $0.userId != userId } // Keep other users' local stamps
                
                // Create a dictionary of Firestore stamps for quick lookup
                let firestoreDict = Dictionary(uniqueKeysWithValues: firestoreStamps.map { ($0.stampId, $0) })
                
                // Add all Firestore stamps (they're the source of truth)
                mergedStamps.append(contentsOf: firestoreStamps)
                
                // Add local-only stamps for this user (ones not in Firestore yet - pending sync)
                let localUserStamps = allStamps.filter { $0.userId == userId }
                for localStamp in localUserStamps {
                    if firestoreDict[localStamp.stampId] == nil {
                        // This stamp is local-only, keep it (will sync later)
                        mergedStamps.append(localStamp)
                    }
                }
                
                allStamps = mergedStamps
                saveCollectedStamps()
                filterStampsForCurrentUser()
                
                print("✅ Synced \(firestoreStamps.count) stamps from Firestore")
            }
        } catch {
            print("⚠️ Failed to fetch stamps from Firestore: \(error.localizedDescription)")
            // Fall back to local data (already loaded)
        }
    }
    
    // MARK: - Local Storage
    
    private func saveCollectedStamps() {
        if let encoded = try? JSONEncoder().encode(allStamps) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadCollectedStamps() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([CollectedStamp].self, from: data) {
                allStamps = decoded
                filterStampsForCurrentUser()
            } else {
                // Failed to decode (likely due to schema change) - clear old data
                print("⚠️ Failed to decode collected stamps (schema changed). Clearing old data.")
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
    
    // MARK: - Pending Deletions Persistence
    
    private func savePendingDeletions() {
        let paths = Array(pendingDeletions)
        UserDefaults.standard.set(paths, forKey: pendingDeletionsKey)
        print("💾 Saved \(paths.count) pending deletions")
    }
    
    private func loadPendingDeletions() {
        if let paths = UserDefaults.standard.array(forKey: pendingDeletionsKey) as? [String] {
            pendingDeletions = Set(paths)
            print("📥 Loaded \(paths.count) pending deletions")
        }
    }
}

