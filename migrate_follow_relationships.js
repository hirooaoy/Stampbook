#!/usr/bin/env node

/**
 * Migrate Follow Relationships to Bidirectional Structure
 * 
 * PROBLEM:
 * The old followUser() function only created one-way relationships:
 * - users/{follower}/following/{followee} ✅
 * - users/{followee}/followers/{follower} ❌ MISSING
 * 
 * This script fixes all existing follow relationships by:
 * 1. Scanning all "following" subcollections across all users
 * 2. Creating the missing "followers" subcollection entries
 * 3. Updating followerCount and followingCount fields correctly
 * 
 * SAFE TO RUN MULTIPLE TIMES (idempotent)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function migrateFollowRelationships() {
  try {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('FOLLOW RELATIONSHIP MIGRATION');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    console.log('🔍 Step 1: Scanning all follow relationships...\n');
    
    // Use collection group to find ALL follow relationships
    const followingSnapshot = await db.collectionGroup('following').get();
    
    console.log(`   Found ${followingSnapshot.size} total follow relationships\n`);
    
    let created = 0;
    let alreadyExists = 0;
    let errors = 0;
    
    console.log('🔧 Step 2: Creating missing bidirectional relationships...\n');
    
    for (const followDoc of followingSnapshot.docs) {
      try {
        // Extract IDs from path: users/{followerId}/following/{followeeId}
        const pathComponents = followDoc.ref.path.split('/');
        const followerId = pathComponents[1];
        const followeeId = followDoc.id;
        
        // Get usernames for logging
        const followerDoc = await db.collection('users').doc(followerId).get();
        const followeeDoc = await db.collection('users').doc(followeeId).get();
        
        const followerUsername = followerDoc.exists ? followerDoc.data().username : followerId;
        const followeeUsername = followeeDoc.exists ? followeeDoc.data().username : followeeId;
        
        // Check if reverse relationship exists
        const followerRef = db
          .collection('users')
          .doc(followeeId)
          .collection('followers')
          .doc(followerId);
        
        const existingFollower = await followerRef.get();
        
        if (existingFollower.exists) {
          console.log(`   ✅ @${followerUsername} → @${followeeUsername} (already bidirectional)`);
          alreadyExists++;
        } else {
          // Create the missing follower relationship
          const followData = followDoc.data();
          const followerData = {
            id: followerId,
            followedAt: followData.createdAt || admin.firestore.FieldValue.serverTimestamp()
          };
          
          await followerRef.set(followerData);
          
          console.log(`   🔧 @${followerUsername} → @${followeeUsername} (created missing followers entry)`);
          created++;
        }
      } catch (error) {
        console.error(`   ❌ Error processing relationship: ${error.message}`);
        errors++;
      }
    }
    
    console.log('\n🔧 Step 3: Recalculating follower/following counts...\n');
    
    const usersSnapshot = await db.collection('users').get();
    let countsUpdated = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      // Count actual followers
      const followersSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('followers')
        .get();
      
      // Count actual following
      const followingSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('following')
        .get();
      
      const actualFollowers = followersSnapshot.size;
      const actualFollowing = followingSnapshot.size;
      
      // Update if counts are wrong
      if (userData.followerCount !== actualFollowers || userData.followingCount !== actualFollowing) {
        await db.collection('users').doc(userId).update({
          followerCount: actualFollowers,
          followingCount: actualFollowing
        });
        
        console.log(`   🔧 @${userData.username}: followers ${userData.followerCount} → ${actualFollowers}, following ${userData.followingCount} → ${actualFollowing}`);
        countsUpdated++;
      } else {
        console.log(`   ✅ @${userData.username}: counts already correct (followers=${actualFollowers}, following=${actualFollowing})`);
      }
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('MIGRATION SUMMARY');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    console.log(`   Total follow relationships: ${followingSnapshot.size}`);
    console.log(`   ✅ Already bidirectional: ${alreadyExists}`);
    console.log(`   🔧 Created missing entries: ${created}`);
    console.log(`   ❌ Errors: ${errors}`);
    console.log(`   📊 Counts updated: ${countsUpdated} users`);
    console.log('');
    
    if (created > 0 || countsUpdated > 0) {
      console.log('✅ Migration complete!');
      console.log('');
      console.log('⚠️  IMPORTANT: Users need to refresh their app to see correct counts');
      console.log('   Tell users to force quit and reopen the app, or sign out and back in.');
      console.log('');
    } else {
      console.log('✅ All relationships already bidirectional, no migration needed!');
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    console.error(error);
    process.exit(1);
  }
}

migrateFollowRelationships()
  .then(() => {
    console.log('✅ Script complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

