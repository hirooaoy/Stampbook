import Foundation
import Combine

/// Represents a bookmarked stamp (saved for later)
struct BookmarkedStamp: Codable, Identifiable, Equatable {
    var id: String { stampId }
    let stampId: String
    let userId: String
    let bookmarkedDate: Date
    
    enum CodingKeys: String, CodingKey {
        case stampId, userId, bookmarkedDate
    }
    
    init(stampId: String, userId: String, bookmarkedDate: Date) {
        self.stampId = stampId
        self.userId = userId
        self.bookmarkedDate = bookmarkedDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stampId = try container.decode(String.self, forKey: .stampId)
        userId = try container.decode(String.self, forKey: .userId)
        bookmarkedDate = try container.decode(Date.self, forKey: .bookmarkedDate)
    }
}

/// Manages user's bookmarked stamps (stamps saved for later)
class UserBookmarkCollection: ObservableObject {
    @Published private(set) var bookmarkedStamps: [BookmarkedStamp] = []
    
    private let userDefaultsKey = "bookmarkedStamps"
    private(set) var currentUserId: String?
    private var allBookmarks: [BookmarkedStamp] = [] // Store all bookmarks, filter by user
    private let firebaseService = FirebaseService.shared
    
    init() {
        loadBookmarkedStamps()
    }
    
    /// Set the current user and filter bookmarks to show only their bookmarks
    func setCurrentUser(_ userId: String?) {
        currentUserId = userId
        filterBookmarksForCurrentUser()
        
        // Fetch from Firestore when user changes
        if let userId = userId {
            Task {
                await syncFromFirestore(userId: userId)
            }
        }
    }
    
    /// Refresh bookmarked stamps from server (pull-to-refresh)
    func refresh(userId: String) async {
        await syncFromFirestore(userId: userId, forceRefresh: true)
    }
    
    /// Filter bookmarks to only show current user's bookmarks
    private func filterBookmarksForCurrentUser() {
        if let userId = currentUserId {
            bookmarkedStamps = allBookmarks.filter { $0.userId == userId }
        } else {
            bookmarkedStamps = []
        }
    }
    
    func isBookmarked(_ stampId: String) -> Bool {
        bookmarkedStamps.contains { $0.stampId == stampId }
    }
    
    /// Add bookmark
    func addBookmark(_ stampId: String, userId: String) {
        #if DEBUG
        print("🔖 [UserBookmarkCollection] addBookmark called: \(stampId) for user: \(userId)")
        #endif
        
        guard !isBookmarked(stampId) else { 
            #if DEBUG
            print("🔖 [UserBookmarkCollection] Already bookmarked: \(stampId)")
            #endif
            return 
        }
        
        let newBookmark = BookmarkedStamp(
            stampId: stampId,
            userId: userId,
            bookmarkedDate: Date()
        )
        
        // Optimistic update: Save locally first (instant UX)
        allBookmarks.append(newBookmark)
        bookmarkedStamps.append(newBookmark)
        saveBookmarkedStamps()
        
        #if DEBUG
        print("🔖 [UserBookmarkCollection] Bookmark added locally. Total bookmarks: \(bookmarkedStamps.count)")
        print("🔖 [UserBookmarkCollection] Bookmarked stamp IDs: \(bookmarkedStamps.map { $0.stampId })")
        #endif
        
        // Sync to Firestore in background
        Task {
            do {
                try await firebaseService.saveBookmarkedStamp(newBookmark, for: userId)
                #if DEBUG
                print("🔖 [UserBookmarkCollection] Bookmark synced to Firestore: \(stampId)")
                #endif
            } catch {
                print("⚠️ Failed to sync bookmark to Firestore: \(error.localizedDescription)")
                // Bookmark is still saved locally, will retry on next app launch
            }
        }
    }
    
    /// Remove bookmark
    func removeBookmark(_ stampId: String, userId: String) {
        #if DEBUG
        print("🔖 [UserBookmarkCollection] removeBookmark called: \(stampId) for user: \(userId)")
        #endif
        
        // Update in allBookmarks
        allBookmarks.removeAll { $0.stampId == stampId && $0.userId == userId }
        
        // Update in filtered bookmarkedStamps
        bookmarkedStamps.removeAll { $0.stampId == stampId }
        
        saveBookmarkedStamps()
        
        #if DEBUG
        print("🔖 [UserBookmarkCollection] Bookmark removed locally. Total bookmarks: \(bookmarkedStamps.count)")
        #endif
        
        // Sync to Firestore
        Task {
            do {
                try await firebaseService.deleteBookmarkedStamp(stampId: stampId, for: userId)
                #if DEBUG
                print("🔖 [UserBookmarkCollection] Bookmark removal synced to Firestore")
                #endif
            } catch {
                print("⚠️ Failed to sync bookmark removal: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch bookmarks from Firestore and merge with local data
    private func syncFromFirestore(userId: String, forceRefresh: Bool = false) async {
        do {
            let firestoreBookmarks = try await firebaseService.fetchBookmarkedStamps(for: userId, forceRefresh: forceRefresh)
            
            await MainActor.run {
                // Merge strategy: Firestore is source of truth
                var mergedBookmarks = allBookmarks.filter { $0.userId != userId } // Keep other users' local bookmarks
                
                // Add all Firestore bookmarks
                mergedBookmarks.append(contentsOf: firestoreBookmarks)
                
                // Add local-only bookmarks (pending sync)
                let firestoreDict = Dictionary(uniqueKeysWithValues: firestoreBookmarks.map { ($0.stampId, $0) })
                let localUserBookmarks = allBookmarks.filter { $0.userId == userId }
                for localBookmark in localUserBookmarks {
                    if firestoreDict[localBookmark.stampId] == nil {
                        mergedBookmarks.append(localBookmark)
                    }
                }
                
                allBookmarks = mergedBookmarks
                saveBookmarkedStamps()
                filterBookmarksForCurrentUser()
                
                print("✅ Synced \(firestoreBookmarks.count) bookmarks from Firestore")
            }
        } catch {
            print("⚠️ Failed to fetch bookmarks from Firestore: \(error.localizedDescription)")
            // Fall back to local data
        }
    }
    
    // MARK: - Local Storage
    
    func saveBookmarkedStamps() {
        if let encoded = try? JSONEncoder().encode(allBookmarks) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
    
    private func loadBookmarkedStamps() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey) {
            if let decoded = try? JSONDecoder().decode([BookmarkedStamp].self, from: data) {
                allBookmarks = decoded
                filterBookmarksForCurrentUser()
            } else {
                print("⚠️ Failed to decode bookmarked stamps. Clearing old data.")
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }
}

