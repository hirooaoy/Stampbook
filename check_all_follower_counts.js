const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Check if already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function checkAllFollowerCounts() {
  try {
    console.log('🔍 Checking all users for follower count inconsistencies...\n');
    
    const usersSnapshot = await db.collection('users').get();
    const issues = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const username = userData.username || 'unknown';
      const profileFollowerCount = userData.followerCount || 0;
      const profileFollowingCount = userData.followingCount || 0;
      
      // Check actual followers (people following this user)
      let actualFollowerCount = 0;
      for (const otherUserDoc of usersSnapshot.docs) {
        const followingDoc = await db.collection('users')
          .doc(otherUserDoc.id)
          .collection('following')
          .doc(userId)
          .get();
        
        if (followingDoc.exists) {
          actualFollowerCount++;
        }
      }
      
      // Check followers subcollection
      const followersSnapshot = await db.collection('users')
        .doc(userId)
        .collection('followers')
        .get();
      
      // Check actual following (people this user follows)
      const followingSnapshot = await db.collection('users')
        .doc(userId)
        .collection('following')
        .get();
      
      const actualFollowingCount = followingSnapshot.size;
      
      // Report if there's any mismatch
      if (profileFollowerCount !== actualFollowerCount || 
          profileFollowerCount !== followersSnapshot.size ||
          profileFollowingCount !== actualFollowingCount) {
        
        issues.push({
          username,
          userId,
          profileFollowerCount,
          actualFollowerCount,
          followersSubcollectionCount: followersSnapshot.size,
          profileFollowingCount,
          actualFollowingCount
        });
        
        console.log(`⚠️  ${username} (${userId})`);
        console.log(`   Profile followerCount: ${profileFollowerCount}, Actual: ${actualFollowerCount}, Subcollection: ${followersSnapshot.size}`);
        console.log(`   Profile followingCount: ${profileFollowingCount}, Actual: ${actualFollowingCount}`);
        console.log('');
      } else {
        console.log(`✅ ${username} (${userId}) - All counts match`);
      }
    }
    
    console.log('\n📋 SUMMARY:');
    console.log(`   Total users checked: ${usersSnapshot.size}`);
    console.log(`   Users with issues: ${issues.length}`);
    
    if (issues.length > 0) {
      console.log('\n⚠️  USERS WITH DATA INCONSISTENCIES:');
      issues.forEach(issue => {
        console.log(`   - ${issue.username}: follower (profile: ${issue.profileFollowerCount}, actual: ${issue.actualFollowerCount}), following (profile: ${issue.profileFollowingCount}, actual: ${issue.actualFollowingCount})`);
      });
    } else {
      console.log('\n✅ All users have consistent follower/following counts!');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

checkAllFollowerCounts();

