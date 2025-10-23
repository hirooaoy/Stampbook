import Foundation
import Combine

class StampsManager: ObservableObject {
    @Published var stamps: [Stamp] = []
    @Published var collections: [Collection] = []
    @Published var userCollection = UserStampCollection()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadStamps()
        loadCollections()
        
        // Forward changes from userCollection to this manager
        userCollection.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    // TODO: BACKEND - Replace with API calls to fetch stamps from server
    // Current: Local JSON bundle files
    // Future: Firebase/Supabase collection of global stamps
    private func loadStamps() {
        guard let url = Bundle.main.url(forResource: "stamps", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decodedStamps = try? JSONDecoder().decode([Stamp].self, from: data) else {
            print("Failed to load stamps.json")
            return
        }
        
        stamps = decodedStamps
    }
    
    // TODO: BACKEND - Replace with API calls to fetch collections from server
    private func loadCollections() {
        guard let url = Bundle.main.url(forResource: "collections", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decodedCollections = try? JSONDecoder().decode([Collection].self, from: data) else {
            print("Failed to load collections.json")
            return
        }
        
        collections = decodedCollections
    }
    
    func isCollected(_ stamp: Stamp) -> Bool {
        userCollection.isCollected(stamp.id)
    }
    
    /// Set the current user - filters collected stamps to show only this user's stamps
    func setCurrentUser(_ userId: String?) {
        userCollection.setCurrentUser(userId)
    }
    
    // MARK: - User Actions
    // TODO: BACKEND - Add location verification before allowing collection
    // TODO: BACKEND - Sync collection to cloud after local save
    func collectStamp(_ stamp: Stamp, userId: String) {
        userCollection.collectStamp(stamp.id, userId: userId)
        // Future: await cloudSync.syncCollectedStamp(stamp.id)
    }
    
    // MARK: - Debug/Testing helpers (remove or gate in production)
    func obtainAll(userId: String) {
        for stamp in stamps {
            userCollection.collectStamp(stamp.id, userId: userId)
        }
    }
    
    func obtainHalf(userId: String) {
        for (index, stamp) in stamps.enumerated() {
            if index % 2 == 0 {
                userCollection.collectStamp(stamp.id, userId: userId)
            }
        }
    }
    
    func resetAll() {
        userCollection.resetAll()
        // Future: await cloudSync.resetUserData()
    }
    
    // Helper methods for collections
    func stampsInCollection(_ collectionId: String) -> [Stamp] {
        stamps.filter { $0.collectionIds.contains(collectionId) }
    }
    
    func collectedStampsInCollection(_ collectionId: String) -> Int {
        let stampsInCollection = stamps.filter { $0.collectionIds.contains(collectionId) }
        let collectedStampIds = Set(userCollection.collectedStamps.map { $0.stampId })
        return stampsInCollection.filter { collectedStampIds.contains($0.id) }.count
    }
}

