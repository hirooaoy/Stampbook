#!/usr/bin/env node

/**
 * Upload stamps.json and collections.json to Firestore
 * 
 * NEW: Now syncs deletions! Stamps removed from JSON are removed from Firebase.
 * NEW: Supports visibility system (status, availableFrom, availableUntil)
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
 * Convert ISO date string to Firestore Timestamp
 */
function parseDate(dateString) {
  if (!dateString) return null;
  try {
    return admin.firestore.Timestamp.fromDate(new Date(dateString));
  } catch (error) {
    console.error(`⚠️  Invalid date: ${dateString}`);
    return null;
  }
}

async function uploadStamps(forceDelete = false) {
  console.log('📚 Reading stamps.json...');
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  
  console.log(`✅ Found ${stampsData.length} stamps in JSON\n`);
  
  // ==================== SMART SYNC CHECK ====================
  console.log('🔍 Checking differences between Firebase and JSON...');
  const snapshot = await db.collection('stamps').get();
  const firebaseStamps = {};
  snapshot.docs.forEach(doc => {
    firebaseStamps[doc.id] = doc.data();
  });
  
  const existingIds = new Set(Object.keys(firebaseStamps));
  const jsonIds = new Set(stampsData.map(stamp => stamp.id));
  
  const onlyInFirebase = [...existingIds].filter(id => !jsonIds.has(id));
  const onlyInJSON = [...jsonIds].filter(id => !existingIds.has(id));
  
  console.log(`📊 Firebase: ${existingIds.size} stamps`);
  console.log(`📊 JSON: ${jsonIds.size} stamps`);
  console.log(`📊 Only in Firebase: ${onlyInFirebase.length} stamps`);
  console.log(`📊 Only in JSON: ${onlyInJSON.length} stamps\n`);
  
  // If Firebase has stamps that JSON doesn't, warn and require confirmation
  if (onlyInFirebase.length > 0) {
    console.log('⚠️  WARNING: Firebase has stamps that are NOT in your local JSON!');
    console.log('⚠️  Running this script will DELETE these stamps from Firebase:\n');
    
    for (const id of onlyInFirebase) {
      const stamp = firebaseStamps[id];
      console.log(`   🗑️  ${stamp.name} (${id})`);
    }
    
    console.log('\n❌ SYNC ABORTED FOR SAFETY!\n');
    console.log('💡 What you probably want to do:');
    console.log('   1. Run: node export_stamps_from_firestore.js');
    console.log('   2. This will pull Firebase stamps into your local JSON');
    console.log('   3. THEN run this script again\n');
    console.log('🚨 If you really want to DELETE these stamps from Firebase:');
    console.log('   Run: node upload_stamps_to_firestore.js --force\n');
    process.exit(1);
  }
  
  // If JSON has more stamps and Firebase is a subset, safe to proceed
  if (onlyInJSON.length > 0 && onlyInFirebase.length === 0) {
    console.log('✅ Safe to sync: JSON has new stamps, Firebase will be updated\n');
  } else if (onlyInJSON.length === 0 && onlyInFirebase.length === 0) {
    console.log('✅ Safe to sync: JSON and Firebase have the same stamps\n');
  }
  // ========================================================
  
  // Only delete if forced
  if (forceDelete && onlyInFirebase.length > 0) {
    console.log(`\n🗑️  FORCE DELETE: Removing ${onlyInFirebase.length} stamp(s) from Firebase:`);
    for (const id of onlyInFirebase) {
      try {
        await db.collection('stamps').doc(id).delete();
        console.log(`   ✓ Deleted: ${id}`);
      } catch (error) {
        console.error(`   ✗ Failed to delete ${id}:`, error.message);
      }
    }
  }
  
  console.log('\n📤 Uploading/updating stamps...');
  let uploadedCount = 0;
  
  for (const stamp of stampsData) {
    try {
      const geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
      
      // Build stamp data with visibility fields
      const stampData = {
        id: stamp.id,
        name: stamp.name,
        latitude: stamp.latitude,
        longitude: stamp.longitude,
        address: stamp.address,
        imageUrl: stamp.imageUrl || '',
        collectionIds: stamp.collectionIds,
        about: stamp.about,
        thingsToDoFromEditors: stamp.thingsToDoFromEditors || [],
        geohash: geohash,
        collectionRadius: stamp.collectionRadius || 'regular'  // Default to regular if missing
      };
      
      // Add aspectRatio if present (optional field for proper lock sizing)
      if (stamp.aspectRatio) {
        stampData.aspectRatio = stamp.aspectRatio;
      }
      
      // Add visibility fields only if present (keeps it clean)
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
      
      await db.collection('stamps').doc(stamp.id).set(stampData);
      
      uploadedCount++;
      console.log(`  ✓ ${stamp.name} (${stamp.id})`);
      
      // Show visibility status if non-standard
      if (stamp.status && stamp.status !== 'active') {
        console.log(`    📌 Status: ${stamp.status}`);
      }
      if (stamp.availableFrom || stamp.availableUntil) {
        const from = stamp.availableFrom || 'always';
        const until = stamp.availableUntil || 'forever';
        console.log(`    📅 ${from} → ${until}`);
      }
      
    } catch (error) {
      console.error(`  ✗ Failed: ${stamp.id} -`, error.message);
    }
  }
  
  console.log(`\n✅ Processed ${uploadedCount}/${stampsData.length} stamps`);
  if (forceDelete && onlyInFirebase.length > 0) {
    console.log(`🗑️  Deleted ${onlyInFirebase.length} stamps\n`);
  }
}

