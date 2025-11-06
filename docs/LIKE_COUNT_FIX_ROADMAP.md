# Like/Comment Count System - Roadmap

**Status:** Phase 1 Complete ✅  
**Last Updated:** November 6, 2025

---

## ✅ Phase 1: COMPLETED (Nov 6, 2025)

### What We Fixed:
1. ✅ **Data Migration** - Fixed -1 and undefined counts
   - Script: `fix_like_comment_counts.js`
   - Fixed 8 stamps (1 negative, 11 undefined fields)
   
2. ✅ **Code Fix** - Initialize fields on collection
   - File: `Stampbook/Models/UserStampCollection.swift`
   - Line 197-198: Added `likeCount: 0, commentCount: 0`

### Result:
- No more -1 counts ✅
- All future stamps initialize with 0 ✅
- FieldValue.increment() works correctly ✅

---

## 📋 Phase 2: TODO (Do Next Week)

### When to Do This:
- **Trigger:** After first week of testing
- **Or:** If you notice count inconsistencies

### 3. Add Reconciliation Script

**What:** Periodically verify counts match reality

**File:** Create `reconcile_like_comment_counts.js`

**Logic:**
```javascript
// For each stamp:
1. Count actual likes in subcollection
2. Compare to stored likeCount
3. If different, fix it and log
4. Same for comments
```

**Why:**
- Distributed systems can drift (network failures, race conditions)
- Self-healing mechanism
- Catches bugs early

**Frequency:** Run weekly or on-demand

---

### 4. Add Monitoring/Alerting

**What:** Detect anomalies automatically

**Options:**

#### Option A: Script-Based (Simple)
```javascript
// Add to reconciliation script:
if (negativeCountFound) {
  console.error("🚨 ALERT: Negative count detected!");
  // Send email or Slack notification
}
```

#### Option B: Firebase Functions (Better)
```javascript
// Trigger on write
exports.validateCounts = functions.firestore
  .document('users/{userId}/collected_stamps/{stampId}')
  .onWrite((change, context) => {
    const data = change.after.data();
    if (data.likeCount < 0 || data.commentCount < 0) {
      console.error("🚨 Negative count detected!", context.params);
    }
  });
```

**Why:**
- Catch bugs immediately
- Don't wait for user reports
- Professional ops practice

---

## 🚀 Phase 3: TODO (Do at 1000+ Users)

### When to Do This:
- **Trigger:** 1000+ users OR consistent performance issues
- **Or:** Manual reconciliation becomes annoying

---

### 5. Move to Cloud Functions

**What:** Handle like/comment operations server-side

**Current (Client-side):**
```swift
// Swift code makes direct Firestore calls
FieldValue.increment(+1)
```

**Future (Server-side):**
```javascript
// Cloud Function
exports.toggleLike = functions.https.onCall((data, context) => {
  // Validate user auth
  // Update counts transactionally
  // Return result
});
```

**Benefits:**
- ✅ Security (users can't fake likes)
- ✅ Validation (server enforces rules)
- ✅ Consistency (single source of logic)

**Costs:**
- ⚠️ More complex deployment
- ⚠️ Slightly higher latency
- ⚠️ More expensive (Cloud Functions cost)

**Files to Change:**
- Create: `functions/index.js` (Cloud Functions)
- Update: `FirebaseService.swift` (call Cloud Functions)
- Update: `LikeManager.swift` (remove increment logic)

---

### 6. Automated Reconciliation

**What:** Cloud Function runs daily to fix drift

```javascript
// Scheduled function (runs daily at 3am)
exports.dailyReconciliation = functions.pubsub
  .schedule('0 3 * * *')
  .timeZone('America/Los_Angeles')
  .onRun(async (context) => {
    // Run reconciliation script
    // Fix any drifts
    // Log results
  });
```

**Why:**
- Zero manual intervention
- Catches and fixes issues automatically
- Professional production system

**Costs:**
- Requires Cloud Functions setup
- Needs monitoring/logging infrastructure

---

## 🎯 Decision Points

### Stay in Phase 1 if:
- ✅ Less than 1000 users
- ✅ No count issues appearing
- ✅ Manual fixes acceptable

### Move to Phase 2 if:
- ⚠️ Seeing occasional count inconsistencies
- ⚠️ Want peace of mind
- ⚠️ 5 minutes/week to run reconciliation

### Move to Phase 3 if:
- ❌ 1000+ users
- ❌ Frequent count issues
- ❌ Need automated reliability
- ❌ Want production-grade system

---

## 📊 Current Architecture

### What We Have Now:
```
Client (Swift)
  → Direct Firestore writes
  → FieldValue.increment()
  → Optimistic UI updates

Good for: MVP, <1000 users
Issues: Potential drift, no validation
```

### Phase 3 Architecture:
```
Client (Swift)
  → Cloud Function (validation)
  → Firestore writes
  → Scheduled reconciliation

Good for: Scale, production
Issues: More complex, higher cost
```

---

## 🔗 Related Files

### Current Implementation:
- `Stampbook/Managers/LikeManager.swift` - Client-side like logic
- `Stampbook/Managers/CommentManager.swift` - Client-side comment logic
- `Stampbook/Services/FirebaseService.swift` - Firebase operations
- `Stampbook/Models/UserStampCollection.swift` - Data model

### Scripts:
- `fix_like_comment_counts.js` - One-time migration (Phase 1) ✅
- `reconcile_like_comment_counts.js` - TODO (Phase 2)
- `functions/index.js` - TODO (Phase 3)

### Documentation:
- `docs/LIKE_COUNT_BUG_ANALYSIS.md` - Technical deep dive
- `docs/LIKE_COUNT_BUG_SUMMARY.md` - Executive summary
- This file - Roadmap

---

## 💡 Key Learnings

1. **Denormalized counts trade consistency for performance**
   - Fast reads (cached counts)
   - Risk of drift
   - Need reconciliation

2. **FieldValue.increment() is good for race conditions**
   - Atomic operations
   - Order doesn't matter
   - But requires initialized fields

3. **Always initialize counters to 0**
   - Never leave undefined
   - Prevents negative values
   - Makes increment work correctly

4. **Eventual consistency is OK for social features**
   - Likes don't need to be perfect immediately
   - Self-healing within hours/days is fine
   - Better than slow reads

---

## 🎓 Industry Comparison

### How Others Do It:

**Instagram/Twitter:**
- Phase 3 architecture (Cloud Functions)
- Automated reconciliation
- Accepts eventual consistency

**Reddit:**
- Fuzzes counts intentionally
- "6.2k upvotes" not exact
- Reconciles periodically

**YouTube:**
- Server-side everything
- Public API (no direct DB access)
- Very accurate but higher latency

**Our Approach (MVP):**
- Phase 1 for now
- Evolve as needed
- Right tradeoff for scale

---

## ✅ Success Criteria

### Phase 1 Success:
- ✅ No negative counts
- ✅ All new stamps initialize correctly
- ✅ Feed shows accurate numbers

### Phase 2 Success:
- ✅ Weekly reconciliation runs smoothly
- ✅ Drift detected and fixed automatically
- ✅ Zero negative counts for 1 month

### Phase 3 Success:
- ✅ 100% server-side validation
- ✅ Daily automated reconciliation
- ✅ Production monitoring/alerting
- ✅ <1% drift rate

---

**Next Action:** Monitor for 1 week, then decide if Phase 2 needed

