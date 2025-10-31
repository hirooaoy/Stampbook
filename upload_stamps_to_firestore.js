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

async function uploadStamps() {
  console.log('📚 Reading stamps.json...');
  const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
  const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
  
  console.log(`✅ Found ${stampsData.length} stamps\n`);
  
  console.log('📤 Uploading stamps to Firestore...');
  let uploadedCount = 0;
  
  for (const stamp of stampsData) {
    try {
      await db.collection('stamps').doc(stamp.id).set({
        id: stamp.id,
        name: stamp.name,
        latitude: stamp.latitude,
        longitude: stamp.longitude,
        address: stamp.address,
        imageName: stamp.imageName,
        collectionIds: stamp.collectionIds,
        about: stamp.about,
        notesFromOthers: stamp.notesFromOthers || [],
        thingsToDoFromEditors: stamp.thingsToDoFromEditors || []
      });
      
      uploadedCount++;
      console.log(`  ✓ Uploaded: ${stamp.name} (${stamp.id})`);
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
    console.log('💡 To add new stamps in the future:');
    console.log('   1. Add to stamps.json locally');
    console.log('   2. Run this script again');
    console.log('   OR add directly via Firebase Console\n');
    
  } catch (error) {
    console.error('❌ Upload failed:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

main();

