#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const DELETED_USER_ID = '0a6oYGdJS7QT4PvsdN6QABveuO62'; // watagumo_test

async function checkAllUsersForOrphanedFollows() {
  try {
    console.log('\n🔍 Checking all users for orphaned relationships to deleted user...\n');
    console.log(`Deleted user ID: ${DELETED_USER_ID}\n`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    const usersSnapshot = await db.collection('users').get();
    
    let issuesFound = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      // Check following subcollection for orphaned relationship
      const followingSnapshot = await db.collection('users').doc(userId).collection('following').doc(DELETED_USER_ID).get();
      
      // Check followers subcollection for orphaned relationship
      const followerSnapshot = await db.collection('users').doc(userId).collection('followers').doc(DELETED_USER_ID).get();
      
      if (followingSnapshot.exists || followerSnapshot.exists) {
        issuesFound++;
        console.log(`❌ ORPHANED RELATIONSHIP FOUND:`);
        console.log(`   User: @${userData.username} (${userId})`);
        if (followingSnapshot.exists) {
          console.log(`   - Has orphaned FOLLOWING relationship to deleted user`);
          console.log(`   - Current followingCount: ${userData.followingCount}`);
        }
        if (followerSnapshot.exists) {
          console.log(`   - Has orphaned FOLLOWER relationship from deleted user`);
          console.log(`   - Current followerCount: ${userData.followerCount}`);
        }
        console.log();
      } else {
        console.log(`✅ @${userData.username}: Clean (no orphaned relationships)`);
      }
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    if (issuesFound === 0) {
      console.log('✅ ALL USERS ARE CLEAN!\n');
      console.log('No orphaned relationships found.\n');
    } else {
      console.log(`⚠️  Found ${issuesFound} user(s) with orphaned relationships.\n`);
      console.log('These should be cleaned up to keep data consistent.\n');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

checkAllUsersForOrphanedFollows()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });

