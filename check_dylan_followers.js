#!/usr/bin/env node

/**
 * Check Dylan's Follower Data
 * Detailed investigation of Dylan's follower count issue
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function checkDylanFollowers() {
  try {
    console.log('\n🔍 Checking Dylan\'s follower data...\n');
    
    // Find Dylan
    const usersSnapshot = await db.collection('users').get();
    let dylanUserId = null;
    let dylanData = null;
    
    usersSnapshot.forEach(doc => {
      const userData = doc.data();
      if (userData.username === 'dylan') {
        dylanUserId = doc.id;
        dylanData = userData;
      }
    });
    
    if (!dylanUserId) {
      console.log('❌ Dylan not found');
      return;
    }
    
    console.log('✅ Found Dylan\'s account');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`User ID:       ${dylanUserId}`);
    console.log(`Username:      @${dylanData.username}`);
    console.log(`Display Name:  ${dylanData.displayName}`);
    console.log(`Follower Count (field): ${dylanData.followerCount}`);
    console.log(`Following Count: ${dylanData.followingCount}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Check followers subcollection
    console.log('📋 Checking followers subcollection...');
    const followersSnapshot = await db.collection('users').doc(dylanUserId).collection('followers').get();
    
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
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('DIAGNOSIS');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    if (dylanData.followerCount !== followersSnapshot.size) {
      console.log(`❌ MISMATCH DETECTED!`);
      console.log(`   followerCount field: ${dylanData.followerCount}`);
      console.log(`   Actual followers: ${followersSnapshot.size}`);
      console.log(`   Difference: ${Math.abs(dylanData.followerCount - followersSnapshot.size)}`);
      console.log(`   \n   The followerCount field needs to be updated to ${followersSnapshot.size}\n`);
    } else {
      console.log('✅ followerCount matches actual followers\n');
    }
    
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

