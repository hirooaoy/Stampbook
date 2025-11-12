# Comment & Like Count Bug Investigation

## Issues Reported

### Comment Count Bug
1. User leaves a comment, deletes it → shows 0 ✅
2. User closes app, kills it, comes back → shows 1 ❌
3. User clicks comment icon → loads no comments ✅
4. When closes comment sheet → shows 0 again ✅

### Like Bug  
1. User likes their own post ✅
2. User kills the app, comes back → shows filled heart icon with 0 likes ❌
3. Then instantly changes to 1 ✅
4. **Question: Why is the heart icon filled to begin with?** ❌

---

## Deep Code Investigation

### Architecture Overview

The app has a sophisticated caching system with multiple layers:

1. **LikeManager**: Manages like state with UserDefaults persistence
2. **CommentManager**: Manages comment state with NO persistence
3. **FeedManager**: Manages feed posts with disk cache (JSON file)
4. **Feed Loading Flow**: Instagram-style with disk cache → Firebase fetch

### What Happens on App Cold Start

```
T+0ms:   App launches
T+1ms:   LikeManager.init() → loads cached liked posts from UserDefaults ✅
T+2ms:   CommentManager.init() → NO cached comment counts loaded ❌
T+50ms:  FeedManager loads disk cache (feed_cache.json)
         - Contains STALE like/comment counts from last session
T+100ms: FeedView appears → feedPosts displayed with stale counts
T+200ms: Firebase fetch begins
T+500ms: Fresh feed data arrives from Firebase
```

---

## Root Cause Analysis

### Problem 1: CommentManager Has NO Persistence

**Location**: `Stampbook/Managers/CommentManager.swift`

```swift
class CommentManager: ObservableObject {
    @Published private(set) var comments: [String: [Comment]] = [:] 
    @Published private(set) var commentCounts: [String: Int] = [:] 
    // ❌ NO UserDefaults persistence
    // ❌ NO init() that loads cache
}
```

**Unlike LikeManager**:
```swift
class LikeManager: ObservableObject {
    @Published private(set) var likedPosts: Set<String> = []
    @Published private(set) var likeCounts: [String: Int] = [:]
    
    init() {
        loadCachedLikes() // ✅ Loads from UserDefaults
    }
    
    private func saveCachedLikes() {
        UserDefaults.standard.set(Array(likedPosts), forKey: "likedPosts")
    }
}
```

**What happens**:
1. User deletes comment → optimistic update → shows 0 ✅
2. App is killed → CommentManager.commentCounts is lost (not persisted)
3. App restarts → CommentManager has empty commentCounts
4. FeedManager loads disk cache with STALE count (1) from before deletion
5. PostView.onAppear calls `commentManager.updateCommentCount(postId: postId, count: commentCount, forceUpdate: true)`
6. This OVERWRITES the empty count with stale disk cache count
7. UI shows 1 ❌

### Problem 2: LikeManager Persistence vs Feed Disk Cache Race

**Location**: `Stampbook/Managers/LikeManager.swift` + `Stampbook/Managers/FeedManager.swift`

**The Race Condition**:

```
T+0ms:  LikeManager.init() loads cached likes from UserDefaults
        - likedPosts contains "hiroo-stamp123" ✅
        - likeCounts is EMPTY (no count cached)

T+50ms: FeedManager loads disk cache
        - Post "hiroo-stamp123" has likeCount: 0 (stale)
        
T+100ms: PostView renders
         - isLiked = likeManager.isLiked(postId) = TRUE ✅ (heart filled)
         - currentLikeCount = likeManager.getLikeCount(postId) = 0 ❌
         
T+200ms: FeedContent.loadFeedIfNeeded() completes
         - Calls likeManager.setLikeCounts() with fresh Firebase data
         - Now likeCounts["hiroo-stamp123"] = 1
         
T+250ms: UI updates
         - isLiked = TRUE ✅
         - currentLikeCount = 1 ✅
```

**Why heart is filled but count is 0**:

1. LikeManager caches `likedPosts` (Set of postIds) in UserDefaults ✅
2. LikeManager does NOT cache `likeCounts` (counts) in UserDefaults ❌
3. On cold start, `isLiked` returns TRUE (from UserDefaults)
4. But `getLikeCount` returns 0 (default, no cached count)
5. Feed load then populates counts → UI updates → shows 1

