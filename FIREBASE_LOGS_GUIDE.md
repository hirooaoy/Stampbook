# Firebase Console - How to Check Logs & Usage

## 🔍 Check Which Functions Are Firing Most

### Step 1: Go to Firebase Console
1. Open https://console.firebase.google.com
2. Select your Stampbook project
3. Click **Functions** in left sidebar

### Step 2: View Function Logs
1. You'll see a list of your deployed functions:
   - `validateContent`
   - `checkUsernameAvailability`
   - `moderateComment`
   - `moderateProfileOnWrite`
   - `createFollowNotification` ⚠️
   - `createLikeNotification` ⚠️
   - `createCommentNotification` ⚠️
   - `updateFollowCounts` ⚠️
   - `cleanupOldNotifications`

2. **Click on any function name** to see:
   - Invocation count (24h, 7d, 30d)
   - Execution time
   - Memory usage
   - Success/failure rate

### Step 3: View Detailed Logs
1. Click **"Logs"** tab at the top
2. Filter by:
   - **Severity:** All levels (shows info, warning, error)
   - **Time range:** Last 7 days
   - **Function:** Select specific function or "All functions"

3. Look for these patterns:
   ```
   📬 Creating follow notification: [userId] followed [userId]
   ✅ Follow notification created successfully
   📊 Follow: [userId] → [userId] (delta: +1)
   ✅ Updated counts successfully
   ```

### Step 4: Identify Top Culprits
Look for:
- **High frequency functions** (> 50 invocations in a day with only 2 users = suspicious)
- **Error patterns** (failed functions that retry = multiplied costs)
- **Long execution times** (> 10 seconds = timeout risk)

---

## 📊 Check Firestore Read/Write Usage

### Step 1: Open Firestore Console
1. Firebase Console → **Firestore Database** in left sidebar
2. Click **"Usage"** tab at the top

### Step 2: Analyze Usage Graphs
You'll see 4 graphs:

#### 1. **Document Reads**
- **What it shows:** Total reads over time
- **What to look for:**
  - Sudden spikes (your 151% increase)
  - Patterns (spikes during testing sessions?)
  - Steady baseline vs. activity spikes

#### 2. **Document Writes**
- **What it shows:** Total writes over time
- **What to look for:**
  - Should be much lower than reads (reads = 10x writes is normal)
  - Spike in writes = lots of social activity (likes, follows, comments)

#### 3. **Document Deletes**
- Usually near zero for your app

#### 4. **Storage**
- Total data stored in Firestore
- Should be minimal for MVP (< 1 GB)

### Step 3: Check Specific Collections
1. Click **"Data"** tab
2. Navigate to collections:
   - `notifications` ← Check size (should be < 1000 docs)
   - `likes` ← Growing with each like
   - `comments` ← Growing with each comment
   - `users/{userId}/collectedStamps` ← Main data
   - `users/{userId}/following` ← Follow relationships

3. **Red flags:**
   - Notifications collection > 1000 docs (cleanup function not running?)
   - Orphaned documents (deleted users but data remains)
   - Duplicate documents (retry failures)

---

## 🔎 Check Collection Group Queries (Expensive!)

### Step 1: Enable Firestore Monitoring
1. Firebase Console → **Firestore Database**
2. Click **"Indexes"** tab
3. Look for composite indexes on:
   - `collectionGroup: collectedStamps` with `userId`, `collectedDate`

### Step 2: Monitor Query Performance
Unfortunately, Firebase doesn't show per-query costs in real-time, but you can:

1. **Look at logs** for slow queries:
   - Functions logs show timing: `⏱️ Query completed in 2.543s`
   - Slow queries (> 3s) = too many reads

2. **Check if indexes are used:**
   - Missing index error in logs = query runs but is VERY expensive
   - Firebase will show a link to create the index automatically

---

## 📈 Set Up Budget Alerts (Recommended!)

### Step 1: Enable Cloud Billing Alerts
1. Go to **Google Cloud Console** (not Firebase Console):
   https://console.cloud.google.com
2. Select your project (Stampbook)
3. Click **Billing** in left menu
4. Click **Budgets & alerts**

### Step 2: Create Budget Alert
1. Click **"Create Budget"**
2. Configure:
   - **Name:** Stampbook MVP Budget
   - **Amount:** $10/month (adjust as needed)
   - **Alert thresholds:** 50%, 90%, 100%
   - **Email:** Your email address

3. You'll get alerts like:
   ```
   ⚠️ Your budget "Stampbook MVP Budget" has exceeded 50% 
   Current spend: $5.23 / $10.00
   ```

### Step 3: Monitor Costs Daily
1. Firebase Console → **Usage and billing** (left sidebar)
2. Click **"Details & settings"**
3. Check daily costs:
   - Firestore reads/writes
   - Cloud Functions invocations
   - Cloud Storage bandwidth

---

## 🚨 Emergency: High Usage Detected

If you see unexpected costs:

### Immediate Actions:
1. **Pause Functions (Temporary):**
   ```bash
   cd /Users/haoyama/Desktop/Developer/Stampbook
   firebase functions:delete createFollowNotification
   firebase functions:delete createLikeNotification
   # etc. (can redeploy later)
   ```

2. **Disable Firestore Writes (Emergency Only):**
   - Firebase Console → Firestore Database → Rules
   - Add temporary deny rule:
     ```
     match /{document=**} {
       allow read;
       allow write: if false; // Temporarily disable all writes
     }
     ```

3. **Check for Infinite Loops:**
   - Function logs showing same function called repeatedly?
   - Check if your functions trigger themselves (e.g., write triggers another write)

---

## 📝 Recommended Weekly Check (5 minutes)

1. ✅ Check total reads/writes (should be < 10K/day for MVP)
2. ✅ Check function invocations (should be < 1000/day for 2 users)
3. ✅ Review function logs for errors
4. ✅ Check notifications collection size (< 500 docs)
5. ✅ Verify cleanup function ran (check logs every midnight)

---

## 🔗 Quick Links

- **Firebase Console:** https://console.firebase.google.com
- **Cloud Console (Billing):** https://console.cloud.google.com
- **Firestore Pricing:** https://firebase.google.com/pricing#firestore-pricing
- **Functions Pricing:** https://firebase.google.com/pricing#functions-pricing

---

## 🎯 What Your Current Metrics Mean

**301 function invocations (7 days):**
- Average: ~43 invocations/day
- Expected for 2 test users: ~10/day (normal usage)
- **Diagnosis:** Testing with frequent follows, likes, comments = 4x normal activity
- **Action:** Expected during development, should drop at launch with real users

**6.8K reads (current):**
- If "current" = today: ~6,800 reads
- Expected: ~2,000 reads/day for 2 users
- **Diagnosis:** 3x normal = excessive feed refreshes
- **Action:** Implement Quick Wins in FIREBASE_COST_ANALYSIS.md

**753 writes (current):**
- Normal for social activity
- Each social action = 2-4 writes
- **Diagnosis:** Healthy ratio (writes << reads)
- **Action:** No immediate concern

