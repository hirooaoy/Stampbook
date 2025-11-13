const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooFollowers() {
  try {
    console.log('🔍 Checking hiroo follower data...\n');
    
    // Step 1: Find hiroo's userId
    const usersSnapshot = await db.collection('users').get();
    let hirooUserId = null;
    let hirooProfile = null;
    
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      if (data.username === 'hiroo') {
        hirooUserId = doc.id;
        hirooProfile = data;
        break;
      }
    }
    
    if (!hirooUserId) {
      console.log('❌ hiroo user not found');
      return;
    }
    
    console.log('✅ Found hiroo:');
    console.log(`   userId: ${hirooUserId}`);
    console.log(`   Profile followerCount: ${hirooProfile.followerCount || 0}`);
    console.log(`   Profile followingCount: ${hirooProfile.followingCount || 0}\n`);
    
    // Step 2: Check actual follower documents (people following hiroo)
    console.log('📊 Checking follower documents (users/*/following where following hiroo):');
    let actualFollowerCount = 0;
    const followersList = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const followingSnapshot = await db.collection('users')
        .doc(userId)
        .collection('following')
        .doc(hirooUserId)
        .get();
      
      if (followingSnapshot.exists) {
        actualFollowerCount++;
        followersList.push({
          userId: userId,
          username: userDoc.data().username,
          followedAt: followingSnapshot.data()?.followedAt?.toDate()
        });
      }
    }
    
    console.log(`   Actual follower count: ${actualFollowerCount}`);
    if (followersList.length > 0) {
      console.log('   Followers:');
      followersList.forEach(f => {
        console.log(`     - ${f.username} (${f.userId}) followed at ${f.followedAt || 'unknown'}`);
      });
    } else {
      console.log('   No followers found');
    }
    console.log('');
    
    // Step 3: Check follower subcollection (users/hiroo/followers)
    console.log('📊 Checking hiroo\'s followers subcollection:');
    const followersSnapshot = await db.collection('users')
      .doc(hirooUserId)
      .collection('followers')
      .get();
    
    console.log(`   Followers subcollection count: ${followersSnapshot.size}`);
    if (!followersSnapshot.empty) {
      console.log('   Followers:');
      followersSnapshot.docs.forEach(doc => {
        console.log(`     - ${doc.id} followed at ${doc.data().followedAt?.toDate() || 'unknown'}`);
      });
    } else {
      console.log('   No followers in subcollection');
    }
    console.log('');
    
    // Step 4: Check who hiroo is following
    console.log('📊 Checking who hiroo is following:');
    const followingSnapshot = await db.collection('users')
      .doc(hirooUserId)
      .collection('following')
      .get();
    
    console.log(`   Following count: ${followingSnapshot.size}`);
    if (!followingSnapshot.empty) {
      console.log('   Following:');
      for (const doc of followingSnapshot.docs) {
        const followedUserId = doc.id;
        const followedUserDoc = await db.collection('users').doc(followedUserId).get();
        const followedUsername = followedUserDoc.exists ? followedUserDoc.data().username : 'unknown';
        console.log(`     - ${followedUsername} (${followedUserId}) followed at ${doc.data().followedAt?.toDate() || 'unknown'}`);
      }
    } else {
      console.log('   Not following anyone');
    }
    console.log('');
    
    // Summary
    console.log('📋 SUMMARY:');
    console.log(`   Profile followerCount: ${hirooProfile.followerCount || 0}`);
    console.log(`   Actual followers (from following docs): ${actualFollowerCount}`);
    console.log(`   Followers subcollection: ${followersSnapshot.size}`);
    
    if (hirooProfile.followerCount !== actualFollowerCount || hirooProfile.followerCount !== followersSnapshot.size) {
      console.log('\n⚠️  DATA INCONSISTENCY DETECTED!');
      console.log(`   Profile says: ${hirooProfile.followerCount || 0} followers`);
      console.log(`   Actual count: ${actualFollowerCount} followers`);
      console.log(`   Subcollection: ${followersSnapshot.size} followers`);
    } else {
      console.log('\n✅ All follower counts match!');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

checkHirooFollowers();