**Location**: `Stampbook/Managers/LikeManager.swift:159-162`
```swift
/// Set initial like counts (called when feed loads)
func setLikeCounts(_ counts: [String: Int]) {
    likeCounts = counts // ❌ Overwrites all counts, no persistence
}
```

### Problem 3: Inconsistent Caching Strategy

**Good Code (LikeManager)**:
- ✅ Persists liked post IDs to UserDefaults
- ✅ Loads cache in init() before any views render
- ✅ Optimistic updates with proper rollback
- ❌ Does NOT persist like counts

**Inconsistent Code (CommentManager)**:
- ❌ NO persistence at all
- ❌ NO init() cache loading
- ✅ Optimistic updates with proper rollback
- ❌ Relies entirely on feed data for counts

**Feed Disk Cache**:
- ✅ Persists full feed posts with counts
- ✅ Instagram-style instant perceived load
- ❌ Can become stale (5 minute refresh interval)
- ❌ Overrides manager state on cold start

---

## Why This Happens: Detailed Flow

### Comment Count Bug Flow

```
1. User adds comment
   → CommentManager.addComment() 
   → Optimistic: commentCounts["post-123"] = 1
   → Firebase: creates comment doc + increments count

2. User deletes comment  
   → CommentManager.deleteComment()
   → Optimistic: commentCounts["post-123"] = 0
   → Firebase: deletes comment doc + decrements count
   → Refetch: fetchComments() → 0 comments
   → Updates: commentCounts["post-123"] = 0
   → Callback: onCommentCountChanged?("post-123", 0)
   → FeedManager updates its cached post

3. User kills app
   → CommentManager.commentCounts is lost (no persistence)
   → FeedManager saves disk cache with count: 0 (correct!)

4. User reopens app
   → LikeManager.init() loads cache
   → CommentManager.init() does nothing (no cache)
   → FeedManager loads disk cache → feedPosts with count: 0
   → BUT: Firebase hasn't been fetched yet

5. PostView.onAppear
   → commentManager.updateCommentCount(postId, count: 0, forceUpdate: true)
   → Sets commentCounts["post-123"] = 0 ✅

6. Firebase fetch completes
   → FeedManager gets fresh data with count: 1 (WHY?)
   → Because Firebase transaction had a timing issue
   → OR the count was never decremented properly
   → FeedManager updates feedPosts with count: 1
   → BUT: CommentManager.commentCounts still has 0

7. User sees count: 0 in UI (from CommentManager)

8. User clicks comment icon
   → CommentView.onAppear
   → commentManager.fetchComments(postId)
   → Fetches 0 comments from Firebase
   → Updates commentCounts["post-123"] = 0
   → Callback: onCommentCountChanged?("post-123", 0)
   → FeedManager updates its post to count: 0

9. User closes comment sheet
   → PostView still shows count: 0 (now in sync)
```

**ACTUAL BUG**: The issue is that when the app is killed and reopened, Firebase might not have the updated count yet. OR there's a race condition where:
- CommentManager fetches comments → 0 comments
- Updates count → 0
- But FeedManager's disk cache has stale count → 1
- And Firebase hasn't updated the commentCount field yet

### Like Count Bug Flow

```
1. User likes post
   → LikeManager.toggleLike()
   → Optimistic: likedPosts.insert("hiroo-stamp123")
   → Optimistic: likeCounts["hiroo-stamp123"] = 1
   → Cache: saves likedPosts to UserDefaults ✅
   → Firebase: creates like doc + increments count

2. User kills app
   → likedPosts saved to UserDefaults ✅
   → likeCounts lost (no persistence) ❌

3. User reopens app
   → LikeManager.init()
   → Loads: likedPosts = ["hiroo-stamp123"] ✅
   → likeCounts = [:] (empty)

4. FeedManager loads disk cache
   → Post has likeCount: 0 (stale)
   → Sets feedPosts with stale counts

5. PostView renders
   → isLiked = likeManager.isLiked("hiroo-stamp123") = TRUE ✅
   → currentLikeCount = likeManager.getLikeCount("hiroo-stamp123") = 0 ❌
   → UI: ❤️ (filled) with "0" 

6. FeedContent.loadFeedIfNeeded() completes
   → Lines 568-571: likeManager.setLikeCounts(likeCounts)
   → Populates likeCounts["hiroo-stamp123"] = 1

7. Lines 573-577: likeManager.fetchLikeStatus(postIds, userId)
   → Verifies liked state from Firebase
   → Updates likedPosts (already correct)

8. UI updates
   → currentLikeCount = 1 ✅
   → UI: ❤️ (filled) with "1"
```

