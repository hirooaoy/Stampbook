# 🚨 CRITICAL BUG: Like Count -1 Analysis - EXECUTIVE SUMMARY

**Date:** November 6, 2025  
**Reporter:** hiroo  
**Status:** ROOT CAUSE IDENTIFIED - READY TO FIX

---

## 🔍 THE PROBLEM

Your "your-first-stamp" post shows **-1 likes** in the feed.

---

## 📊 FIREBASE INVESTIGATION - WHAT I FOUND

### Your Account Status:
- **Total Stamps:** 11
- **Problem Stamp:** `your-first-stamp` has `likeCount: -1` ❌
- **Other Issue:** 7 older stamps have `likeCount: undefined` ⚠️
- **Actual Likes in Database:** Only 1 like exists (on a different stamp)

So "your-first-stamp" **should be 0, not -1**.

---

## 🐛 ROOT CAUSE - THE BUG

### **Bug #1: Missing Field Initialization** ⭐ CRITICAL

When you collect a stamp, this code runs:

```swift:183:191:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Services/FirebaseService.swift
func saveCollectedStamp(_ stamp: CollectedStamp, for userId: String) async throws {
    let docRef = db
        .collection("users")
        .document(userId)
        .collection("collected_stamps")
        .document(stamp.stampId)
    
    try docRef.setData(from: stamp, merge: true)
}
```

**The Problem:**
- `CollectedStamp` model defaults `likeCount` and `commentCount` to `0` when decoded
- BUT when **creating a new stamp**, if these fields aren't explicitly set, Firebase may store them as `undefined`
- This happens because of the `merge: true` parameter - it doesn't initialize missing fields

---

### **Bug #2: Unsafe Decrement Operation** ⭐ CRITICAL

When you unlike a post, this code runs:

```swift:1150:1156:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Services/FirebaseService.swift
if likeDoc.exists {
    // Unlike: delete the like document and decrement count
    transaction.deleteDocument(likeRef)
    transaction.updateData([
        "likeCount": FieldValue.increment(Int64(-1))
    ], forDocument: postRef)
    return false
```

**The Problem:**
- `FieldValue.increment(-1)` on an **undefined** field = **-1**
- Should be: `undefined - 1 = 0` (or skip decrement)
- Actually becomes: `undefined - 1 = -1` ❌

---

### **Bug #3: Frontend Has Protection But Gets Overridden**

```swift:40:40:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Managers/LikeManager.swift
likeCounts[postId, default: 0] = max(0, likeCounts[postId, default: 0] - 1)
```

**This DOES protect local state!** ✅

**But:**
1. Local state says: `max(0, 0 - 1) = 0` ✅
2. Firebase gets: `FieldValue.increment(-1)` on `undefined` = `-1` ❌
3. Next feed refresh loads Firebase data: `-1` ❌
4. Local protection is overridden by stale Firebase data

---

## 🎯 HOW IT HAPPENED - THE TIMELINE

Based on Firebase data and code analysis:

1. **Nov 5, 2025 5:54pm** - You collected "your-first-stamp"
   - Document created WITHOUT `likeCount` field (undefined)
   
2. **Shortly After** - You (or someone) tapped the heart
   - Like added successfully
   - `likeCount` field still undefined
   
3. **Then** - You tapped heart again (unlike)
   - Unlike ran: `FieldValue.increment(-1)`
   - `undefined - 1 = -1` ❌
   
4. **Result** - Firebase now stores `likeCount: -1`
   - Feed shows "-1 likes"
   - No way to recover without manual fix

---

## ⚠️ OTHER SYSTEMS AFFECTED

### ✅ **Comments - SAME BUG**
- Same pattern in `toggleComment()`
- If you comment then uncomment on a post with undefined `commentCount`, it will become `-1`

### ✅ **Follows - SAFE!** ✅

Good news! The follow system is **safe** from this bug:

```swift:180:182:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Managers/FollowManager.swift
currentCounts.following = max(0, currentCounts.following - 1)
followCounts[currentUserId] = currentCounts
```

**Why it's safe:**
1. Follow counts are fetched on-demand from subcollections (not stored)
2. Local decrements use `max(0, ...)` protection
3. No blind `FieldValue.increment()` operations
4. Refreshes from Firebase after every operation

**Architecture Difference:**
- **Likes/Comments:** Denormalized counts stored in document + use `FieldValue.increment()`
- **Follows:** Count subcollections on-demand + local state management

---

## 💡 THE PATTERN - What Makes This Bug Possible

```
Optimistic UI
  +
Firebase FieldValue.increment()
  +
Undefined Fields
  =
NEGATIVE COUNTS ❌
```

---

## 🛠️ THE FIX - Three-Part Solution

### Part 1: Initialize Fields on Collection ⭐ MUST FIX

```swift
// In UserStampCollection.swift - collectStamp()
let newCollection = CollectedStamp(
    stampId: stampId,
    userId: userId,
    collectedDate: Date(),
    userNotes: "",
    userImageNames: [],
    userImagePaths: [],
    likeCount: 0,      // ✅ ADD THIS
    commentCount: 0,   // ✅ ADD THIS
    userRank: userRank
)
```

---

### Part 2: Safe Decrement in Firebase ⭐ MUST FIX

```swift
// In FirebaseService.swift - toggleLike()
// BEFORE:
transaction.updateData([
    "likeCount": FieldValue.increment(Int64(-1))
], forDocument: postRef)

// AFTER:
let currentDoc = try transaction.getDocument(postRef)
let currentCount = currentDoc.data()?["likeCount"] as? Int ?? 0
let newCount = max(0, currentCount - 1)
transaction.updateData(["likeCount": newCount], forDocument: postRef)
```

Same fix needed for `toggleComment()`.

---

### Part 3: Data Migration ⭐ MUST FIX

```javascript
// Run script to fix existing data:
// 1. Set all undefined likeCount/commentCount to 0
// 2. Fix "your-first-stamp" from -1 to 0
// 3. Verify all counts >= 0
```

---

## 📋 MY RECOMMENDATIONS

### Immediate Actions (Do Now):

1. **Run Migration Script** - Fix existing data
2. **Fix collectStamp()** - Initialize likeCount/commentCount to 0
3. **Fix toggleLike()** - Safe decrement logic
4. **Fix toggleComment()** - Safe decrement logic

### Optional (Nice to Have):

5. **Add Frontend Validation** - Never display negative counts
6. **Add Firestore Rules** - Prevent storing negative counts
7. **Add Tests** - Offline + rapid tap scenarios

---

## 🎓 LESSONS LEARNED

### Why This Happened:
1. ❌ Social features added to existing stamps (undefined fields)
2. ❌ Blind `FieldValue.increment()` on undefined fields
3. ❌ No validation on stored counts
4. ✅ Frontend protection exists but can't prevent Firebase corruption

### Architecture Insight:
**Follow system is safer because it:**
- Counts on-demand (no stored counts to corrupt)
- Refreshes from source of truth after operations
- No blind increment/decrement operations

**Like/Comment system is vulnerable because it:**
- Stores denormalized counts (performance optimization)
- Uses blind `FieldValue.increment()` (race condition optimization)
- Assumes fields always exist (migration gap)

---

## 🚀 READY TO FIX?

I've identified the exact issues and can fix them systematically. The fixes are straightforward and low-risk.

**Your call - how should we proceed?**

A) Fix everything now (migration + backend + frontend)
B) Just migration first (clean up data, then fix code later)
C) Review the specific fixes together before implementing

**Also:**
- Should I check ProfileManager for similar issues?
- Want to add Firestore validation rules while we're at it?

Let me know and I'll implement the fixes! 🛠️

