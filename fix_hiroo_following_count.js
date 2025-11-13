#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixHirooFollowingCount() {
  try {
    const hirooId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    console.log('\n🔧 Fixing Hiroo\'s following count...\n');
    
    // Get actual count from subcollection
    const followingRef = db.collection('users').doc(hirooId).collection('following');
    const following = await followingRef.get();
    const actualCount = following.size;
    
    console.log(`Actual following (from subcollection): ${actualCount}`);
    
    // Get current count from profile
    const userDoc = await db.collection('users').doc(hirooId).get();
    const currentCount = userDoc.data().followingCount;
    
    console.log(`Current followingCount (from profile): ${currentCount}`);
    
    if (actualCount === currentCount) {
      console.log('\n✅ Counts already match! No fix needed.\n');
    } else {
      console.log(`\n⚠️  Mismatch detected! Updating to ${actualCount}...\n`);
      
      await db.collection('users').doc(hirooId).update({
        followingCount: actualCount
      });
      
      console.log('✅ Fixed! followingCount is now correct.\n');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

fixHirooFollowingCount()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });

