#!/usr/bin/env node

/**
 * Check watagumostudio's follower data
 * Examines followerCount field vs actual followers subcollection
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function checkWatagumoFollowers() {
  try {
    console.log('\n🔍 Checking watagumostudio follower data...\n');
    
    // Find watagumostudio user
    const usersSnapshot = await db.collection('users').get();
    let watagumoUserId = null;
    let watagumoData = null;
    
    usersSnapshot.forEach(doc => {
      const userData = doc.data();
      if (userData.username === 'watagumostudio') {
        watagumoUserId = doc.id;
        watagumoData = userData;
      }
    });
    
    if (!watagumoUserId) {
      console.log('❌ watagumostudio user not found');
      return;
    }
    
    console.log('✅ Found watagumostudio account');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`User ID:       ${watagumoUserId}`);
    console.log(`Username:      @${watagumoData.username}`);
    console.log(`Display Name:  ${watagumoData.displayName}`);
    console.log(`Follower Count (field): ${watagumoData.followerCount}`);
    console.log(`Following Count: ${watagumoData.followingCount}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Check followers subcollection
    console.log('📋 Checking followers subcollection...');
    const followersSnapshot = await db.collection('users').doc(watagumoUserId).collection('followers').get();
    
    console.log(`   Actual followers in subcollection: ${followersSnapshot.size}\n`);
    
    if (followersSnapshot.empty) {
      console.log('   ❌ No followers in subcollection\n');
    } else {
      console.log('   Followers:');
      for (const doc of followersSnapshot.docs) {
        const followerData = doc.data();
        console.log(`   - ${doc.id}`);
        console.log(`     Followed at: ${followerData.followedAt?.toDate?.() || 'N/A'}`);
        
        // Get the follower's username
        const followerDoc = await db.collection('users').doc(doc.id).get();
        if (followerDoc.exists) {
          const followerUser = followerDoc.data();
          console.log(`     Username: @${followerUser.username} (${followerUser.displayName})`);
        } else {
          console.log(`     ⚠️ WARNING: User document doesn't exist!`);
        }
        console.log('');
      }
    }
    
    // Check if there's a mismatch
    if (watagumoData.followerCount !== followersSnapshot.size) {
      console.log('⚠️  MISMATCH DETECTED!');
      console.log(`    followerCount field: ${watagumoData.followerCount}`);
      console.log(`    Actual followers: ${followersSnapshot.size}`);
      console.log(`    Difference: ${watagumoData.followerCount - followersSnapshot.size}\n`);
    } else {
      console.log('✅ followerCount matches actual followers\n');
    }
    
    // Check following subcollection
    console.log('📋 Checking following subcollection...');
    const followingSnapshot = await db.collection('users').doc(watagumoUserId).collection('following').get();
    console.log(`   Actual following in subcollection: ${followingSnapshot.size}\n`);
    
    if (!followingSnapshot.empty) {
      console.log('   Following:');
      for (const doc of followingSnapshot.docs) {
        const followingData = doc.data();
        console.log(`   - ${doc.id}`);
        console.log(`     Followed at: ${followingData.followedAt?.toDate?.() || 'N/A'}`);
        
        // Get the user's username
        const userDoc = await db.collection('users').doc(doc.id).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          console.log(`     Username: @${userData.username} (${userData.displayName})`);
        }
        console.log('');
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

checkWatagumoFollowers()
  .then(() => {
    console.log('✅ Check complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

