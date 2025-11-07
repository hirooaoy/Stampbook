#!/usr/bin/env node

/**
 * Remove a stamp (soft delete for moderation)
 * 
 * Marks a stamp as "removed" without deleting it from Firebase:
 * - Stamp becomes invisible to all users immediately
 * - Users who collected it keep it (fair!)
 * - Data preserved for audit trail
 * 
 * Usage: node remove_stamp.js <stamp-id> "<reason>"
 * Example: node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function removeStamp(stampId, reason) {
  console.log(`🗑️  Removing stamp: ${stampId}\n`);
  console.log(`📝 Reason: ${reason}\n`);
  
  try {
    // Check if stamp exists
    const docRef = db.collection('stamps').doc(stampId);
    const doc = await docRef.get();
    
    if (!doc.exists) {
      console.error(`❌ Error: Stamp "${stampId}" not found in Firebase`);
      process.exit(1);
    }
    
    const stampData = doc.data();
    console.log(`📍 Found: ${stampData.name}`);
    console.log(`   Location: ${stampData.address}\n`);
    
    // Update stamp to mark as removed (SOFT DELETE)
    await docRef.update({
      status: 'removed',
      removalReason: reason,
      removedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Successfully removed stamp');
    console.log('   - Status: removed');
    console.log('   - Stamp invisible to all users now');
    console.log('   - Users who collected it keep it');
    console.log('   - Data preserved for audit\n');
    
    // Count collectors
    const collectedSnapshot = await db.collection('collected_stamps')
      .where('stampId', '==', stampId)
      .get();
    
    if (collectedSnapshot.size > 0) {
      console.log(`ℹ️  ${collectedSnapshot.size} user(s) have collected this stamp and will keep it\n`);
    }
    
  } catch (error) {
    console.error('❌ Error removing stamp:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

// Parse command line arguments
const stampId = process.argv[2];
const reason = process.argv[3];

if (!stampId || !reason) {
  console.error('❌ Usage: node remove_stamp.js <stamp-id> "<reason>"');
  console.error('   Example: node remove_stamp.js us-ca-sf-bad-stamp "User reported inappropriate content"');
  process.exit(1);
}

removeStamp(stampId, reason);

