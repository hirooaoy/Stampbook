import Foundation
import Combine

// TODO: BACKEND - Consider adding collectionLocation (lat/long where user actually collected it)
struct CollectedStamp: Codable, Identifiable {
    var id: String { stampId } // Make it Identifiable for Firestore
    let stampId: String
    let userId: String
    let collectedDate: Date
    var userNotes: String
    var userImageNames: [String] // References to locally saved images
    // Future fields:
    // var collectionLocation: CLLocationCoordinate2D?
    // var isPublic: Bool = false (for social features)
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
    
    private let userDefaultsKey = "collectedStamps"
    private var currentUserId: String?
    private var allStamps: [CollectedStamp] = [] // Store all stamps, filter by user
    private let firebaseService = FirebaseService.shared
    
    init() {
        loadCollectedStamps()
    }
    
    /// Set the current user and filter stamps to show only their collected stamps
    func setCurrentUser(_ userId: String?) {
        currentUserId = userId
        filterStampsForCurrentUser()
        
        // Fetch from Firestore when user changes
        if let userId = userId {
            Task {
                await syncFromFirestore(userId: userId)
            }
        }
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
            userImageNames: []
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
    
    func addImage(for stampId: String, imageName: String) {
        // Update in allStamps
        if let allIndex = allStamps.firstIndex(where: { $0.stampId == stampId }) {
            allStamps[allIndex].userImageNames.append(imageName)
        }
        // Update in filtered collectedStamps
        if let index = collectedStamps.firstIndex(where: { $0.stampId == stampId }) {
            collectedStamps[index].userImageNames.append(imageName)
        }
        saveCollectedStamps()
    }
    
    func resetAll() {
        allStamps.removeAll()
        collectedStamps.removeAll()
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
    
    // MARK: - Firestore Sync
    
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
}

