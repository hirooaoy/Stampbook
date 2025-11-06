# Critical Bug Analysis: Like Count -1 Issue

**Date:** November 6, 2025  
**Status:** 🚨 CRITICAL BUG IDENTIFIED

---

## 🔍 ISSUE DISCOVERED

Your "your-first-stamp" post shows **-1 likes** in the feed.

---

## 📊 FIREBASE DATA ANALYSIS

### What I Found:

1. **Your "your-first-stamp" has:**
   - `likeCount: -1` ❌ (stored in Firestore)
   - `commentCount: 0` ✅
   - Collected: Nov 5, 2025

2. **Actual likes in database:**
   - Total likes documents: **1 like**
   - This like is on "powell-hyde-cable-car" (not your-first-stamp)
   - So "your-first-stamp" should have 0 likes, not -1

3. **7 older stamps have undefined counts:**
   - These were collected before social features were added (Oct 22-28)
   - Missing `likeCount` field entirely

---

## 🚨 ROOT CAUSES IDENTIFIED

### **Primary Issue: Missing Field Initialization**

When you collected "your-first-stamp", the code likely:

```swift
// FirebaseService.swift - saveCollectedStamp()
// Creates new stamp document but DOESN'T initialize likeCount/commentCount
```

**What happened:**
1. Nov 5: You collect "your-first-stamp"
2. Firestore document created **WITHOUT** `likeCount: 0` field
3. You (or someone) tried to like it
4. Unlike happened (maybe accidentally tapped twice?)
5. Firebase runs: `FieldValue.increment(-1)`
6. **-1 + undefined = -1** (not 0 - 1 = -1)

---

## 🔧 TECHNICAL DEEP DIVE

### Where the Bugs Are:

#### 1. **FirebaseService.swift - `saveCollectedStamp()`**

```swift
// Currently: When saving a new collected stamp
func saveCollectedStamp(...) {
    // ❌ MISSING: Does NOT initialize likeCount and commentCount
    // Should be:
    // "likeCount": 0,
    // "commentCount": 0
}
```

**Impact:** All new stamps start with `undefined` counts, making them vulnerable to negative values.

---

#### 2. **FirebaseService.swift - `toggleLike()`**

```swift
func toggleLike(...) {
    transaction.updateData([
        "likeCount": FieldValue.increment(Int64(-1))  // ❌ DANGER!
    ], forDocument: postRef)
}
```

**The Problem:**
- If `likeCount` field doesn't exist: `undefined - 1 = -1`
- Should check if field exists first, or use safer atomic operations

---

#### 3. **Frontend - Missing Safety Guards**

Looking at `LikeManager.swift` lines 40, 75, 94:

```swift
likeCounts[postId, default: 0] = max(0, likeCounts[postId, default: 0] - 1)
```

**This protects the LOCAL state** but:
- Firebase still gets the decrement
- If Firebase has `undefined`, it becomes `-1`
- Next feed refresh brings `-1` back from Firebase
- Local `max(0, ...)` protection is overridden by feed data

---

## 📱 DOES THIS AFFECT OTHER PARTS?

### ✅ **Comment System - SAME VULNERABILITY**

```swift
// CommentManager and toggleComment have the same pattern
// If commentCount is undefined, decrementing will cause -1
```

**Evidence:** In your data, some stamps show:
- `commentCount: undefined`

This means **the same bug can happen with comments**.

---

### ✅ **Follow System - CHECK NEEDED**

Need to verify if follow counts have same issue:
- `followerCount`
- `followingCount`

**Action:** Check `FollowManager.swift` for similar patterns.

---

### ✅ **Profile Stats - CHECK NEEDED**

Need to verify:
- `totalStamps` (probably safe - you have 11)
- Any other counters

---

## 🎯 CRITICAL SCENARIOS

### Scenario 1: Race Condition (MOST LIKELY)
1. User collects stamp (no likeCount initialized)
2. User rapidly taps heart: like → unlike
3. Unlike happens before like completes
4. Decrement hits undefined field → `-1`

### Scenario 2: Old Stamp Migration
1. Stamp collected before social features (Oct 22-28)
2. likeCount never added to document
3. Someone tries to like/unlike
4. Decrement on undefined → `-1`

### Scenario 3: Failed Like Sync
1. Offline collection
2. Like attempted while likeCount not synced
3. Local state says "0", Firebase has "undefined"
4. Unlike decrements undefined → `-1`

---

## 🔍 RELATED ISSUES IN CODE

### Issue 1: Optimistic Updates Don't Account for Undefined

