#!/usr/bin/env node

/**
 * Comprehensive Follow Relationship Verification
 * 
 * Shows every user's followers and following in table format
 * Verifies bidirectional relationships and counts
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function verifyAllFollowRelationships() {
  try {
    console.log('\n═══════════════════════════════════════════════════════════════');
    console.log('COMPREHENSIVE FOLLOW RELATIONSHIP VERIFICATION');
    console.log('═══════════════════════════════════════════════════════════════\n');
    
    const usersSnapshot = await db.collection('users').get();
    const users = [];
    
    // Collect all user data
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      // Get followers subcollection
      const followersSnapshot = await db.collection('users').doc(userId).collection('followers').get();
      const followersList = [];
      for (const doc of followersSnapshot.docs) {
        const followerDoc = await db.collection('users').doc(doc.id).get();
        if (followerDoc.exists) {
          followersList.push(followerDoc.data().username);
        }
      }
      
      // Get following subcollection
      const followingSnapshot = await db.collection('users').doc(userId).collection('following').get();
      const followingList = [];
      for (const doc of followingSnapshot.docs) {
        const followeeDoc = await db.collection('users').doc(doc.id).get();
        if (followeeDoc.exists) {
          followingList.push(followeeDoc.data().username);
        }
      }
      
      users.push({
        username: userData.username,
        userId: userId,
        followerCount: userData.followerCount,
        actualFollowers: followersSnapshot.size,
        followersList: followersList.sort(),
        followingCount: userData.followingCount,
        actualFollowing: followingSnapshot.size,
        followingList: followingList.sort()
      });
    }
    
    // Sort users alphabetically
    users.sort((a, b) => a.username.localeCompare(b.username));
    
    // Display detailed table for each user
    for (const user of users) {
      const countMatch = 
        user.followerCount === user.actualFollowers && 
        user.followingCount === user.actualFollowing;
      
      const status = countMatch ? '✅' : '❌';
      
      console.log(`${status} @${user.username}`);
      console.log('─────────────────────────────────────────────────────────────');
      console.log(`   User ID: ${user.userId}`);
      console.log('');
      console.log(`   FOLLOWERS: ${user.followerCount} (field) | ${user.actualFollowers} (actual)`);
      if (user.actualFollowers > 0) {
        user.followersList.forEach(f => console.log(`      • @${f}`));
      } else {
        console.log(`      (none)`);
      }
      console.log('');
      console.log(`   FOLLOWING: ${user.followingCount} (field) | ${user.actualFollowing} (actual)`);
      if (user.actualFollowing > 0) {
        user.followingList.forEach(f => console.log(`      • @${f}`));
      } else {
        console.log(`      (none)`);
      }
      
      if (!countMatch) {
        console.log('');
        console.log(`   ⚠️  MISMATCH DETECTED!`);
        if (user.followerCount !== user.actualFollowers) {
          console.log(`      Followers: field=${user.followerCount}, actual=${user.actualFollowers}`);
        }
        if (user.followingCount !== user.actualFollowing) {
          console.log(`      Following: field=${user.followingCount}, actual=${user.actualFollowing}`);
        }
      }
      
      console.log('');
    }
    
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('BIDIRECTIONAL RELATIONSHIP VERIFICATION');
    console.log('═══════════════════════════════════════════════════════════════\n');
    
    let bidirectionalErrors = 0;
    
    for (const user of users) {
      // For each person this user follows, verify the reverse relationship exists
      for (const followeeUsername of user.followingList) {
        const followee = users.find(u => u.username === followeeUsername);
        if (followee && !followee.followersList.includes(user.username)) {
          console.log(`❌ BROKEN: @${user.username} follows @${followeeUsername}, but @${followeeUsername} doesn't have @${user.username} in followers!`);
          bidirectionalErrors++;
        }
      }
      
      // For each follower, verify the reverse relationship exists
      for (const followerUsername of user.followersList) {
        const follower = users.find(u => u.username === followerUsername);
        if (follower && !follower.followingList.includes(user.username)) {
          console.log(`❌ BROKEN: @${followerUsername} is in @${user.username}'s followers, but @${user.username} is not in @${followerUsername}'s following!`);
          bidirectionalErrors++;
        }
      }
    }
    
    if (bidirectionalErrors === 0) {
      console.log('✅ All bidirectional relationships are CORRECT!\n');
    } else {
      console.log(`\n❌ Found ${bidirectionalErrors} bidirectional relationship errors!\n`);
    }
    
    console.log('═══════════════════════════════════════════════════════════════');
    console.log('SUMMARY');
    console.log('═══════════════════════════════════════════════════════════════\n');
    
    const totalUsers = users.length;
    const usersWithCorrectCounts = users.filter(u => 
      u.followerCount === u.actualFollowers && 
      u.followingCount === u.actualFollowing
    ).length;
    const usersWithMismatches = totalUsers - usersWithCorrectCounts;
    
    console.log(`   Total users: ${totalUsers}`);
    console.log(`   ✅ Correct counts: ${usersWithCorrectCounts}`);
    console.log(`   ❌ Mismatched counts: ${usersWithMismatches}`);
    console.log(`   ❌ Bidirectional errors: ${bidirectionalErrors}`);
    console.log('');
    
    if (usersWithMismatches === 0 && bidirectionalErrors === 0) {
      console.log('✅ ALL FOLLOW RELATIONSHIPS ARE CORRECT!\n');
    } else {
      console.log('❌ FOLLOW RELATIONSHIPS HAVE ERRORS - RUN MIGRATION AGAIN!\n');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

verifyAllFollowRelationships()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

