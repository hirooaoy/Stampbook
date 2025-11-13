#!/usr/bin/env node

/**
 * Check what photo data is in the local app after Firestore sync
 * This simulates what the app should have in UserDefaults after syncing
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function checkPhotos() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
  
  console.log('\n📋 Checking what photos should be in local app after Firestore sync\n');
  
  // This simulates what syncFromFirestore() fetches
  const firestoreStamps = await db.collection('users')
    .doc(userId)
    .collection('collectedStamps')
    .get();
  
  console.log(`Found ${firestoreStamps.size} stamps in Firestore:\n`);
  
  firestoreStamps.forEach(doc => {
    const data = doc.data();
    console.log(`📌 ${doc.id}`);
    console.log(`   userImageNames: ${JSON.stringify(data.userImageNames || [])}`);
    console.log(`   userImagePaths: ${JSON.stringify(data.userImagePaths || [])}`);
    
    if ((data.userImagePaths || []).length > 0) {
      console.log(`   ✅ HAS PHOTOS (${data.userImagePaths.length})`);
    } else {
      console.log(`   ⚠️  NO PHOTOS`);
    }
    console.log('');
  });
  
  process.exit(0);
}

checkPhotos().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});

