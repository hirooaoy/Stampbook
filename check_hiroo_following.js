#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooFollowing() {
  try {
    const hirooId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    console.log('\n🔍 Checking who Hiroo is following...\n');
    
    const followingRef = db.collection('users').doc(hirooId).collection('following');
    const following = await followingRef.get();
    
    if (following.empty) {
      console.log('✅ Hiroo is not following anyone (subcollection is empty)');
      console.log('⚠️  But followingCount is 1 - this is a data inconsistency!\n');
    } else {
      console.log(`Found ${following.size} following relationship(s):\n`);
      
      for (const doc of following.docs) {
        const data = doc.data();
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
        console.log(`Following User ID: ${doc.id}`);
        console.log(`Data:`, data);
        
        // Check if that user still exists
        const userDoc = await db.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          console.log(`✅ User exists: @${userDoc.data().username}`);
        } else {
          console.log(`❌ User DOES NOT EXIST (orphaned relationship!)`);
        }
        console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

checkHirooFollowing()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });

