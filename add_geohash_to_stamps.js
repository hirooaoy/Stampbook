#!/usr/bin/env node

/**
 * Add Geohash Field to Existing Stamps in Firestore
 * 
 * This script updates all stamps in Firestore to include a geohash field.
 * Geohash enables efficient geographic queries for map views.
 * 
 * Run: node add_geohash_to_stamps.js
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Encode coordinates to geohash string
 * @param {number} latitude 
 * @param {number} longitude 
 * @param {number} precision 
 * @returns {string} geohash
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
      // Longitude
      const mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude > mid) {
        bit |= (1 << (4 - bits));
        lonRange[0] = mid;
      } else {
        lonRange[1] = mid;
      }
    } else {
      // Latitude
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

async function addGeohashToStamps() {
  try {
    console.log('🚀 Starting geohash migration...\n');
    
    // Fetch all stamps
    const stampsSnapshot = await db.collection('stamps').get();
    
    if (stampsSnapshot.empty) {
      console.log('⚠️  No stamps found in Firestore');
      return;
    }
    
    console.log(`📍 Found ${stampsSnapshot.size} stamps to update\n`);
    
    let updated = 0;
    let skipped = 0;
    let errors = 0;
    
    // Update in batch (Firestore batches support max 500 operations)
    const batchSize = 500;
    let batch = db.batch();
    let operationsInBatch = 0;
    
    for (const doc of stampsSnapshot.docs) {
      const stamp = doc.data();
      
      // Check if geohash already exists
      if (stamp.geohash) {
        console.log(`⏭️  Skipping ${stamp.id} - already has geohash: ${stamp.geohash}`);
        skipped++;
        continue;
      }
      
      // Validate coordinates
      if (typeof stamp.latitude !== 'number' || typeof stamp.longitude !== 'number') {
        console.log(`❌ Error: ${stamp.id} - invalid coordinates (lat: ${stamp.latitude}, lng: ${stamp.longitude})`);
        errors++;
        continue;
      }
      
      // Generate geohash
      const geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
      
      // Add to batch
      batch.update(doc.ref, { geohash });
      operationsInBatch++;
      updated++;
      
      console.log(`✅ ${stamp.id}`);
      console.log(`   Coordinates: ${stamp.latitude.toFixed(6)}, ${stamp.longitude.toFixed(6)}`);
      console.log(`   Geohash: ${geohash}\n`);
      
      // Commit batch if it reaches 500 operations
      if (operationsInBatch >= batchSize) {
        await batch.commit();
        console.log(`💾 Committed batch of ${operationsInBatch} updates\n`);
        batch = db.batch();
        operationsInBatch = 0;
      }
    }
    
    // Commit remaining operations
    if (operationsInBatch > 0) {
      await batch.commit();
      console.log(`💾 Committed final batch of ${operationsInBatch} updates\n`);
    }
    
    // Summary
    console.log('═'.repeat(50));
    console.log('📊 MIGRATION SUMMARY');
    console.log('═'.repeat(50));
    console.log(`✅ Updated:  ${updated} stamps`);
    console.log(`⏭️  Skipped:  ${skipped} stamps (already had geohash)`);
    console.log(`❌ Errors:   ${errors} stamps`);
    console.log(`📍 Total:    ${stampsSnapshot.size} stamps`);
    console.log('═'.repeat(50));
    
    if (updated > 0) {
      console.log('\n🎉 Migration complete! Your stamps now support efficient geographic queries.');
      console.log('\n💡 Next steps:');
      console.log('   1. Create a composite index in Firestore:');
      console.log('      Collection: stamps');
      console.log('      Fields: geohash (Ascending), __name__ (Ascending)');
      console.log('   2. Or run the app and Firestore will prompt you with a link');
    }
    
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

// Run the migration
addGeohashToStamps()
  .then(() => {
    console.log('\n✅ Script completed successfully');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Script failed:', error);
    process.exit(1);
  });

