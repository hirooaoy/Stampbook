#!/usr/bin/env node

/**
 * Fix All Follower Counts
 * 
 * Reconciles followerCount and followingCount fields with actual subcollection data
 * for all users in the database.
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function fixAllFollowerCounts() {
  try {
    console.log('\n🔧 Fixing follower counts for all users...\n');
    
    const usersSnapshot = await db.collection('users').get();
    let fixedCount = 0;
    let alreadyCorrectCount = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      // Get actual follower count
      const followersSnapshot = await db.collection('users').doc(userId).collection('followers').get();
      const actualFollowers = followersSnapshot.size;
      
      // Get actual following count
      const followingSnapshot = await db.collection('users').doc(userId).collection('following').get();
      const actualFollowing = followingSnapshot.size;
      
      // Check for mismatches
      const followerMismatch = userData.followerCount !== actualFollowers;
      const followingMismatch = userData.followingCount !== actualFollowing;
      
      if (followerMismatch || followingMismatch) {
        console.log(`🔧 Fixing @${userData.username} (${userId})`);
        console.log(`   Before: followers=${userData.followerCount}, following=${userData.followingCount}`);
        console.log(`   After:  followers=${actualFollowers}, following=${actualFollowing}`);
        
        // Update the fields
        await db.collection('users').doc(userId).update({
          followerCount: actualFollowers,
          followingCount: actualFollowing
        });
        
        console.log(`   ✅ Updated\n`);
        fixedCount++;
      } else {
        console.log(`✅ @${userData.username} already correct (followers=${actualFollowers}, following=${actualFollowing})`);
        alreadyCorrectCount++;
      }
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('SUMMARY');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`✅ Fixed: ${fixedCount} users`);
    console.log(`✅ Already correct: ${alreadyCorrectCount} users`);
    console.log(`📊 Total users: ${usersSnapshot.size}`);
    console.log('');
    console.log('⚠️  IMPORTANT: Users still need to refresh their app to clear cached data');
    console.log('   Tell users to:');
    console.log('   1. Force quit the app');
    console.log('   2. Re-open the app');
    console.log('   OR sign out and sign back in');
    console.log('');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

fixAllFollowerCounts()
  .then(() => {
    console.log('✅ Fix complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

