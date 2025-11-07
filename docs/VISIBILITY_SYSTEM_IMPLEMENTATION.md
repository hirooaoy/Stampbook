# 🎯 Stamp Visibility System - Complete Implementation Plan

**Created:** November 7, 2025  
**Purpose:** Enable stamp removal (moderation) and temporary stamps (events)  
**Estimated Time:** 2-3 hours  
**Risk Level:** LOW (fully backward compatible)

---

## 📚 Table of Contents
1. [Overview](#overview)
2. [Phase 1: Update Stamp Model](#phase-1-update-stamp-model)
3. [Phase 2: Add Filtering Logic](#phase-2-add-filtering-logic)
4. [Phase 3: Update Upload Script](#phase-3-update-upload-script)
5. [Phase 4: Create Admin Tools](#phase-4-create-admin-tools)
6. [Phase 5: Testing](#phase-5-testing)
7. [Use Cases](#use-cases)
8. [Rollback Plan](#rollback-plan)

---

## Overview

### What We're Building
A visibility system that allows:
- ✅ **Moderation:** Remove reported stamps immediately for all users
- ✅ **Temporary Stamps:** Event-based stamps that appear/disappear on schedule
- ✅ **Keep Collected:** Users keep stamps they collected even after removal
- ✅ **Cache Compatible:** Works with Firebase's persistent offline cache

### Key Concept: Soft Delete
Instead of deleting stamps, we mark them as `removed` or add date ranges. Firebase cache updates with the new status, and the app filters them out.

### New Fields
```swift
status: String?          // "active", "hidden", "removed" (default: "active")
availableFrom: Date?     // When stamp becomes visible (default: nil = always)
availableUntil: Date?    // When stamp expires (default: nil = forever)
removalReason: String?   // Why it was removed (for audit trail)
```

---

## Phase 1: Update Stamp Model
**File:** `Stampbook/Models/Stamp.swift`  
**Time:** 15 minutes  
**Risk:** NONE (all fields optional, backward compatible)

### Step 1.1: Add New Fields to Struct

Find line 15 (after `let geohash: String?`) and add:

```swift
let geohash: String? // Optional for backward compatibility

// ==================== VISIBILITY SYSTEM ====================
// Fields for moderation and temporary stamps
// All fields are optional for backward compatibility with existing stamps
// See docs/VISIBILITY_SYSTEM_IMPLEMENTATION.md for details
// ===========================================================

/// Visibility status of the stamp
/// - "active": Normal stamp, visible to all users (DEFAULT)
/// - "hidden": Temporarily hidden (e.g., under review)
/// - "removed": Permanently removed (e.g., reported content)
/// If nil, defaults to "active" for backward compatibility
let status: String?

/// Date when stamp becomes visible (for future releases or events)
/// - If nil: stamp is visible immediately (DEFAULT)
/// - If set: stamp only appears after this date
/// Example: New museum opening on June 1st
let availableFrom: Date?

/// Date when stamp stops being visible (for temporary events)
/// - If nil: stamp is visible forever (DEFAULT)
/// - If set: stamp disappears after this date
/// Example: Festival stamp only visible during festival week
/// Note: Users who collected it before expiry keep it in their collection
let availableUntil: Date?

/// Reason why stamp was removed (for audit trail and moderation)
/// - Only relevant when status = "removed"
/// - Example: "User reported inappropriate content"
let removalReason: String?
```

### Step 1.2: Add Computed Property for Availability Check

Add after the `isWelcomeStamp` computed property (around line 29):

```swift
var isWelcomeStamp: Bool {
    return id == "your-first-stamp"
}

// ==================== VISIBILITY CHECK ====================
/// Check if this stamp should be visible to users right now
/// This is the SINGLE SOURCE OF TRUTH for stamp visibility
/// 
/// Returns false if:
/// 1. Status is not "active" (hidden or removed)
/// 2. Current time is before availableFrom date
/// 3. Current time is after availableUntil date
///
/// This does NOT affect collected stamps - users keep stamps they collected
/// even after they become unavailable
/// ==========================================================
var isCurrentlyAvailable: Bool {
    // 1. Check status (default to "active" if nil for backward compatibility)
    let currentStatus = status ?? "active"
    guard currentStatus == "active" else {
        // Stamp is hidden or removed
        return false
    }
    
    let now = Date()
    
    // 2. Check if stamp is not yet available (future release)
    if let from = availableFrom, now < from {
        return false
    }
    
    // 3. Check if stamp has expired (past event)
    if let until = availableUntil, now > until {
        return false
    }
    
    // All checks passed - stamp is currently available
    return true
}
```

### Step 1.3: Update CodingKeys Enum

Find the `enum CodingKeys` (around line 68) and update:

```swift
enum CodingKeys: String, CodingKey {
    case id, name, latitude, longitude, address, imageName, imageUrl, about, thingsToDoFromEditors, geohash
    case collectionIds
    case collectionId
    // Visibility system fields
    case status, availableFrom, availableUntil, removalReason
}
```

### Step 1.4: Update Init Method

Find the main `init` method (around line 74) and update:

```swift
init(id: String, name: String, latitude: Double, longitude: Double, address: String, 
     imageName: String = "", imageUrl: String? = nil, collectionIds: [String], 
     about: String, thingsToDoFromEditors: [String] = [], geohash: String? = nil,
     status: String? = nil, availableFrom: Date? = nil, 
     availableUntil: Date? = nil, removalReason: String? = nil) {
    self.id = id
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
    self.address = address
    self.imageName = imageName
    self.imageUrl = imageUrl
    self.collectionIds = collectionIds
    self.about = about
    self.thingsToDoFromEditors = thingsToDoFromEditors
    self.geohash = geohash
    // Visibility system fields
    self.status = status
    self.availableFrom = availableFrom
    self.availableUntil = availableUntil
    self.removalReason = removalReason
}
```

### Step 1.5: Update Decoder Init

Find `init(from decoder:)` (around line 88) and add before the collectionIds decoding:

```swift
thingsToDoFromEditors = try container.decodeIfPresent([String].self, forKey: .thingsToDoFromEditors) ?? []
geohash = try container.decodeIfPresent(String.self, forKey: .geohash)

// Decode visibility system fields (all optional for backward compatibility)
status = try container.decodeIfPresent(String.self, forKey: .status)
availableFrom = try container.decodeIfPresent(Date.self, forKey: .availableFrom)
availableUntil = try container.decodeIfPresent(Date.self, forKey: .availableUntil)
removalReason = try container.decodeIfPresent(String.self, forKey: .removalReason)

// Support both collectionIds (array) and collectionId (string) for backward compatibility
```

### Step 1.6: Update Encoder Method

Find `func encode(to encoder:)` (around line 111) and add before the closing brace:

```swift
try container.encode(thingsToDoFromEditors, forKey: .thingsToDoFromEditors)
try container.encodeIfPresent(geohash, forKey: .geohash)

// Encode visibility system fields (only if present)
try container.encodeIfPresent(status, forKey: .status)
try container.encodeIfPresent(availableFrom, forKey: .availableFrom)
try container.encodeIfPresent(availableUntil, forKey: .availableUntil)
try container.encodeIfPresent(removalReason, forKey: .removalReason)
```

### ✅ Phase 1 Checkpoint
- [ ] Build the app (Cmd+B) - should compile with 0 errors
- [ ] Run the app - should work exactly as before
- [ ] Existing stamps don't have new fields → they default to "active" → visible as normal

**Nothing should break at this point!** We just added fields, didn't change behavior yet.

---

## Phase 2: Add Filtering Logic
**Files:** `StampsManager.swift`, `FirebaseService.swift`  
**Time:** 30 minutes  
**Risk:** LOW (only filters display, doesn't affect collected stamps)

### Step 2.1: Add Filter Helper to StampsManager

**File:** `Stampbook/Managers/StampsManager.swift`

Add this new method after the `clearCache()` method (around line 296):

```swift
func clearCache() {
    stampCache.removeAll()
    if DEBUG_STAMPS {
        print("🗑️ [StampsManager] Cleared stamp cache")
    }
}

// ==================== VISIBILITY FILTERING ====================
/// Filter stamps to only show currently available ones
/// This respects the visibility system (status, availableFrom, availableUntil)
///
/// IMPORTANT: This filter is for DISPLAYING stamps (map, collections, suggestions)
/// This does NOT filter collected stamps - users keep what they collected
///
/// - Parameter stamps: Array of stamps to filter
/// - Returns: Only stamps that are currently available to collect
/// =============================================================
private func filterAvailableStamps(_ stamps: [Stamp]) -> [Stamp] {
    let available = stamps.filter { $0.isCurrentlyAvailable }
    
    if DEBUG_STAMPS && available.count < stamps.count {
        let filtered = stamps.count - available.count
        print("🔍 [StampsManager] Filtered out \(filtered) unavailable stamps")
        print("   Hidden stamps: \(stamps.filter { !$0.isCurrentlyAvailable }.map { $0.id })")
    }
    
    return available
}
```

### Step 2.2: Apply Filter to fetchStamps Method

Find the `fetchStamps(ids:)` method (around line 156) and update the return statement:

```swift
func fetchStamps(ids: [String]) async -> [Stamp] {
    var results: [Stamp] = []
    var uncachedIds: [String] = []
    
    // ... existing cache check code ...
    
    if DEBUG_STAMPS {
        print("✅ [StampsManager] fetchStamps complete: \(results.count)/\(ids.count) stamps")
    }
    
    // VISIBILITY FILTER: Only return stamps that are currently available
    // This prevents removed or expired stamps from appearing on map/collections
    let available = filterAvailableStamps(results)
    
    return available
}
```

### Step 2.3: Apply Filter to fetchAllStamps Method

Find the `fetchAllStamps()` method (around line 210-245) and update:

```swift
func fetchAllStamps() async -> [Stamp] {
    if DEBUG_STAMPS {
        print("🌍 [StampsManager] Fetching ALL stamps globally")
    }
    
    do {
        let fetched = try await firebaseService.fetchStamps()
        
        // Add to cache
        for stamp in fetched {
            stampCache.set(stamp.id, stamp)
        }
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] Fetched \(fetched.count) stamps globally")
        }
        
        // VISIBILITY FILTER: Only return stamps that are currently available
        let available = filterAvailableStamps(fetched)
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] Returning \(available.count) available stamps")
        }
        
        return available
    } catch {
        print("❌ [StampsManager] Failed to fetch all stamps: \(error.localizedDescription)")
        return []
    }
}
```

### Step 2.4: Apply Filter to fetchStampsInCollection Method

Find the `fetchStampsInCollection(collectionId:)` method (around line 260) and update:

```swift
func fetchStampsInCollection(collectionId: String) async -> [Stamp] {
    if DEBUG_STAMPS {
        print("📚 [StampsManager] Fetching stamps in collection: \(collectionId)")
    }
    
    do {
        let fetched = try await firebaseService.fetchStampsInCollection(collectionId: collectionId)
        
        // VISIBILITY FILTER: Only show stamps that are currently available
        // Users who already collected unavailable stamps still keep them
        let available = filterAvailableStamps(fetched)
        
        // Add to cache
        for stamp in available {
            stampCache.set(stamp.id, stamp)
        }
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] Fetched \(available.count) stamps in collection")
        }
        return available
    } catch {
        print("❌ [StampsManager] Failed to fetch stamps in collection: \(error.localizedDescription)")
        return []
    }
}
```

### Step 2.5: Add Force Refresh Option (Optional but Recommended)

Add this new method after `fetchAllStamps()`:

```swift
/// Force refresh stamps from server (bypasses cache)
/// Use this when you need guaranteed fresh data:
/// - After user reports content (force refresh to see if it's removed)
/// - On pull-to-refresh
/// - After app returns from background (to check for expired event stamps)
///
/// - Returns: Array of currently available stamps
func forceRefreshStamps() async -> [Stamp] {
    if DEBUG_STAMPS {
        print("🔄 [StampsManager] FORCE refreshing stamps from server...")
    }
    
    do {
        // Force fetch from server, not cache
        let fetched = try await firebaseService.fetchStamps(forceRefresh: true)
        
        // Clear old cache and update with fresh data
        stampCache.removeAll()
        
        let available = filterAvailableStamps(fetched)
        
        // Cache the fresh data
        for stamp in available {
            stampCache.set(stamp.id, stamp)
        }
        
        // Update last refresh time
        await MainActor.run {
            lastRefreshTime = Date()
        }
        
        if DEBUG_STAMPS {
            print("✅ [StampsManager] Force refresh complete: \(available.count) stamps")
        }
        
        return available
    } catch {
        print("❌ [StampsManager] Failed to force refresh: \(error.localizedDescription)")
        return []
    }
}
```

### Step 2.6: Update FirebaseService to Support Force Refresh

**File:** `Stampbook/Services/FirebaseService.swift`

Find the `fetchStamps()` method (around line 240) and update:

```swift
/// Fetch all stamps from Firestore
/// - Parameter forceRefresh: If true, fetches from server instead of cache
/// - Returns: Array of all stamps (no filtering - caller must filter)
func fetchStamps(forceRefresh: Bool = false) async throws -> [Stamp] {
    // If force refresh requested, bypass cache and fetch from server
    let source: FirestoreSource = forceRefresh ? .server : .default
    
    let snapshot = try await db
        .collection("stamps")
        .getDocuments(source: source)
    
    let stamps = snapshot.documents.compactMap { doc -> Stamp? in
        try? doc.data(as: Stamp.self)
    }
    
    #if DEBUG
    print("🔥 [FirebaseService] Fetched \(stamps.count) stamps (source: \(forceRefresh ? "server" : "cache/server"))")
    #endif
    
    return stamps
}
```

### ✅ Phase 2 Checkpoint
- [ ] Build the app (Cmd+B) - should compile with 0 errors
- [ ] Run the app - should work exactly as before
- [ ] All existing stamps show normally (they have status=nil → defaults to "active")
- [ ] No stamps are filtered yet (none are marked as removed)

**Still nothing should break!** Filtering is in place but has no effect yet.

---

## Phase 3: Update Upload Script
**File:** `upload_stamps_to_firestore.js`  
**Time:** 20 minutes  
**Risk:** LOW (test on staging first)

### Step 3.1: Backup Current Script

```bash
cp upload_stamps_to_firestore.js upload_stamps_to_firestore.js.backup
```

### Step 3.2: Update Script with Sync Deletions

Replace the entire `upload_stamps_to_firestore.js` file with:

```javascript
#!/usr/bin/env node

/**
 * Upload stamps.json and collections.json to Firestore
 * 
 * NEW FEATURES:
 * - Syncs deletions (removes stamps from Firebase that aren't in JSON)
 * - Supports visibility system (status, availableFrom, availableUntil)
 * - Auto-generates geohashes
 * 
 * IMPORTANT: This script now DELETES stamps from Firebase if they're not in stamps.json
 * Make sure your stamps.json is correct before running!
 * 
 * Usage: node upload_stamps_to_firestore.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Encode coordinates to geohash string
 */
function encodeGeohash(latitude, longitude, precision = 8) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let latRange = [-90.0, 90.0];
  let lonRange = [-180.0, 180.0];
  let hash = '';
  let bits = 0;
  let bit = 0;
  let even = true;
  
  while (hash.length < precision) {
    if (even) {
      const mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude > mid) {
        bit |= (1 << (4 - bits));
        lonRange[0] = mid;
      } else {
        lonRange[1] = mid;
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (latitude > mid) {
        bit |= (1 << (4 - bits));
        latRange[0] = mid;
      } else {
        latRange[1] = mid;
      }
    }
    
    even = !even;
    bits++;
    
    if (bits === 5) {
      hash += base32[bit];
      bits = 0;
      bit = 0;
    }
  }
  
  return hash;
}

/**
 * Convert ISO date string to Firestore Timestamp (or null)
 */
function parseDate(dateString) {
  if (!dateString) return null;
  try {
    return admin.firestore.Timestamp.fromDate(new Date(dateString));
  } catch (error) {
    console.error(`⚠️  Invalid date format: ${dateString}`);
    return null;
  }
}

async function uploadStamps() {
  console.log('📚 Reading stamps.json...');
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  
  console.log(`✅ Found ${stampsData.length} stamps in JSON\n`);
  
  // ==================== SYNC DELETIONS ====================
  // Get all existing stamps from Firebase
  console.log('🔍 Checking for stamps to delete...');
  const snapshot = await db.collection('stamps').get();
  const existingIds = new Set(snapshot.docs.map(doc => doc.id));
  const jsonIds = new Set(stampsData.map(stamp => stamp.id));
  
  // Find stamps in Firebase but not in JSON (these should be deleted)
  const toDelete = [...existingIds].filter(id => !jsonIds.has(id));
  
  if (toDelete.length > 0) {
    console.log(`\n🗑️  Found ${toDelete.length} stamps to DELETE:`);
    toDelete.forEach(id => console.log(`   - ${id}`));
    
    // Delete them
    for (const id of toDelete) {
      try {
        await db.collection('stamps').doc(id).delete();
        console.log(`   ✓ Deleted: ${id}`);
      } catch (error) {
        console.error(`   ✗ Failed to delete ${id}:`, error.message);
      }
    }
  } else {
    console.log('✅ No stamps to delete\n');
  }
  // ========================================================
  
  console.log('\n📤 Uploading/updating stamps to Firestore...');
  let uploadedCount = 0;
  let updatedCount = 0;
  
  for (const stamp of stampsData) {
    try {
      // Auto-generate geohash from coordinates
      const geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
      
      // Prepare stamp data with visibility system fields
      const stampData = {
        id: stamp.id,
        name: stamp.name,
        latitude: stamp.latitude,
        longitude: stamp.longitude,
        address: stamp.address,
        imageUrl: stamp.imageUrl || '',
        collectionIds: stamp.collectionIds,
        about: stamp.about,
        notesFromOthers: stamp.notesFromOthers || [],
        thingsToDoFromEditors: stamp.thingsToDoFromEditors || [],
        geohash: geohash
      };
      
      // Add visibility system fields (only if present in JSON)
      if (stamp.status) {
        stampData.status = stamp.status;
      }
      if (stamp.availableFrom) {
        stampData.availableFrom = parseDate(stamp.availableFrom);
      }
      if (stamp.availableUntil) {
        stampData.availableUntil = parseDate(stamp.availableUntil);
      }
      if (stamp.removalReason) {
        stampData.removalReason = stamp.removalReason;
      }
      
      // Check if this is a new stamp or an update
      const isNew = !existingIds.has(stamp.id);
      
      await db.collection('stamps').doc(stamp.id).set(stampData);
      
      if (isNew) {
        console.log(`  ✓ CREATED: ${stamp.name} (${stamp.id})`);
      } else {
        console.log(`  ✓ UPDATED: ${stamp.name} (${stamp.id})`);
      }
      
      // Show visibility status if present
      if (stamp.status && stamp.status !== 'active') {
        console.log(`    📌 Status: ${stamp.status}`);
      }
      if (stamp.availableFrom || stamp.availableUntil) {
        const from = stamp.availableFrom || 'always';
        const until = stamp.availableUntil || 'forever';
        console.log(`    📅 Available: ${from} → ${until}`);
      }
      
      uploadedCount++;
      if (!isNew) updatedCount++;
    } catch (error) {
      console.error(`  ✗ Failed to upload ${stamp.id}:`, error.message);
    }
  }
  
  console.log(`\n✅ Successfully processed ${uploadedCount}/${stampsData.length} stamps`);
  console.log(`   📊 Created: ${uploadedCount - updatedCount}, Updated: ${updatedCount}, Deleted: ${toDelete.length}\n`);
}

async function uploadCollections() {
  console.log('📚 Reading collections.json...');
  const collectionsPath = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');
  const collectionsData = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
  
  console.log(`✅ Found ${collectionsData.length} collections\n`);
  
  console.log('📤 Uploading collections to Firestore...');
  let uploadedCount = 0;
  
  for (const collection of collectionsData) {
    try {
      await db.collection('collections').doc(collection.id).set({
        id: collection.id,
        name: collection.name,
        description: collection.description,
        region: collection.region,
        totalStamps: collection.totalStamps
      });
      
      uploadedCount++;
      console.log(`  ✓ Uploaded: ${collection.name} (${collection.id})`);
    } catch (error) {
      console.error(`  ✗ Failed to upload ${collection.id}:`, error.message);
    }
  }
  
  console.log(`\n✅ Successfully uploaded ${uploadedCount}/${collectionsData.length} collections\n`);
}

async function main() {
  console.log('🚀 Starting Firestore upload with SYNC...\n');
  console.log('⚠️  WARNING: This script will DELETE stamps from Firebase that aren\'t in stamps.json\n');
  
  try {
    await uploadStamps();
    await uploadCollections();
    
    console.log('🎉 Upload complete!\n');
    console.log('✅ Stamps synced (added, updated, and deleted as needed)');
    console.log('✅ Geohashes automatically generated');
    console.log('✅ Visibility system fields preserved\n');
    
  } catch (error) {
    console.error('❌ Upload failed:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

main();
```

### ✅ Phase 3 Checkpoint
- [ ] Test the script on a backup/staging Firebase first
- [ ] Verify it doesn't delete anything unexpected
- [ ] Run it on production
- [ ] Verify all 37 stamps are still there

**This is the key change** - now deletions from JSON sync to Firebase!

---

## Phase 4: Create Admin Tools
**Time:** 30 minutes  
**Risk:** NONE (these are helper scripts)

### Script 1: Remove Stamp (For Moderation)

**File:** `remove_stamp.js` (NEW FILE)

```javascript
#!/usr/bin/env node

/**
 * Remove a stamp (soft delete for moderation)
 * 
 * This script marks a stamp as "removed" without deleting it from Firebase.
 * - Stamp becomes invisible to all users immediately
 * - Users who already collected it keep it in their collection
 * - Stamp stays in database for audit trail
 * 
 * Usage: node remove_stamp.js <stamp-id> "<reason>"
 * Example: node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function removeStamp(stampId, reason) {
  console.log(`🗑️  Removing stamp: ${stampId}\n`);
  console.log(`📝 Reason: ${reason}\n`);
  
  try {
    // Check if stamp exists
    const docRef = db.collection('stamps').doc(stampId);
    const doc = await docRef.get();
    
    if (!doc.exists) {
      console.error(`❌ Error: Stamp "${stampId}" not found in Firebase`);
      process.exit(1);
    }
    
    const stampData = doc.data();
    console.log(`📍 Found: ${stampData.name}`);
    console.log(`   Location: ${stampData.address}\n`);
    
    // Update stamp to mark as removed (SOFT DELETE)
    await docRef.update({
      status: 'removed',
      removalReason: reason,
      removedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Successfully removed stamp');
    console.log('   - Status: removed');
    console.log('   - Stamp is now invisible to all users');
    console.log('   - Users who collected it keep it in their collection');
    console.log('   - Data preserved in database for audit trail\n');
    
    // Count how many users have collected this stamp
    const collectedSnapshot = await db.collection('collected_stamps')
      .where('stampId', '==', stampId)
      .get();
    
    if (collectedSnapshot.size > 0) {
      console.log(`ℹ️  Note: ${collectedSnapshot.size} user(s) have collected this stamp and will keep it\n`);
    }
    
  } catch (error) {
    console.error('❌ Error removing stamp:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

// Parse command line arguments
const stampId = process.argv[2];
const reason = process.argv[3];

if (!stampId || !reason) {
  console.error('❌ Usage: node remove_stamp.js <stamp-id> "<reason>"');
  console.error('   Example: node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"');
  process.exit(1);
}

removeStamp(stampId, reason);
```

Make it executable:
```bash
chmod +x remove_stamp.js
```

### Script 2: Restore Stamp (Undo Removal)

**File:** `restore_stamp.js` (NEW FILE)

```javascript
#!/usr/bin/env node

/**
 * Restore a removed stamp
 * 
 * This script changes a stamp's status back to "active" after removal.
 * Use this if a stamp was removed by mistake or after reviewing an appeal.
 * 
 * Usage: node restore_stamp.js <stamp-id>
 * Example: node restore_stamp.js us-ca-sf-good-stamp
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function restoreStamp(stampId) {
  console.log(`♻️  Restoring stamp: ${stampId}\n`);
  
  try {
    const docRef = db.collection('stamps').doc(stampId);
    const doc = await docRef.get();
    
    if (!doc.exists) {
      console.error(`❌ Error: Stamp "${stampId}" not found in Firebase`);
      process.exit(1);
    }
    
    const stampData = doc.data();
    console.log(`📍 Found: ${stampData.name}`);
    console.log(`   Current status: ${stampData.status || 'active'}\n`);
    
    if (stampData.status !== 'removed' && stampData.status !== 'hidden') {
      console.log('⚠️  Warning: This stamp is not removed or hidden');
      console.log('   It may already be active. Continuing anyway...\n');
    }
    
    // Restore stamp to active status
    await docRef.update({
      status: 'active',
      restoredAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Successfully restored stamp');
    console.log('   - Status: active');
    console.log('   - Stamp is now visible to all users again\n');
    
  } catch (error) {
    console.error('❌ Error restoring stamp:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

const stampId = process.argv[2];

if (!stampId) {
  console.error('❌ Usage: node restore_stamp.js <stamp-id>');
  console.error('   Example: node restore_stamp.js us-ca-sf-good-stamp');
  process.exit(1);
}

restoreStamp(stampId);
```

Make it executable:
```bash
chmod +x restore_stamp.js
```

### Script 3: List Removed Stamps (Audit)

**File:** `list_removed_stamps.js` (NEW FILE)

```javascript
#!/usr/bin/env node

/**
 * List all removed/hidden stamps (for audit and review)
 * 
 * Shows all stamps that are not active, with reasons and dates
 * 
 * Usage: node list_removed_stamps.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function listRemovedStamps() {
  console.log('🔍 Searching for removed/hidden stamps...\n');
  
  try {
    const snapshot = await db.collection('stamps').get();
    
    const removed = [];
    const hidden = [];
    let activeCount = 0;
    
    snapshot.docs.forEach(doc => {
      const data = doc.data();
      const status = data.status || 'active';
      
      if (status === 'removed') {
        removed.push({ id: doc.id, ...data });
      } else if (status === 'hidden') {
        hidden.push({ id: doc.id, ...data });
      } else {
        activeCount++;
      }
    });
    
    console.log(`📊 Stamp Status Summary:`);
    console.log(`   Active: ${activeCount}`);
    console.log(`   Removed: ${removed.length}`);
    console.log(`   Hidden: ${hidden.length}`);
    console.log(`   Total: ${snapshot.size}\n`);
    
    if (removed.length > 0) {
      console.log('❌ REMOVED STAMPS:\n');
      removed.forEach(stamp => {
        console.log(`   ${stamp.id}`);
        console.log(`   Name: ${stamp.name}`);
        console.log(`   Reason: ${stamp.removalReason || 'No reason provided'}`);
        if (stamp.removedAt) {
          console.log(`   Removed: ${stamp.removedAt.toDate().toISOString()}`);
        }
        console.log('');
      });
    }
    
    if (hidden.length > 0) {
      console.log('🙈 HIDDEN STAMPS:\n');
      hidden.forEach(stamp => {
        console.log(`   ${stamp.id}`);
        console.log(`   Name: ${stamp.name}`);
        console.log(`   Reason: ${stamp.removalReason || 'Under review'}`);
        console.log('');
      });
    }
    
    if (removed.length === 0 && hidden.length === 0) {
      console.log('✅ No removed or hidden stamps found\n');
    }
    
  } catch (error) {
    console.error('❌ Error listing stamps:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

listRemovedStamps();
```

Make it executable:
```bash
chmod +x list_removed_stamps.js
```

### ✅ Phase 4 Checkpoint
- [ ] Test each script with a test stamp ID
- [ ] Verify remove_stamp.js hides the stamp in the app
- [ ] Verify restore_stamp.js brings it back
- [ ] Verify list_removed_stamps.js shows the right counts

---

## Phase 5: Testing
**Time:** 30 minutes  
**Risk:** This is where we catch any issues

### Test 1: Backward Compatibility
**Goal:** Verify existing stamps still work

1. Build and run the app
2. Open map view → All 37 stamps should appear normally
3. Open a collection → All stamps should appear
4. Collect a stamp → Should work as before
5. Check profile → Collected stamp should appear

✅ **Expected:** Everything works exactly as before

### Test 2: Remove a Stamp (Moderation Use Case)
**Goal:** Test reported stamp removal

1. Pick a test stamp (e.g., "Neighbor's Corner")
2. Run: `node remove_stamp.js us-ca-sf-neighbor "Testing removal system"`
3. Force quit and reopen the app
4. Map view → Stamp should be gone
5. Collection view → Stamp should be gone
6. If you had collected it → Should still be in your profile ✅

✅ **Expected:** Stamp invisible on map/collections, but kept in user's collection

### Test 3: Restore a Stamp
**Goal:** Test undo functionality

1. Run: `node restore_stamp.js us-ca-sf-neighbor`
2. Force quit and reopen the app
3. Stamp should reappear on map and in collection

✅ **Expected:** Stamp is back

### Test 4: Temporary Stamp (Event Use Case)
**Goal:** Test time-based stamps

1. Edit `stamps.json`, add a new test stamp:

```json
{
  "id": "test-future-stamp",
  "name": "Test Future Event",
  "latitude": 37.77,
  "longitude": -122.42,
  "address": "Test St\nSan Francisco, CA, USA 94102",
  "collectionIds": ["sf-must-visits"],
  "about": "This is a test event stamp",
  "thingsToDoFromEditors": ["Test tip"],
  "imageUrl": "https://placeholder.com/test.jpg",
  "status": "active",
  "availableFrom": "2025-12-01T00:00:00Z",
  "availableUntil": "2025-12-07T23:59:59Z"
}
```

2. Run: `node upload_stamps_to_firestore.js`
3. Open app → Stamp should NOT appear (it's in the future)
4. Change `availableFrom` to yesterday, `availableUntil` to tomorrow
5. Run upload script again
6. Open app → Stamp should appear now
7. Change `availableUntil` to yesterday
8. Run upload script again
9. Open app → Stamp should disappear (expired)

✅ **Expected:** Stamp respects date ranges

### Test 5: Deletion Sync
**Goal:** Test that deletions from JSON sync to Firebase

1. Count stamps in Firebase: `node list_removed_stamps.js`
2. Remove the test stamp from `stamps.json`
3. Run: `node upload_stamps_to_firestore.js`
4. Script should say "Found 1 stamps to DELETE"
5. Check Firebase → Test stamp should be gone

✅ **Expected:** Deletions from JSON propagate to Firebase

### Test 6: Force Refresh (Cache Testing)
**Goal:** Ensure removed stamps disappear without reinstalling

1. Open app normally (uses cache)
2. While app is open, run: `node remove_stamp.js <some-stamp> "Test"`
3. In app, pull to refresh on map (should trigger force refresh eventually)
4. Stamp should disappear within 5-10 seconds

✅ **Expected:** Cache updates show removed stamps disappearing

---

## Use Cases - How to Handle Each Scenario

### ✅ Use Case 1: User Reports Inappropriate Stamp

**Steps:**
1. User reports stamp via app (you get notification)
2. You review the report
3. If valid, run:
   ```bash
   node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"
   ```
4. Stamp disappears for all users on next app open
5. Users who collected it keep it (fair)

**Timeline:** Stamp removed within minutes for all users

### ✅ Use Case 2: Create 1-Week Event Stamp

**Steps:**
1. Add to `stamps.json`:
   ```json
   {
     "id": "sf-outside-lands-2025",
     "name": "Outside Lands Music Festival",
     "status": "active",
     "availableFrom": "2025-08-08T00:00:00Z",
     "availableUntil": "2025-08-10T23:59:59Z",
     ...
   }
   ```
2. Run: `node upload_stamps_to_firestore.js`
3. Stamp automatically appears Aug 8 and disappears Aug 11
4. Users who collected it during the festival keep it forever

**Timeline:** Fully automated based on dates

### ✅ Use Case 3: Delete a Stamp Permanently

**Steps:**
1. Remove from `stamps.json`
2. Run: `node upload_stamps_to_firestore.js`
3. Script deletes it from Firebase
4. Disappears from all users' maps on next app open

**Timeline:** Immediate on next app open

### ✅ Use Case 4: Hide Stamp Temporarily (Under Review)

**Steps:**
1. Update stamp in Firebase directly:
   ```bash
   # Create a quick helper script or use Firebase Console
   # Set status: "hidden"
   ```
2. Or update stamps.json with `"status": "hidden"` and upload
3. Stamp disappears but can be restored later

---

## Rollback Plan

### If Something Breaks:

**Quick Rollback (Restore Old Script):**
```bash
cp upload_stamps_to_firestore.js.backup upload_stamps_to_firestore.js
```

**Remove Visibility Filtering (Emergency):**

In `StampsManager.swift`, comment out the filtering:

```swift
// Temporary rollback - remove this to re-enable filtering
// let available = filterAvailableStamps(results)
// return available
return results  // Return all stamps without filtering
```

**Restore All Stamps to Active:**

Run this emergency script:

```javascript
// emergency_restore_all.js
const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function restoreAll() {
  const snapshot = await db.collection('stamps').get();
  
  for (const doc of snapshot.docs) {
    await doc.ref.update({ status: 'active' });
    console.log(`Restored: ${doc.id}`);
  }
  
  console.log(`✅ Restored ${snapshot.size} stamps to active`);
  process.exit(0);
}

restoreAll();
```

---

## Summary Checklist

### Before Implementation:
- [ ] Read this entire document
- [ ] Backup Firebase data (export from console)
- [ ] Backup current upload script
- [ ] Test on staging environment if available

### During Implementation:
- [ ] Phase 1: Update Stamp model (15 min)
- [ ] Phase 1 Checkpoint: Build succeeds
- [ ] Phase 2: Add filtering logic (30 min)
- [ ] Phase 2 Checkpoint: App runs normally
- [ ] Phase 3: Update upload script (20 min)
- [ ] Phase 3 Checkpoint: Test on staging
- [ ] Phase 4: Create admin tools (30 min)
- [ ] Phase 4 Checkpoint: Test each script
- [ ] Phase 5: Full testing (30 min)

### After Implementation:
- [ ] All tests pass
- [ ] Document in README how to use admin scripts
- [ ] Train yourself on moderation workflow
- [ ] Monitor first few days for any issues

---

## Files Modified Summary

**Swift Files:**
- ✏️ `Stampbook/Models/Stamp.swift` - Added 4 fields + computed property
- ✏️ `Stampbook/Managers/StampsManager.swift` - Added filtering
- ✏️ `Stampbook/Services/FirebaseService.swift` - Added force refresh

**JavaScript Files:**
- ✏️ `upload_stamps_to_firestore.js` - Added sync deletions + visibility fields
- ➕ `remove_stamp.js` - NEW - Moderation tool
- ➕ `restore_stamp.js` - NEW - Undo removal
- ➕ `list_removed_stamps.js` - NEW - Audit tool

**Documentation:**
- ➕ `docs/VISIBILITY_SYSTEM_IMPLEMENTATION.md` - THIS FILE

**Total:** 4 files modified, 4 files created

---

## Questions & Troubleshooting

### Q: What if a user complains they can't see a stamp?
**A:** Check if it's removed: `node list_removed_stamps.js`

### Q: What if I accidentally remove the wrong stamp?
**A:** Restore it immediately: `node restore_stamp.js <stamp-id>`

### Q: How do I test without affecting production?
**A:** Use a separate Firebase project for staging, or temporarily change status to "hidden" instead of "removed"

### Q: What happens to collected stamps when a stamp is removed?
**A:** Users keep them! The filtering only applies to uncollected stamps on map/collections

### Q: Can I delete a stamp permanently?
**A:** Yes, remove it from `stamps.json` and run the upload script

### Q: How quickly do changes propagate?
**A:** Usually within seconds to minutes, depending on Firebase cache. Force quit + reopen guarantees fresh data.

---

**Ready to implement? Start with Phase 1!**

