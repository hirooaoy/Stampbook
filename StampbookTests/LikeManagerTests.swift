import XCTest
@testable import Stampbook

/// Tests for like/unlike logic and optimistic UI updates
/// Critical because like count bugs have been a recurring issue
class LikeManagerTests: XCTestCase {
    var likeManager: LikeManager!
    
    override func setUp() {
        super.setUp()
        likeManager = LikeManager()
    }
    
    override func tearDown() {
        likeManager.clearCache()
        likeManager = nil
        super.tearDown()
    }
    
    // MARK: - Basic Like/Unlike
    
    func testToggleLikeIncrementsCount() {
        let postId = "user123-stamp456"
        
        // Initial state: not liked
        XCTAssertFalse(likeManager.isLiked(postId: postId), "Post should initially not be liked")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 0, "Initial like count should be 0")
        
        // After toggling: should be liked with count 1
        likeManager.toggleLike(postId: postId, stampId: "stamp456", 
                              userId: "currentUser", postOwnerId: "user123")
        
        XCTAssertTrue(likeManager.isLiked(postId: postId), "Post should be liked after toggle")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 1, "Like count should be 1 after liking")
    }
    
    func testToggleLikeTwiceReturnsToZero() {
        let postId = "user123-stamp456"
        
        // Like
        likeManager.toggleLike(postId: postId, stampId: "stamp456",
                              userId: "currentUser", postOwnerId: "user123")
        XCTAssertTrue(likeManager.isLiked(postId: postId))
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 1)
        
        // Unlike
        likeManager.toggleLike(postId: postId, stampId: "stamp456",
                              userId: "currentUser", postOwnerId: "user123")
        XCTAssertFalse(likeManager.isLiked(postId: postId), "Post should be unliked after second toggle")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 0, "Like count should return to 0")
    }
    
    func testLikeMultiplePosts() {
        let postId1 = "user1-stamp1"
        let postId2 = "user2-stamp2"
        
        likeManager.toggleLike(postId: postId1, stampId: "stamp1",
                              userId: "currentUser", postOwnerId: "user1")
        likeManager.toggleLike(postId: postId2, stampId: "stamp2",
                              userId: "currentUser", postOwnerId: "user2")
        
        XCTAssertTrue(likeManager.isLiked(postId: postId1), "First post should be liked")
        XCTAssertTrue(likeManager.isLiked(postId: postId2), "Second post should be liked")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId1), 1)
        XCTAssertEqual(likeManager.getLikeCount(postId: postId2), 1)
    }
    
    // MARK: - Like Count Edge Cases
    
    func testRapidTogglesMaintainCorrectCount() {
        let postId = "user123-stamp456"
        
        // Simulate rapid toggling (e.g., accidental double-tap or network lag)
        // Toggle 7 times in quick succession
        for _ in 0..<7 {
            likeManager.toggleLike(postId: postId, stampId: "stamp456",
                                  userId: "currentUser", postOwnerId: "user123")
        }
        
        // After 7 toggles (odd number), should be liked with count 1
        XCTAssertTrue(likeManager.isLiked(postId: postId), "After odd number of toggles, should be liked")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 1, "Like count should be 1 after odd toggles")
        XCTAssertGreaterThanOrEqual(likeManager.getLikeCount(postId: postId), 0, "Count should never go negative")
        
        // Toggle one more time (8 total - even number)
        likeManager.toggleLike(postId: postId, stampId: "stamp456",
                              userId: "currentUser", postOwnerId: "user123")
        
        // After 8 toggles (even number), should be unliked with count 0
        XCTAssertFalse(likeManager.isLiked(postId: postId), "After even number of toggles, should be unliked")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 0, "Like count should return to 0")
    }
    
    func testSetInitialLikeCounts() {
        let counts = [
            "post1": 5,
            "post2": 10,
            "post3": 0
        ]
        
        likeManager.setLikeCounts(counts)
        
        XCTAssertEqual(likeManager.getLikeCount(postId: "post1"), 5)
        XCTAssertEqual(likeManager.getLikeCount(postId: "post2"), 10)
        XCTAssertEqual(likeManager.getLikeCount(postId: "post3"), 0)
    }
    
    func testUpdateLikeCountWithFreshData() {
        let postId = "user123-stamp456"
        
        // Set initial count from feed
        likeManager.updateLikeCount(postId: postId, count: 5)
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 5)
        
        // Update with new count (simulate feed refresh)
        likeManager.updateLikeCount(postId: postId, count: 10)
        XCTAssertEqual(likeManager.getLikeCount(postId: postId), 10, "Should update with fresh data")
    }
    
    // MARK: - Default Values
    
    func testGetLikeCountForUnknownPost() {
        let unknownPostId = "unknown-post"
        
        let count = likeManager.getLikeCount(postId: unknownPostId)
        XCTAssertEqual(count, 0, "Unknown posts should default to 0 likes")
    }
    
    func testIsLikedForUnknownPost() {
        let unknownPostId = "unknown-post"
        
        let isLiked = likeManager.isLiked(postId: unknownPostId)
        XCTAssertFalse(isLiked, "Unknown posts should default to not liked")
    }
    
    // MARK: - Cache Management
    
    func testClearCacheRemovesAllData() {
        let postId1 = "user1-stamp1"
        let postId2 = "user2-stamp2"
        
        // Like some posts
        likeManager.toggleLike(postId: postId1, stampId: "stamp1",
                              userId: "currentUser", postOwnerId: "user1")
        likeManager.toggleLike(postId: postId2, stampId: "stamp2",
                              userId: "currentUser", postOwnerId: "user2")
        
        XCTAssertTrue(likeManager.isLiked(postId: postId1))
        XCTAssertTrue(likeManager.isLiked(postId: postId2))
        
        // Clear cache
        likeManager.clearCache()
        
        XCTAssertFalse(likeManager.isLiked(postId: postId1), "Cache should be cleared")
        XCTAssertFalse(likeManager.isLiked(postId: postId2), "Cache should be cleared")
        XCTAssertEqual(likeManager.getLikeCount(postId: postId1), 0)
        XCTAssertEqual(likeManager.getLikeCount(postId: postId2), 0)
    }
    
    // MARK: - Post ID Format
    
    func testPostIdFormat() {
        let userId = "hiroo"
        let stampId = "golden-gate-bridge"
        let expectedPostId = "\(userId)-\(stampId)"
        
        XCTAssertEqual(expectedPostId, "hiroo-golden-gate-bridge", "Post ID should follow userId-stampId format")
    }
    
    func testMultipleUsersCanLikeSameStamp() {
        // User 1 likes the stamp
        let postId1 = "user1-stamp456"
        likeManager.toggleLike(postId: postId1, stampId: "stamp456",
                              userId: "currentUser", postOwnerId: "user1")
        
        // User 2 also collected and liked the same stamp
        let postId2 = "user2-stamp456"
        likeManager.toggleLike(postId: postId2, stampId: "stamp456",
                              userId: "currentUser", postOwnerId: "user2")
        
        XCTAssertTrue(likeManager.isLiked(postId: postId1), "User 1's post should be liked")
        XCTAssertTrue(likeManager.isLiked(postId: postId2), "User 2's post should be liked")
        XCTAssertNotEqual(postId1, postId2, "Different users' posts should have different IDs")
    }
}