---

## Consistency Issues with Rest of Feed

### Good Patterns in Feed
1. **FeedManager disk cache**: Instagram-style instant perceived load
2. **LikeManager UserDefaults**: Persists user's liked state across sessions
3. **Optimistic updates**: Instant UI response with rollback on error
4. **Callback pattern**: CommentManager → FeedManager sync via `onCommentCountChanged`

### Inconsistent Patterns
1. **LikeManager**: Persists `likedPosts` but NOT `likeCounts`
2. **CommentManager**: NO persistence at all
3. **Count sync**: Comments use callback, likes use setLikeCounts
4. **Init timing**: LikeManager has init(), CommentManager doesn't

### What Should Be Consistent

**Manager Lifecycle**:
- All managers should have init() that loads cache
- All managers should have clearCache() (both have this ✅)
- All managers should persist their state to UserDefaults

**Count Management**:
- Either ALL counts come from feed data (current)
- OR ALL managers cache their own counts (better)

**State Sync**:
- Either use callbacks (like comments)
- OR use direct updates (like likes)
- Should be consistent

---

## Plan to Fix

### Fix 1: Add Comment Count Persistence

**What**: Make CommentManager cache comment counts like LikeManager caches liked posts

**Why**: Currently comment counts are lost on app restart, causing stale disk cache to override

**Where**: `Stampbook/Managers/CommentManager.swift`

**Changes**:
1. Add `init()` to load cached comment counts
2. Add `saveCachedCommentCounts()` to persist to UserDefaults
3. Call save after every count update
4. Update `clearCache()` to remove UserDefaults key

**Pros**:
- Fixes comment count showing 1 after deletion
- Consistent with LikeManager pattern
- Simple, minimal code change

**Cons**:
- Adds more UserDefaults storage
- Could get out of sync with Firebase if counts change elsewhere

### Fix 2: Add Like Count Persistence

**What**: Make LikeManager cache like counts, not just liked post IDs

**Why**: Currently like counts show 0 on cold start even though heart is filled

**Where**: `Stampbook/Managers/LikeManager.swift`

**Changes**:
1. Update `saveCachedLikes()` to also save `likeCounts` dictionary
2. Update `loadCachedLikes()` to also load `likeCounts` dictionary
3. Use separate UserDefaults keys: "likedPosts" and "likeCounts"

**Pros**:
- Fixes "❤️ 0" → "❤️ 1" flash on cold start
- More consistent with rest of system
- Better user experience (no flashing counts)

**Cons**:
- Counts could diverge from Firebase if someone else likes/unlikes
- More UserDefaults storage
- Cache invalidation becomes more complex

### Fix 3: Better Feed Cache Invalidation

**What**: When counts change via managers, also update disk cache immediately

**Why**: Currently disk cache can have stale counts that override manager state

**Where**: `Stampbook/Managers/FeedManager.swift`

**Changes**:
1. When `updatePostCommentCount()` is called, also save to disk
2. When like counts are updated (need new callback), also save to disk
3. Make disk cache save incremental, not just on full refresh

**Pros**:
- Disk cache stays fresh
- No stale count issues on restart
- Better Instagram-style experience

**Cons**:
- More disk writes (performance?)
- More complex cache management
- Need to handle partial updates

### Fix 4: Remove Disk Cache for Counts (Alternative Approach)

**What**: Store post metadata (user, stamp, date) in disk cache, but NOT counts

**Why**: Counts are volatile and should come from live sources (managers or Firebase)

**Where**: `Stampbook/Managers/FeedManager.swift`

**Changes**:
1. Remove `likeCount` and `commentCount` from FeedPost Codable
2. Always initialize counts to 0 in disk cache
3. Rely on managers to populate counts after feed loads

**Pros**:
- No stale count issues
- Simpler cache management
- Counts always come from authoritative sources

**Cons**:
- Breaks Instagram-style instant perceived load for counts
- Counts will always show 0 → actual count flash
- More complex FeedPost struct handling

