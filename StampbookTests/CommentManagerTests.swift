import XCTest
@testable import Stampbook

/// Tests for comment count persistence
/// Verifies Fix #2: Comment count cache to prevent stale counts after deletion
class CommentManagerTests: XCTestCase {
    var commentManager: CommentManager!
    
    override func setUp() {
        super.setUp()
        commentManager = CommentManager()
    }
    
    override func tearDown() {
        commentManager.clearCache()
        commentManager = nil
        super.tearDown()
    }
    
    // MARK: - Basic Comment Count Tests
    
    func testGetCommentCountForUnknownPost() {
        let unknownPostId = "unknown-post"
        
        let count = commentManager.getCommentCount(postId: unknownPostId)
        XCTAssertEqual(count, 0, "Unknown posts should default to 0 comments")
    }
    
    func testSetInitialCommentCounts() {
        let counts = [
            "post1": 5,
            "post2": 10,
            "post3": 0
        ]
        
        commentManager.setCommentCounts(counts)
        
        XCTAssertEqual(commentManager.getCommentCount(postId: "post1"), 5)
        XCTAssertEqual(commentManager.getCommentCount(postId: "post2"), 10)
        XCTAssertEqual(commentManager.getCommentCount(postId: "post3"), 0)
    }
    
    func testUpdateCommentCount() {
        let postId = "user123-stamp456"
        
        // Set initial count
        commentManager.updateCommentCount(postId: postId, count: 5, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 5)
        
        // Update count (simulate feed refresh)
        commentManager.updateCommentCount(postId: postId, count: 10, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 10, 
                      "Should update with fresh data when forceUpdate=true")
    }
    
    func testUpdateCommentCountPreservesExisting() {
        let postId = "user123-stamp456"
        
        // Set initial count
        commentManager.updateCommentCount(postId: postId, count: 5, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 5)
        
        // Try to update without forceUpdate - should NOT update
        commentManager.updateCommentCount(postId: postId, count: 10, forceUpdate: false)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 5, 
                      "Should preserve existing count when forceUpdate=false")
    }
    
    // MARK: - Comment Count Persistence Tests (NEW - Bug Fix Verification)
    
    /// Test that comment counts persist across manager instances (simulates app restart)
    /// This verifies Fix #2: Comment count persistence to prevent stale counts after deletion
    func testCommentCountPersistsAcrossInstances() {
        let postId = "user123-stamp456"
        
        // Set comment count
        commentManager.updateCommentCount(postId: postId, count: 5, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 5)
        
        // Simulate app restart: create new manager instance (let Swift ARC handle cleanup)
        let newCommentManager = CommentManager()
        
        // Verify comment count persists (THIS IS THE BUG FIX!)
        XCTAssertEqual(newCommentManager.getCommentCount(postId: postId), 5, 
                      "Comment count should persist across app restarts")
    }
    
    /// Test that zero comment count persists (THE MAIN BUG FIX!)
    /// This was the original bug: deleting a comment would show 0, but after restart it would show 1
    func testZeroCommentCountPersistsAfterDeletion() {
        let postId = "user123-stamp456"
        
        // Start with 1 comment
        commentManager.updateCommentCount(postId: postId, count: 1, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 1)
        
        // Delete comment (simulate)
        commentManager.updateCommentCount(postId: postId, count: 0, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 0)
        
        // Simulate app restart (THIS IS WHERE THE BUG WAS!) - let Swift ARC handle cleanup
        let newCommentManager = CommentManager()
        
        // Verify count stays 0 (not 1 from stale cache)
        XCTAssertEqual(newCommentManager.getCommentCount(postId: postId), 0, 
                      "Zero comment count should persist after deletion (prevents showing stale count 1)")
    }
    
    /// Test that multiple comment counts persist correctly
    func testMultipleCommentCountsPersist() {
        let posts = [
            "post1": 3,
            "post2": 7,
            "post3": 0
        ]
        
        commentManager.setCommentCounts(posts)
        
        XCTAssertEqual(commentManager.getCommentCount(postId: "post1"), 3)
        XCTAssertEqual(commentManager.getCommentCount(postId: "post2"), 7)
        XCTAssertEqual(commentManager.getCommentCount(postId: "post3"), 0)
        
        // Simulate app restart - let Swift ARC handle cleanup
        let newCommentManager = CommentManager()
        
        // Verify all counts persist
        XCTAssertEqual(newCommentManager.getCommentCount(postId: "post1"), 3, 
                      "Post 1 comment count should persist")
        XCTAssertEqual(newCommentManager.getCommentCount(postId: "post2"), 7, 
                      "Post 2 comment count should persist")
        XCTAssertEqual(newCommentManager.getCommentCount(postId: "post3"), 0, 
                      "Post 3 comment count should persist")
    }
    
    /// Test that clearCache removes persisted counts
    func testClearCacheRemovesPersistedCounts() {
        let postId = "user123-stamp456"
        
        // Set comment count
        commentManager.updateCommentCount(postId: postId, count: 5, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 5)
        
        // Clear cache using the manager's method
        commentManager.clearCache()
        
        // Verify data is cleared in memory
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 0, 
                      "Cached comment count should be cleared")
        
        // Verify UserDefaults was cleared
        let cachedCounts = UserDefaults.standard.dictionary(forKey: "commentCounts") as? [String: Int]
        XCTAssertNil(cachedCounts, "commentCounts should be removed from UserDefaults")
    }
    
    /// Test realistic scenario: add comment → delete → restart
    func testRealisticAddDeleteRestartScenario() {
        let postId = "user123-stamp456"
        
        // Initial state: no comments
        commentManager.updateCommentCount(postId: postId, count: 0, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 0)
        
        // User adds a comment
        commentManager.updateCommentCount(postId: postId, count: 1, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 1)
        
        // Simulate app restart #1 (comment should still be there) - let Swift ARC handle cleanup
        do {
            let newManager = CommentManager()
            XCTAssertEqual(newManager.getCommentCount(postId: postId), 1, 
                          "Comment should persist after first restart")
        }
        
        // User deletes the comment
        commentManager.updateCommentCount(postId: postId, count: 0, forceUpdate: true)
        XCTAssertEqual(commentManager.getCommentCount(postId: postId), 0)
        
        // Simulate app restart #2 (THIS WAS THE BUG - would show 1 instead of 0) - let Swift ARC handle cleanup
        do {
            let newManager = CommentManager()
            XCTAssertEqual(newManager.getCommentCount(postId: postId), 0, 
                          "Deleted comment count should stay 0 after restart (THE BUG FIX!)")
        }
    }
    
    /// Test that init() loads cached counts
    func testInitLoadsCache() {
        let postId = "user123-stamp456"
        
        // Set count in first manager
        commentManager.updateCommentCount(postId: postId, count: 42, forceUpdate: true)
        
        // Create new manager (init should load from cache) - let Swift ARC handle cleanup
        let newManager = CommentManager()
        
        // Verify count was loaded in init
        XCTAssertEqual(newManager.getCommentCount(postId: postId), 42, 
                      "init() should load cached comment counts")
    }
}

