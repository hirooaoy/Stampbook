# Like Count Synchronization Fix

## Problem

When rapidly liking/unliking posts, the `likeCount` field on posts could become out of sync with the actual number of like documents in the `/likes` collection.

### What Happened

User scenario: Like → Unlike → Like → Unlike (rapidly)

The original implementation had **two separate operations**:
```swift
// Operation 1: Delete/create like document
try await likeRef.delete()

// Operation 2: Update counter (separate call)
try await postRef.updateData([
    "likeCount": FieldValue.increment(Int64(-1))
])
```

**This caused issues:**
1. **Partial failures**: If operation 1 succeeded but operation 2 failed → like deleted but count not decremented
2. **Race conditions**: Rapid tapping could cause multiple increments before deletes completed
3. **Result**: Count = 4, but actual likes = 0

## Solution

### ✅ Use Firestore Transactions

Wrapped both operations in a **transaction** to make them **atomic** (all-or-nothing):

```swift
let isLiked = try await db.runTransaction({ (transaction, errorPointer) -> Bool in
    let likeDoc = try transaction.getDocument(likeRef)
    
    if likeDoc.exists {
        // Both operations happen atomically
        transaction.deleteDocument(likeRef)
        transaction.updateData(["likeCount": FieldValue.increment(Int64(-1))], forDocument: postRef)
        return false
    } else {
        transaction.setData(from: like, forDocument: likeRef)
        transaction.updateData(["likeCount": FieldValue.increment(Int64(1))], forDocument: postRef)
        return true
    }
})
```

**Benefits:**
- ✅ Either BOTH operations succeed or BOTH fail (no partial updates)
- ✅ Prevents race conditions from rapid tapping
- ✅ Ensures `likeCount` always matches actual like documents
- ✅ Automatic retry on conflicts

## Reconciliation Script

Created `fix_like_counts.js` to repair existing inconsistencies:

**What it does:**
1. Scans all posts in the database
2. Counts actual likes in `/likes` collection (source of truth)
3. Compares with stored `likeCount` field
4. Updates any mismatches

**Usage:**
```bash
node fix_like_counts.js
```

**Example output:**
```
👤 Checking posts for Hiroo...
   📍 us-ca-sf-powell-hyde-cable-car
      Stored count: 4
      Actual count: 0
      ✅ Fixed!
```

## Best Practices

### 1. Source of Truth
- **`/likes` collection** = source of truth (actual likes)
- **`likeCount` field** = denormalized cache for performance

### 2. When to Recount
Run the reconciliation script:
- After any database migration
- If users report incorrect counts
- Periodically as a maintenance task (optional)

### 3. Transaction Rules
- Use transactions when updating multiple related documents
- Keep transactions short (Firestore has time limits)
- Don't put network calls inside transactions

### 4. Error Handling
- Transactions automatically retry on conflicts
- If transaction fails, entire operation fails (safe)
- Client-side optimistic updates should revert on error

## Alternative Approaches Considered

### ❌ Cloud Functions Triggers
```javascript
// Automatically update count when like is added/deleted
exports.updateLikeCount = functions.firestore
    .document('likes/{likeId}')
    .onWrite(async (change, context) => {
        // Update count...
    });
```

**Why not used:**
- Additional complexity
- Additional cost (function invocations)
- Slight delay (eventually consistent)
- Transactions are simpler and more immediate

### ❌ Remove Denormalized Count
Store only in `/likes` collection, count on-demand.

**Why not used:**
- Would require counting on every feed load (expensive)
- Poor performance for feeds with many posts
- High Firestore read costs

### ✅ Chosen: Transactions + Reconciliation
- Best balance of performance and consistency
- Immediate consistency (not eventual)
- Low cost (no extra functions)
- Simple to understand and maintain

## Testing

### Manual Tests
1. ✅ Like a post → count increments to 1, document created
2. ✅ Unlike a post → count decrements to 0, document deleted
3. ✅ Rapidly toggle 10 times → count stays correct
4. ✅ Like while offline → syncs correctly when online
5. ✅ Multiple users like same post → count accurate

### Edge Cases
- [x] Network interruption during like → transaction fails safely
- [x] Rapid tapping (tap 5 times in 1 second) → count stays accurate
- [x] Simultaneous likes from different users → no race conditions

## Summary

**Fixed:** Like count synchronization issue by using Firestore transactions
**Impact:** Ensures `likeCount` always matches actual likes, prevents data inconsistency
**Files Changed:**
- `Stampbook/Services/FirebaseService.swift` - Added transaction logic
**Files Added:**
- `fix_like_counts.js` - Reconciliation script for existing data

**Before:** 2 separate operations (could fail independently)  
**After:** 1 atomic transaction (all-or-nothing)

The like system is now **robust and consistent**! 🎉

