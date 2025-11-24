#!/usr/bin/env node

/**
 * Upload Collections to Firestore
 * 
 * This script uploads all collections from collections.json to Firestore
 * 
 * Run: node upload_collections_to_firestore.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function uploadCollections() {
  try {
    console.log('📤 Uploading collections to Firestore...\n');
    
    // Read collections.json
    const collectionsPath = path.join(__dirname, 'Stampbook/Data/collections.json');
    const localCollections = JSON.parse(fs.readFileSync(collectionsPath, 'utf8'));
    console.log(`✅ Found ${localCollections.length} collections in local JSON\n`);
    
    // Get Firebase collections for comparison
    const firebaseSnapshot = await db.collection('collections').get();
    const firebaseCollections = [];
    firebaseSnapshot.forEach(doc => {
      firebaseCollections.push(doc.data());
    });
    
    console.log(`✅ Found ${firebaseCollections.length} collections in Firebase\n`);
    
    // Upload each collection
    const batch = db.batch();
    let updateCount = 0;
    
    for (const collection of localCollections) {
      const collectionRef = db.collection('collections').doc(collection.id);
      batch.set(collectionRef, collection, { merge: true });
      updateCount++;
    }
    
    // Commit the batch
    await batch.commit();
    
    console.log(`✅ Successfully uploaded ${updateCount} collections to Firestore`);
    console.log('🎉 Local collections.json is now synced with Firebase\n');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error uploading collections:', error);
    process.exit(1);
  }
}

uploadCollections();