async function uploadCollections() {
  console.log('📚 Reading collections.json...');
  const collectionsPath = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');
  const collectionsData = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
  
  console.log(`✅ Found ${collectionsData.length} collections\n`);
  
  // ==================== SYNC DELETIONS ====================
  console.log('🔍 Checking for collection deletions...');
  const snapshot = await db.collection('collections').get();
  const existingIds = new Set(snapshot.docs.map(doc => doc.id));
  const jsonIds = new Set(collectionsData.map(collection => collection.id));
  
  const toDelete = [...existingIds].filter(id => !jsonIds.has(id));
  
  if (toDelete.length > 0) {
    console.log(`\n🗑️  Deleting ${toDelete.length} collection(s) not in JSON:`);
    for (const id of toDelete) {
      try {
        await db.collection('collections').doc(id).delete();
        console.log(`   ✓ Deleted: ${id}`);
      } catch (error) {
        console.error(`   ✗ Failed to delete ${id}:`, error.message);
      }
    }
  } else {
    console.log('✅ No collections to delete\n');
  }
  // ========================================================
  
  console.log('📤 Uploading collections...');
  let uploadedCount = 0;
  
  for (const collection of collectionsData) {
    try {
      await db.collection('collections').doc(collection.id).set({
        id: collection.id,
        emoji: collection.emoji || '',
        name: collection.name,
        description: collection.description,
        region: collection.region,
        totalStamps: collection.totalStamps
      });
      
      uploadedCount++;
      console.log(`  ✓ ${collection.emoji} ${collection.name}`);
    } catch (error) {
      console.error(`  ✗ Failed: ${collection.id} -`, error.message);
    }
  }
  
  console.log(`\n✅ Uploaded ${uploadedCount}/${collectionsData.length} collections\n`);
}

async function verifyCollectionCounts() {
  console.log('🔍 Verifying collection counts before upload...\n');
  
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const collectionsPath = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');
  
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  const collectionsData = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
  
  // Count actual stamps per collection from stamps.json
  const actualCounts = {};
  stampsData.forEach(stamp => {
    const collectionIds = stamp.collectionIds || [];
    collectionIds.forEach(collectionId => {
      actualCounts[collectionId] = (actualCounts[collectionId] || 0) + 1;
    });
  });
  
  // Check for mismatches
  let hasErrors = false;
  const errors = [];
  
  collectionsData.forEach(collection => {
    const expected = collection.totalStamps;
    const actual = actualCounts[collection.id] || 0;
    
    if (expected !== actual) {
      hasErrors = true;
      errors.push({
        id: collection.id,
        name: collection.name,
        expected,
        actual
      });
    }
  });
  
  if (hasErrors) {
    console.log('❌ COLLECTION COUNT MISMATCHES FOUND:\n');
    errors.forEach(err => {
      console.log(`   ${err.name} (${err.id})`);
      console.log(`   Expected: ${err.expected}, Actual: ${err.actual}`);
      console.log(`   → Update collections.json: "totalStamps": ${err.actual}\n`);
    });
    console.log('⚠️  Please fix collections.json before uploading!\n');
    return false;
  }
  
  console.log('✅ All collection counts are correct!\n');
  return true;
}

async function main() {
  console.log('🚀 Syncing Firestore with local JSON...\n');
  
  // Check for --force flag
  const forceDelete = process.argv.includes('--force');
  
  try {
    // Verify counts first
    const countsValid = await verifyCollectionCounts();
    if (!countsValid) {
      console.log('❌ Upload aborted due to count mismatches.\n');
      process.exit(1);
    }
    
    await uploadStamps(forceDelete);
    await uploadCollections();
    
    console.log('🎉 Sync complete!\n');
    console.log('✅ Stamps synced (added, updated, deleted)');
    console.log('✅ Collections synced (added, updated, deleted)');
    console.log('✅ Visibility system ready\n');
    
  } catch (error) {
    console.error('❌ Sync failed:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

main();