---

## Recommendation: Which Fixes to Apply

### Priority 1: Fix 2 (Like Count Persistence) ⭐⭐⭐
**Do this**: This fixes the most visible bug (❤️ 0 flash) and is consistent with existing pattern

### Priority 2: Fix 1 (Comment Count Persistence) ⭐⭐
**Do this**: Fixes the comment count bug and makes managers consistent

### Priority 3: Fix 3 (Better Cache Invalidation) ⭐
**Consider**: Only if you still see stale data after Fix 1 & 2

### Don't Do: Fix 4 
**Skip**: Breaks Instagram-style perceived speed, makes UX worse

---

## Implementation Order

1. **Fix LikeManager first** (most visible bug)
   - Add like count caching
   - Test cold start → should not show ❤️ 0 flash

2. **Fix CommentManager second** (less frequent bug)
   - Add comment count caching  
   - Test cold start after delete → should show correct count

3. **Test together**
   - Like post → kill app → reopen → should show ❤️ 1 immediately
   - Comment → delete → kill app → reopen → should show 0 immediately

---

## Senior Developer Perspective

### What's Good About Current Code

1. **Optimistic updates**: Instant UI response, proper error rollback
2. **Instagram pattern**: Disk cache for perceived speed is excellent
3. **Separation of concerns**: Managers handle state, views handle display
4. **Callback pattern**: CommentManager → FeedManager sync is clean

### What Needs Improvement

1. **Inconsistent persistence**: LikeManager persists, CommentManager doesn't
2. **Partial persistence**: LikeManager persists IDs but not counts
3. **Cache coherence**: Three sources of truth (managers, feed cache, Firebase)
4. **No cache versioning**: What if FeedPost struct changes?

### What a Senior Dev Would Say

> "The Instagram-style disk cache is great for perceived performance, but you've created three sources of truth: LikeManager UserDefaults, CommentManager (nothing), and FeedManager disk cache. This is a classic distributed systems problem.
>
> The real issue is that counts can change from multiple sources (user action, other users, Firebase transactions), so you need a clear hierarchy:
> 1. Manager state (authoritative for current session)
> 2. UserDefaults (persisted across sessions)  
> 3. Disk cache (fast cold start, can be stale)
> 4. Firebase (source of truth, but slow)
>
> Right now your managers are missing level 2 (persistence), so disk cache (level 3) can override them. Fix: add persistence to both managers, and always prefer manager state over disk cache when both exist."

### Best Practice Recommendations

1. **Persist all manager state**: Both IDs and counts
2. **Invalidate disk cache**: When managers update, update disk cache too
3. **Add cache version**: So old disk caches don't break new app versions
4. **Add cache timestamp**: So you can reject very old disk caches (> 7 days)
5. **Unified caching pattern**: All managers should persist the same way

---

## Worth Doing Now? (MVP with 100 users / 1000 stamps)

### Yes, Do This Now ✅

**Reason**: These are core UX bugs that affect the primary feature (feed). Users will notice:
- Heart showing filled with 0 likes looks broken
- Comment counts being wrong after deletion is confusing
- These bugs happen EVERY time user restarts app

**Cost**: Low
- ~50 lines of code total
- No Firebase changes needed
- No API calls or storage changes
- Just UserDefaults additions

**Impact**: High
- Much better user experience
- More polished feel
- Builds user trust in the app

### Senior Dev Verdict

> "Fix it now. These are polish issues that make the app feel unfinished. At 100 users, you want every interaction to feel smooth. The good news is the fix is simple - just add persistence to your managers. Do it before you hit 1000 users, because then you'll be too busy with other features."

---

## Summary

### The Bugs
1. ❌ Comment count shows 1 after deletion on cold start
2. ❌ Like heart filled with 0, then flashes to 1 on cold start

### The Root Cause  
1. CommentManager has NO persistence → stale disk cache overrides
2. LikeManager persists liked IDs but NOT counts → filled heart but no count

### The Fix
1. Add comment count persistence to CommentManager
2. Add like count persistence to LikeManager
3. Both managers should save/load from UserDefaults

### The Result
✅ Smooth UX with no flashing counts
✅ Consistent behavior across app restarts
✅ Better Instagram-style perceived performance

