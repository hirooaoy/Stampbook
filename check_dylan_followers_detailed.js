#!/usr/bin/env node

/**
 * Check Who is Following Dylan
 * Find all users following Dylan and diagnose the bidirectional relationship
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function checkDylanFollowers() {
  try {
    const dylanId = 'bT76nSxOaQOLT8sgJmB7TeLuFcQ2';
    
    console.log('\n🔍 Finding everyone who is following Dylan...\n');
    console.log('Method 1: Query collection group (who has Dylan in their following list)');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Use collection group query to find all users who have Dylan in their following subcollection
    const followingSnapshot = await db
      .collectionGroup('following')
      .where('id', '==', dylanId)
      .get();
      
    console.log(`Found ${followingSnapshot.size} users following Dylan via collection group query:\n`);
    
    for (const doc of followingSnapshot.docs) {
      // Extract follower ID from path: users/{followerId}/following/{followeeId}
      const pathComponents = doc.ref.path.split('/');
      const followerId = pathComponents[1];
      
      const userDoc = await db.collection('users').doc(followerId).get();
      const userData = userDoc.data();
      
      console.log(`  ✅ @${userData.username} (${userData.displayName})`);
      console.log(`     User ID: ${followerId}`);
      console.log(`     Followed at: ${doc.data().createdAt?.toDate() || 'N/A'}`);
      console.log('');
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('Method 2: Check Dylan\'s followers subcollection directly');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    const dylanFollowersSnapshot = await db.collection('users').doc(dylanId).collection('followers').get();
    console.log(`Dylan's followers subcollection: ${dylanFollowersSnapshot.size} documents\n`);
    
    if (dylanFollowersSnapshot.empty) {
      console.log('❌ EMPTY - This is the problem!\n');
    } else {
      for (const doc of dylanFollowersSnapshot.docs) {
        console.log(`  - ${doc.id}`);
      }
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('DIAGNOSIS');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    if (followingSnapshot.size > 0 && dylanFollowersSnapshot.size === 0) {
      console.log('❌ BIDIRECTIONAL RELATIONSHIP BROKEN!');
      console.log(`   ${followingSnapshot.size} user(s) have Dylan in their following list`);
      console.log('   BUT Dylan has 0 documents in his followers subcollection');
      console.log('');
      console.log('   ROOT CAUSE:');
      console.log('   The iOS followUser() function only writes to the follower\'s');
      console.log('   \'following\' subcollection, but does NOT write to the followee\'s');
      console.log('   \'followers\' subcollection. This creates a one-way relationship.');
      console.log('');
      console.log('   IMPACT:');
      console.log('   - fetchFollowers() uses collection group query, so it WORKS');
      console.log('   - But followerCount field doesn\'t update (Cloud Function needs both sides)');
      console.log('   - Direct queries to followers subcollection show 0');
    }
    
    console.log('');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

checkDylanFollowers()
  .then(() => {
    console.log('✅ Check complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

