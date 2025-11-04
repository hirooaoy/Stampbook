#!/usr/bin/env node

/**
 * Upload stamps.json and collections.json to Firestore
 * 
 * This script reads the local JSON files and uploads them to Firebase.
 * Run once to populate Firestore, then you can add/update stamps via Firebase Console.
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

async function uploadStamps() {
  console.log('📚 Reading stamps.json...');
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  
  console.log(`✅ Found ${stampsData.length} stamps\n`);
  
  console.log('📤 Uploading stamps to Firestore (with auto-generated geohashes)...');
  let uploadedCount = 0;
  
  for (const stamp of stampsData) {
    try {
      // Auto-generate geohash from coordinates
      const geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
      
      await db.collection('stamps').doc(stamp.id).set({
        id: stamp.id,
        name: stamp.name,
        latitude: stamp.latitude,
        longitude: stamp.longitude,
        address: stamp.address,
        imageUrl: stamp.imageUrl || '',  // Changed from imageName to imageUrl
        collectionIds: stamp.collectionIds,
        about: stamp.about,
        notesFromOthers: stamp.notesFromOthers || [],
        thingsToDoFromEditors: stamp.thingsToDoFromEditors || [],
        geohash: geohash  // Auto-generated for map queries
      });
      
      uploadedCount++;
      console.log(`  ✓ Uploaded: ${stamp.name} (${stamp.id})`);
      console.log(`    Geohash: ${geohash}`);
    } catch (error) {
      console.error(`  ✗ Failed to upload ${stamp.id}:`, error.message);
    }
  }
  
  console.log(`\n✅ Successfully uploaded ${uploadedCount}/${stampsData.length} stamps\n`);
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
  console.log('🚀 Starting Firestore upload...\n');
  
  try {
    await uploadStamps();
    await uploadCollections();
    
    console.log('🎉 Upload complete! Your app will now load stamps from Firestore.\n');
    console.log('✅ Geohashes automatically generated for all stamps!\n');
    console.log('💡 To add new stamps in the future:');
    console.log('   1. Add to stamps.json locally');
    console.log('   2. Run this script again (geohashes will be auto-generated)');
    console.log('   OR add directly via Firebase Console (and run add_geohash_to_stamps.js)\n');
    
  } catch (error) {
    console.error('❌ Upload failed:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

main();

