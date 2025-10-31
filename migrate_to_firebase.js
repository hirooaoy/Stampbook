#!/usr/bin/env node

/**
 * Migration Script: Upload stamps.json and collections.json to Firebase Firestore
 * 
 * Prerequisites:
 * 1. Install Firebase Admin SDK: npm install firebase-admin
 * 2. Download your Firebase service account key from:
 *    Firebase Console → Project Settings → Service Accounts → Generate New Private Key
 * 3. Save it as 'serviceAccountKey.json' in this directory
 * 
 * Usage:
 *   node migrate_to_firebase.js
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
  
  console.log('🚀 Uploading stamps to Firestore...');
  const batch = db.batch();
  
  for (const stamp of stampsData) {
    const docRef = db.collection('stamps').doc(stamp.id);
    batch.set(docRef, stamp);
    console.log(`  ✓ ${stamp.name} (${stamp.id})`);
  }
  
  await batch.commit();
  console.log(`\n✅ Successfully uploaded ${stampsData.length} stamps to Firestore\n`);
}

async function uploadCollections() {
  console.log('📚 Reading collections.json...');
  const collectionsPath = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');
  const collectionsData = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
  
  console.log(`✅ Found ${collectionsData.length} collections\n`);
  
  console.log('🚀 Uploading collections to Firestore...');
  const batch = db.batch();
  
  for (const collection of collectionsData) {
    const docRef = db.collection('collections').doc(collection.id);
    batch.set(docRef, collection);
    console.log(`  ✓ ${collection.name} (${collection.id})`);
  }
  
  await batch.commit();
  console.log(`\n✅ Successfully uploaded ${collectionsData.length} collections to Firestore\n`);
}

async function initializeStampStatistics() {
  console.log('📊 Initializing stamp statistics...');
  
  // Get all stamps
  const stampsSnapshot = await db.collection('stamps').get();
  
  console.log(`✅ Found ${stampsSnapshot.docs.length} stamps\n`);
  
  console.log('🚀 Creating initial statistics documents...');
  const batch = db.batch();
  
  for (const stampDoc of stampsSnapshot.docs) {
    const statsRef = db.collection('stamp_statistics').doc(stampDoc.id);
    batch.set(statsRef, {
      stampId: stampDoc.id,
      totalCollectors: 0,
      collectorUserIds: [],
      lastUpdated: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log(`  ✓ Initialized stats for ${stampDoc.id}`);
  }
  
  await batch.commit();
  console.log(`\n✅ Successfully initialized statistics for ${stampsSnapshot.docs.length} stamps\n`);
}

async function main() {
  console.log('╔════════════════════════════════════════════════╗');
  console.log('║  Stampbook Firebase Migration Script          ║');
  console.log('╚════════════════════════════════════════════════╝\n');
  
  try {
    await uploadStamps();
    await uploadCollections();
    await initializeStampStatistics();
    
    console.log('╔════════════════════════════════════════════════╗');
    console.log('║  ✅ Migration Complete!                        ║');
    console.log('╚════════════════════════════════════════════════╝\n');
    
    console.log('Next steps:');
    console.log('1. Verify data in Firebase Console');
    console.log('2. Update Firestore Security Rules (see firestore.rules)');
    console.log('3. Deploy rules: firebase deploy --only firestore:rules');
    console.log('4. Test the app to confirm stamps load from Firebase\n');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    process.exit(1);
  }
}

main();