```swift:166:182:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Managers/LikeManager.swift
func updateLikeCount(postId: String, count: Int) {
    // Only skip update if there's an active pending operation
    if pendingLikes.contains(postId) || pendingUnlikes.contains(postId) {
        return
    }
    
    // ❌ This check assumes Firebase returns valid count
    // But Firebase might return undefined (treated as 0 in Swift)
    if likedPosts.contains(postId) && count == 0 {
        likeCounts[postId] = max(1, likeCounts[postId] ?? 1)
        return
    }
    
    likeCounts[postId] = count
}
```

**Problem:** When Firebase returns a document without `likeCount`, Swift decodes it as `0`, not `undefined`.

---

### Issue 2: Feed Loading Doesn't Validate Counts

```swift:514:515:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Managers/FeedManager.swift
likeCount: collectedStamp.likeCount,
commentCount: collectedStamp.commentCount
```

**Problem:** Directly passes whatever Firebase has, including negative or undefined values.

---

### Issue 3: CollectedStamp Model Has Backward Compatibility but No Validation

```swift:48:50:/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Models/UserStampCollection.swift
likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
```

**Good:** Defaults to 0 if missing.  
**Problem:** Doesn't prevent negative values from being stored.

---

## 🛠️ PROPOSED FIXES (High Level - Don't Implement Yet)

### Fix 1: Initialize Fields on Stamp Collection ⭐ CRITICAL

```swift
// FirebaseService.swift - saveCollectedStamp()
// Add these fields when creating new collected stamp:
"likeCount": 0,
"commentCount": 0
```

---

### Fix 2: Safe Decrement in toggleLike/toggleComment ⭐ CRITICAL

```swift
// Instead of:
transaction.updateData(["likeCount": FieldValue.increment(-1)], forDocument: postRef)

// Do:
let currentData = try transaction.getDocument(postRef).data()
let currentCount = currentData?["likeCount"] as? Int ?? 0
let newCount = max(0, currentCount - 1)
transaction.updateData(["likeCount": newCount], forDocument: postRef)
```

---

### Fix 3: Data Migration Script ⭐ HIGH PRIORITY

Run a script to fix existing stamps:
- Set all `undefined` likeCount/commentCount to `0`
- Fix the -1 on "your-first-stamp" to `0`

---

### Fix 4: Frontend Validation ⭐ MEDIUM PRIORITY

```swift
// FeedManager.swift
likeCount: max(0, collectedStamp.likeCount),  // Never allow negative
commentCount: max(0, collectedStamp.commentCount)
```

---

### Fix 5: Add Firestore Rule Validation ⭐ NICE TO HAVE

```javascript
// firestore.rules
match /users/{userId}/collected_stamps/{stampId} {
  allow write: if request.resource.data.likeCount >= 0 
            && request.resource.data.commentCount >= 0;
}
```

---

## ⚠️ OTHER SYSTEMS TO CHECK

Based on this pattern, audit ALL increment/decrement operations:

1. **FollowManager** - followerCount, followingCount
2. **ProfileManager** - totalStamps, totalCountries (probably safe)
3. **StampsManager** - stamp statistics (probably safe, read-only)
4. **Any future counting features**

---

## 🎓 LESSONS LEARNED

### Anti-Pattern Identified:
**"Optimistic UI + Firebase Increment + Undefined Fields = Negative Counts"**

### Best Practices Going Forward:
1. ✅ Always initialize counter fields (never leave undefined)
2. ✅ Use read-then-write for decrements (not blind increments)
3. ✅ Validate counts >= 0 on both client and server
4. ✅ Add migration scripts when adding new fields to existing documents
5. ✅ Test offline scenarios with rapid tap interactions

---

## 📋 RECOMMENDED ACTION PLAN

### Phase 1: Stop the Bleeding (Do First)
1. Run migration script to fix all counts
2. Fix saveCollectedStamp() to initialize fields

### Phase 2: Prevent Recurrence (Do Next)
3. Fix toggleLike() and toggleComment() decrement logic
4. Add frontend validation in FeedManager

### Phase 3: Harden System (Do Later)
5. Add Firestore rules
6. Audit other increment/decrement operations
7. Add tests for offline + rapid tap scenarios

---

## 🎯 PRIORITY ASSESSMENT

**Severity:** 🚨 **CRITICAL**
- User-facing bug (shows negative numbers)
- Data corruption in Firestore
- Affects all users potentially

**Scope:** 🌐 **SYSTEM-WIDE**
- Affects: Likes, Comments
- Potentially: Follows, other counters

**Urgency:** ⏰ **HIGH**
- Already affecting production
- Will worsen as more users interact

---

## Questions for You:

1. **Do you remember tapping the heart on "your-first-stamp"?** This would confirm the race condition theory.

2. **Do you want me to:**
   - A) Fix everything in one go?
   - B) Fix in phases (migration → backend → frontend)?
   - C) Start with just the migration to fix current data?

3. **Should I check FollowManager for the same issue?**

4. **Do you want to add Firestore security rules to prevent negative values?**

