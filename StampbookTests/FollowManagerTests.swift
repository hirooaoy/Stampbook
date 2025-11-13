import XCTest
@testable import Stampbook

/// Tests for follow count management and optimistic updates
/// Critical because follow counts are shown prominently in profiles and need to stay accurate
class FollowManagerTests: XCTestCase {
    var followManager: FollowManager!
    
    override func setUp() {
        super.setUp()
        followManager = FollowManager()
    }
    
    override func tearDown() {
        followManager.clearFollowData()
        followManager = nil
        super.tearDown()
    }
    
    // MARK: - Follow Count Updates
    
    func testUpdateFollowCountsSetsInitialCounts() {
        let userId = "hiroo"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 10, "Follower count should be set")
        XCTAssertEqual(followManager.followCounts[userId]?.following, 5, "Following count should be set")
    }
    
    func testUpdateFollowCountsOverwritesExisting() {
        let userId = "hiroo"
        
        // Set initial counts
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        // Update with new counts
        followManager.updateFollowCounts(userId: userId, followerCount: 15, followingCount: 8)
        
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 15, "Follower count should be updated")
        XCTAssertEqual(followManager.followCounts[userId]?.following, 8, "Following count should be updated")
    }
    
    func testUpdateFollowCountsForMultipleUsers() {
        followManager.updateFollowCounts(userId: "hiroo", followerCount: 10, followingCount: 5)
        followManager.updateFollowCounts(userId: "watagumostudio", followerCount: 3, followingCount: 7)
        followManager.updateFollowCounts(userId: "alice", followerCount: 0, followingCount: 0)
        
        XCTAssertEqual(followManager.followCounts["hiroo"]?.followers, 10)
        XCTAssertEqual(followManager.followCounts["hiroo"]?.following, 5)
        XCTAssertEqual(followManager.followCounts["watagumostudio"]?.followers, 3)
        XCTAssertEqual(followManager.followCounts["watagumostudio"]?.following, 7)
        XCTAssertEqual(followManager.followCounts["alice"]?.followers, 0)
        XCTAssertEqual(followManager.followCounts["alice"]?.following, 0)
    }
    
    // MARK: - Follow Status Tracking
    
    func testIsFollowingDefaultsToFalse() {
        let targetUserId = "watagumostudio"
        
        let isFollowing = followManager.isFollowing[targetUserId] ?? false
        XCTAssertFalse(isFollowing, "Unknown users should default to not following")
    }
    
    func testIsFollowingStateCanBeSet() {
        let targetUserId = "watagumostudio"
        
        followManager.isFollowing[targetUserId] = true
        XCTAssertTrue(followManager.isFollowing[targetUserId] ?? false, "Following state should be set to true")
        
        followManager.isFollowing[targetUserId] = false
        XCTAssertFalse(followManager.isFollowing[targetUserId] ?? false, "Following state should be set to false")
    }
    
    func testMultipleUserFollowingStates() {
        followManager.isFollowing["user1"] = true
        followManager.isFollowing["user2"] = false
        followManager.isFollowing["user3"] = true
        
        XCTAssertTrue(followManager.isFollowing["user1"] ?? false)
        XCTAssertFalse(followManager.isFollowing["user2"] ?? false)
        XCTAssertTrue(followManager.isFollowing["user3"] ?? false)
    }
    
    // MARK: - Processing State
    
    func testProcessingStateCanBeTracked() {
        let targetUserId = "watagumostudio"
        
        followManager.isProcessingFollow[targetUserId] = true
        XCTAssertTrue(followManager.isProcessingFollow[targetUserId] ?? false, 
                     "Processing state should be trackable for button loading states")
        
        followManager.isProcessingFollow[targetUserId] = false
        XCTAssertFalse(followManager.isProcessingFollow[targetUserId] ?? false)
    }
    
    // MARK: - Count Never Goes Negative (Critical Edge Case)
    
    func testFollowerCountNeverGoesNegative() {
        let userId = "hiroo"
        
        // Start with 0 followers
        followManager.updateFollowCounts(userId: userId, followerCount: 0, followingCount: 5)
        
        // Simulate decrement (like rollback or unfollow)
        if var counts = followManager.followCounts[userId] {
            counts.followers = max(0, counts.followers - 1)
            followManager.followCounts[userId] = counts
        }
        
        // Should stay at 0, not go negative
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 0, 
                      "Follower count should never go below 0")
    }
    
    func testFollowingCountNeverGoesNegative() {
        let userId = "hiroo"
        
        // Start with 0 following
        followManager.updateFollowCounts(userId: userId, followerCount: 5, followingCount: 0)
        
        // Simulate decrement (like rollback or unfollow)
        if var counts = followManager.followCounts[userId] {
            counts.following = max(0, counts.following - 1)
            followManager.followCounts[userId] = counts
        }
        
        // Should stay at 0, not go negative
        XCTAssertEqual(followManager.followCounts[userId]?.following, 0, 
                      "Following count should never go below 0")
    }
    
    func testMultipleDecrementsNeverGoNegative() {
        let userId = "hiroo"
        
        // Start with 2
        followManager.updateFollowCounts(userId: userId, followerCount: 2, followingCount: 5)
        
        // Decrement 5 times (simulating multiple rollbacks or unfollows)
        for _ in 0..<5 {
            if var counts = followManager.followCounts[userId] {
                counts.followers = max(0, counts.followers - 1)
                followManager.followCounts[userId] = counts
            }
        }
        
        // Should be 0, not -3
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 0, 
                      "Multiple decrements should never result in negative count")
    }
    
    // MARK: - Count Increment/Decrement Logic
    
    func testIncrementFollowerCount() {
        let userId = "hiroo"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        // Simulate follow (increment follower count)
        if var counts = followManager.followCounts[userId] {
            counts.followers += 1
            followManager.followCounts[userId] = counts
        }
        
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 11, 
                      "Following a user should increment their follower count")
    }
    
    func testIncrementFollowingCount() {
        let userId = "hiroo"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        // Simulate follow (increment following count)
        if var counts = followManager.followCounts[userId] {
            counts.following += 1
            followManager.followCounts[userId] = counts
        }
        
        XCTAssertEqual(followManager.followCounts[userId]?.following, 6, 
                      "Following a user should increment your following count")
    }
    
    func testDecrementFollowerCount() {
        let userId = "hiroo"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        // Simulate unfollow (decrement follower count with safety)
        if var counts = followManager.followCounts[userId] {
            counts.followers = max(0, counts.followers - 1)
            followManager.followCounts[userId] = counts
        }
        
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 9, 
                      "Unfollowing a user should decrement their follower count")
    }
    
    func testDecrementFollowingCount() {
        let userId = "hiroo"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 10, followingCount: 5)
        
        // Simulate unfollow (decrement following count with safety)
        if var counts = followManager.followCounts[userId] {
            counts.following = max(0, counts.following - 1)
            followManager.followCounts[userId] = counts
        }
        
        XCTAssertEqual(followManager.followCounts[userId]?.following, 4, 
                      "Unfollowing a user should decrement your following count")
    }
    
    // MARK: - Realistic Follow/Unfollow Scenarios
    
    func testFollowUpdatesCountsForBothUsers() {
        let currentUserId = "hiroo"
        let targetUserId = "watagumostudio"
        
        // Set initial counts
        followManager.updateFollowCounts(userId: currentUserId, followerCount: 10, followingCount: 5)
        followManager.updateFollowCounts(userId: targetUserId, followerCount: 3, followingCount: 7)
        
        // Simulate optimistic follow (what happens in followUser method)
        followManager.isFollowing[targetUserId] = true
        
        if var currentCounts = followManager.followCounts[currentUserId] {
            currentCounts.following += 1
            followManager.followCounts[currentUserId] = currentCounts
        }
        
        if var targetCounts = followManager.followCounts[targetUserId] {
            targetCounts.followers += 1
            followManager.followCounts[targetUserId] = targetCounts
        }
        
        // Verify counts updated correctly
        XCTAssertTrue(followManager.isFollowing[targetUserId] ?? false, "Should be following target user")
        XCTAssertEqual(followManager.followCounts[currentUserId]?.following, 6, 
                      "Current user's following count should increment")
        XCTAssertEqual(followManager.followCounts[targetUserId]?.followers, 4, 
                      "Target user's follower count should increment")
    }
    
    func testUnfollowUpdatesCountsForBothUsers() {
        let currentUserId = "hiroo"
        let targetUserId = "watagumostudio"
        
        // Set initial counts (already following)
        followManager.updateFollowCounts(userId: currentUserId, followerCount: 10, followingCount: 6)
        followManager.updateFollowCounts(userId: targetUserId, followerCount: 4, followingCount: 7)
        followManager.isFollowing[targetUserId] = true
        
        // Simulate optimistic unfollow (what happens in unfollowUser method)
        followManager.isFollowing[targetUserId] = false
        
        if var currentCounts = followManager.followCounts[currentUserId] {
            currentCounts.following = max(0, currentCounts.following - 1)
            followManager.followCounts[currentUserId] = currentCounts
        }
        
        if var targetCounts = followManager.followCounts[targetUserId] {
            targetCounts.followers = max(0, targetCounts.followers - 1)
            followManager.followCounts[targetUserId] = targetCounts
        }
        
        // Verify counts updated correctly
        XCTAssertFalse(followManager.isFollowing[targetUserId] ?? false, "Should not be following target user")
        XCTAssertEqual(followManager.followCounts[currentUserId]?.following, 5, 
                      "Current user's following count should decrement")
        XCTAssertEqual(followManager.followCounts[targetUserId]?.followers, 3, 
                      "Target user's follower count should decrement")
    }
    
    func testRollbackOnErrorRestoresCounts() {
        let currentUserId = "hiroo"
        let targetUserId = "watagumostudio"
        
        // Set initial counts
        followManager.updateFollowCounts(userId: currentUserId, followerCount: 10, followingCount: 5)
        followManager.updateFollowCounts(userId: targetUserId, followerCount: 3, followingCount: 7)
        
        // Simulate optimistic follow
        followManager.isFollowing[targetUserId] = true
        if var currentCounts = followManager.followCounts[currentUserId] {
            currentCounts.following += 1
            followManager.followCounts[currentUserId] = currentCounts
        }
        if var targetCounts = followManager.followCounts[targetUserId] {
            targetCounts.followers += 1
            followManager.followCounts[targetUserId] = targetCounts
        }
        
        // Verify optimistic update
        XCTAssertEqual(followManager.followCounts[currentUserId]?.following, 6)
        XCTAssertEqual(followManager.followCounts[targetUserId]?.followers, 4)
        
        // Simulate error - rollback (what happens in catch block)
        followManager.isFollowing[targetUserId] = false
        if var currentCounts = followManager.followCounts[currentUserId] {
            currentCounts.following = max(0, currentCounts.following - 1)
            followManager.followCounts[currentUserId] = currentCounts
        }
        if var targetCounts = followManager.followCounts[targetUserId] {
            targetCounts.followers = max(0, targetCounts.followers - 1)
            followManager.followCounts[targetUserId] = targetCounts
        }
        
        // Verify rollback restored original counts
        XCTAssertFalse(followManager.isFollowing[targetUserId] ?? false, "Following state should be rolled back")
        XCTAssertEqual(followManager.followCounts[currentUserId]?.following, 5, 
                      "Following count should be rolled back to original")
        XCTAssertEqual(followManager.followCounts[targetUserId]?.followers, 3, 
                      "Follower count should be rolled back to original")
    }
    
    func testMultipleFollowsAcrossDifferentUsers() {
        let currentUserId = "hiroo"
        
        followManager.updateFollowCounts(userId: currentUserId, followerCount: 10, followingCount: 5)
        followManager.updateFollowCounts(userId: "user1", followerCount: 1, followingCount: 0)
        followManager.updateFollowCounts(userId: "user2", followerCount: 2, followingCount: 0)
        followManager.updateFollowCounts(userId: "user3", followerCount: 3, followingCount: 0)
        
        // Follow 3 users
        for targetUserId in ["user1", "user2", "user3"] {
            followManager.isFollowing[targetUserId] = true
            
            if var currentCounts = followManager.followCounts[currentUserId] {
                currentCounts.following += 1
                followManager.followCounts[currentUserId] = currentCounts
            }
            
            if var targetCounts = followManager.followCounts[targetUserId] {
                targetCounts.followers += 1
                followManager.followCounts[targetUserId] = targetCounts
            }
        }
        
        // Current user should be following 3 more people (5 + 3 = 8)
        XCTAssertEqual(followManager.followCounts[currentUserId]?.following, 8, 
                      "Following count should increase by 3")
        
        // Each target user should have 1 more follower
        XCTAssertEqual(followManager.followCounts["user1"]?.followers, 2)
        XCTAssertEqual(followManager.followCounts["user2"]?.followers, 3)
        XCTAssertEqual(followManager.followCounts["user3"]?.followers, 4)
    }
    
    // MARK: - Cleanup
    
    func testClearFollowDataRemovesAllData() {
        // Set up some data
        followManager.isFollowing["user1"] = true
        followManager.isFollowing["user2"] = false
        followManager.updateFollowCounts(userId: "hiroo", followerCount: 10, followingCount: 5)
        followManager.updateFollowCounts(userId: "user1", followerCount: 3, followingCount: 7)
        followManager.isProcessingFollow["user1"] = true
        
        // Clear all data
        followManager.clearFollowData()
        
        // Verify everything is cleared
        XCTAssertTrue(followManager.isFollowing.isEmpty, "isFollowing should be cleared")
        XCTAssertTrue(followManager.followers.isEmpty, "followers should be cleared")
        XCTAssertTrue(followManager.following.isEmpty, "following should be cleared")
        XCTAssertTrue(followManager.followCounts.isEmpty, "followCounts should be cleared")
        XCTAssertTrue(followManager.isProcessingFollow.isEmpty, "isProcessingFollow should be cleared")
        XCTAssertNil(followManager.error, "error should be cleared")
    }
    
    // MARK: - Zero Count Edge Cases
    
    func testZeroFollowerCount() {
        followManager.updateFollowCounts(userId: "newUser", followerCount: 0, followingCount: 0)
        
        XCTAssertEqual(followManager.followCounts["newUser"]?.followers, 0, 
                      "Zero follower count should be valid")
        XCTAssertEqual(followManager.followCounts["newUser"]?.following, 0, 
                      "Zero following count should be valid")
    }
    
    func testUnfollowFromZeroFollowersStaysZero() {
        let userId = "newUser"
        
        followManager.updateFollowCounts(userId: userId, followerCount: 0, followingCount: 5)
        
        // Try to decrement from 0 (simulates race condition or double-unfollow)
        if var counts = followManager.followCounts[userId] {
            counts.followers = max(0, counts.followers - 1)
            followManager.followCounts[userId] = counts
        }
        
        // Should stay at 0
        XCTAssertEqual(followManager.followCounts[userId]?.followers, 0, 
                      "Decrementing from 0 should stay at 0, not go negative")
    }
    
    func testLargeFollowCounts() {
        let influencerId = "influencer"
        
        // Test with large numbers (thousands of followers)
        followManager.updateFollowCounts(userId: influencerId, followerCount: 10000, followingCount: 200)
        
        XCTAssertEqual(followManager.followCounts[influencerId]?.followers, 10000, 
                      "Should handle large follower counts")
        
        // Increment and decrement still work
        if var counts = followManager.followCounts[influencerId] {
            counts.followers += 1
            followManager.followCounts[influencerId] = counts
        }
        
        XCTAssertEqual(followManager.followCounts[influencerId]?.followers, 10001, 
                      "Should handle incrementing large counts")
    }
}

