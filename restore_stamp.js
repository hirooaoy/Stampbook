#!/usr/bin/env node

/**
 * Restore a removed stamp
 * 
 * Changes a stamp's status back to "active" after removal.
 * Use if stamp was removed by mistake or after appeal review.
 * 
 * Usage: node restore_stamp.js <stamp-id>
 * Example: node restore_stamp.js us-ca-sf-good-stamp
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function restoreStamp(stampId) {
  console.log(`♻️  Restoring stamp: ${stampId}\n`);
  
  try {
    const docRef = db.collection('stamps').doc(stampId);
    const doc = await docRef.get();
    
    if (!doc.exists) {
      console.error(`❌ Error: Stamp "${stampId}" not found`);
      process.exit(1);
    }
    
    const stampData = doc.data();
    console.log(`📍 Found: ${stampData.name}`);
    console.log(`   Current status: ${stampData.status || 'active'}\n`);
    
    if (stampData.status !== 'removed' && stampData.status !== 'hidden') {
      console.log('⚠️  Warning: Stamp is not removed/hidden');
      console.log('   Continuing anyway...\n');
    }
    
    // Restore to active
    await docRef.update({
      status: 'active',
      restoredAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Successfully restored stamp');
    console.log('   - Status: active');
    console.log('   - Visible to all users again\n');
    
  } catch (error) {
    console.error('❌ Error restoring stamp:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

const stampId = process.argv[2];

if (!stampId) {
  console.error('❌ Usage: node restore_stamp.js <stamp-id>');
  console.error('   Example: node restore_stamp.js us-ca-sf-good-stamp');
  process.exit(1);
}

restoreStamp(stampId);

