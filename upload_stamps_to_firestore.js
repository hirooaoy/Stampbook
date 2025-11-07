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

async function uploadStamps() {
  console.log('📚 Reading stamps.json...');
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  
  console.log(`✅ Found ${stampsData.length} stamps in JSON\n`);
  
  // ==================== SYNC DELETIONS ====================
  console.log('🔍 Checking for deletions...');
  const snapshot = await db.collection('stamps').get();
  const existingIds = new Set(snapshot.docs.map(doc => doc.id));
  const jsonIds = new Set(stampsData.map(stamp => stamp.id));
  
  const toDelete = [...existingIds].filter(id => !jsonIds.has(id));
  
  if (toDelete.length > 0) {
    console.log(`\n🗑️  Deleting ${toDelete.length} stamp(s) not in JSON:`);
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
        notesFromOthers: stamp.notesFromOthers || [],
        thingsToDoFromEditors: stamp.thingsToDoFromEditors || [],
        geohash: geohash
      };
      
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
  if (toDelete.length > 0) {
    console.log(`🗑️  Deleted ${toDelete.length} stamps\n`);
  }
}

async function uploadCollections() {
  console.log('📚 Reading collections.json...');
  const collectionsPath = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');
  const collectionsData = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
  
  console.log(`✅ Found ${collectionsData.length} collections\n`);
  
  console.log('📤 Uploading collections...');
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
      console.log(`  ✓ ${collection.name}`);
    } catch (error) {
      console.error(`  ✗ Failed: ${collection.id} -`, error.message);
    }
  }
  
  console.log(`\n✅ Uploaded ${uploadedCount}/${collectionsData.length} collections\n`);
}

async function main() {
  console.log('🚀 Syncing Firestore with local JSON...\n');
  
  try {
    await uploadStamps();
    await uploadCollections();
    
    console.log('🎉 Sync complete!\n');
    console.log('✅ Stamps synced (added, updated, deleted)');
    console.log('✅ Collections synced');
    console.log('✅ Visibility system ready\n');
    
  } catch (error) {
    console.error('❌ Sync failed:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

main();
