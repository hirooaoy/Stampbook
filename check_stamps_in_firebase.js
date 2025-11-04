#!/usr/bin/env node

/**
 * Check what stamps are in Firebase and diagnose map issues
 * 
 * This script will:
 * 1. Count total stamps in Firestore
 * 2. Check if stamps have geohash fields (required for map)
 * 3. Show sample stamps with their locations
 * 4. Identify missing geohashes
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkStamps() {
  console.log('🔍 Checking Firebase stamps...\n');
  
  try {
    // Fetch all stamps
    const stampsSnapshot = await db.collection('stamps').get();
    const totalStamps = stampsSnapshot.size;
    
    console.log(`📊 Total stamps in Firebase: ${totalStamps}\n`);
    
    if (totalStamps === 0) {
      console.log('❌ NO STAMPS FOUND IN FIREBASE!');
      console.log('   This is why your map is empty.\n');
      console.log('💡 Solution: Run "node upload_stamps_to_firestore.js" to upload from JSON\n');
      return;
    }
    
    // Check for geohash fields
    let stampsWithGeohash = 0;
    let stampsWithoutGeohash = [];
    let sampleStamps = [];
    
    stampsSnapshot.forEach(doc => {
      const stamp = doc.data();
      
      if (stamp.geohash) {
        stampsWithGeohash++;
      } else {
        stampsWithoutGeohash.push({
          id: stamp.id,
          name: stamp.name,
          lat: stamp.latitude,
          lon: stamp.longitude
        });
      }
      
      // Collect first 5 samples
      if (sampleStamps.length < 5) {
        sampleStamps.push({
          id: stamp.id,
          name: stamp.name,
          lat: stamp.latitude,
          lon: stamp.longitude,
          geohash: stamp.geohash || 'MISSING'
        });
      }
    });
    
    console.log('📍 Sample stamps:');
    sampleStamps.forEach(s => {
      console.log(`   • ${s.name} (${s.id})`);
      console.log(`     Location: ${s.lat}, ${s.lon}`);
      console.log(`     Geohash: ${s.geohash}`);
    });
    console.log('');
    
    // Report geohash status
    console.log('🗺️  Geohash Status (required for map):');
    console.log(`   ✅ With geohash: ${stampsWithGeohash}`);
    console.log(`   ❌ Missing geohash: ${stampsWithoutGeohash.length}\n`);
    
    if (stampsWithoutGeohash.length > 0) {
      console.log('⚠️  PROBLEM FOUND: Stamps missing geohash fields!');
      console.log('   The map uses geohash for spatial queries.');
      console.log('   Stamps without geohash won\'t appear on the map.\n');
      console.log('   Missing geohash for:');
      stampsWithoutGeohash.slice(0, 10).forEach(s => {
        console.log(`   • ${s.name} (${s.id})`);
      });
      if (stampsWithoutGeohash.length > 10) {
        console.log(`   ... and ${stampsWithoutGeohash.length - 10} more\n`);
      } else {
        console.log('');
      }
      console.log('💡 Solution: Run "node add_geohash_to_stamps.js" to add geohashes\n');
    } else {
      console.log('✅ All stamps have geohash fields - map should work!\n');
      console.log('🤔 If map is still empty, check:');
      console.log('   1. Are you signed in on TestFlight?');
      console.log('   2. Is TestFlight using the correct Firebase project?');
      console.log('   3. Check Firebase Console → Firestore → stamps collection\n');
    }
    
  } catch (error) {
    console.error('❌ Error checking stamps:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

checkStamps();

