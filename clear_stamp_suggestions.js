#!/usr/bin/env node

/**
 * Clear all stamp suggestions from Firestore
 * Run this to clean up test data after schema change
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function clearStampSuggestions() {
  try {
    console.log('🔍 Checking for stamp suggestions...');
    
    const suggestionsRef = db.collection('stamp_suggestions');
    const snapshot = await suggestionsRef.get();
    
    if (snapshot.empty) {
      console.log('✅ No stamp suggestions found. Nothing to clear.');
      process.exit(0);
    }
    
    console.log(`📝 Found ${snapshot.size} stamp suggestions`);
    console.log('🗑️  Deleting all suggestions...');
    
    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    
    console.log('✅ All stamp suggestions have been cleared!');
    console.log(`   Deleted ${snapshot.size} documents`);
    
  } catch (error) {
    console.error('❌ Error clearing suggestions:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

clearStampSuggestions();

