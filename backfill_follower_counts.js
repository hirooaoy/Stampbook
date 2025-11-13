#!/usr/bin/env node

/**
 * Backfill Follower/Following Counts
 * 
 * One-time script to populate denormalized follower/following counts for existing users
 * Run this after deploying the updateFollowCounts Cloud Function
 * 
 * Usage:
 *   node backfill_follower_counts.js
 * 
 * What it does:
 * 1. Fetches all users from Firestore
 * 2. For each user, counts actual followers/following from subcollections
 * 3. Updates user profile with correct counts
 * 4. Commits in batches of 500 (Firestore limit)
 * 
 * Safe to run multiple times - just overwrites with correct counts
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function backfillFollowerCounts() {
  console.log('🔄 Backfilling follower/following counts...\n');
  const startTime = Date.now();
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`📊 Found ${usersSnapshot.size} users to process\n`);
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found. Nothing to do.');
      return;
    }
    
    let batch = db.batch();
    let updateCount = 0;
    let batchCount = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      console.log(`\n🔍 Processing: ${userData.username || userId}`);
      
      // Count followers (users who follow this user)
      const followersSnapshot = await db.collectionGroup('following')
        .where('id', '==', userId)
        .get();
      const followerCount = followersSnapshot.size;
      console.log(`   Followers: ${followerCount}`);
      
      // Count following (users this user follows)
      const followingSnapshot = await db.collection('users')
        .doc(userId)
        .collection('following')
        .get();
      const followingCount = followingSnapshot.size;
      console.log(`   Following: ${followingCount}`);
      
      // Update user document with counts
      batch.update(userDoc.ref, {
        followerCount: followerCount,
        followingCount: followingCount
      });
      
      updateCount++;
      
      // Commit in batches of 500 (Firestore limit)
      if (updateCount % 500 === 0) {
        console.log(`\n💾 Committing batch ${Math.floor(updateCount / 500)}...`);
        await batch.commit();
        batch = db.batch(); // Start new batch
        batchCount++;
        console.log(`✅ Batch committed (${updateCount} users processed so far)`);
      }
    }
    
    // Commit remaining updates
    if (updateCount % 500 !== 0) {
      console.log(`\n💾 Committing final batch...`);
      await batch.commit();
      batchCount++;
    }
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    
    console.log(`\n${'='.repeat(50)}`);
    console.log(`✅ Backfill complete!`);
    console.log(`${'='.repeat(50)}`);
    console.log(`   Users updated: ${updateCount}`);
    console.log(`   Batches committed: ${batchCount}`);
    console.log(`   Time taken: ${duration}s`);
    console.log(`${'='.repeat(50)}\n`);
    
  } catch (error) {
    console.error(`\n❌ Error during backfill:`, error);
    throw error;
  }
}

// Run the script
backfillFollowerCounts()
  .then(() => {
    console.log('👋 Done!');
    process.exit(0);
  })
  .catch(error => {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  });

