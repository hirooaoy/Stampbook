#!/usr/bin/env node

/**
 * Reconcile Follower/Following Counts
 * 
 * Monthly maintenance script to check for count discrepancies and fix them
 * Run this to catch any drift caused by failed Cloud Function executions
 * 
 * Usage:
 *   node reconcile_follower_counts.js
 * 
 * What it does:
 * 1. Fetches all users from Firestore
 * 2. For each user, compares stored count vs actual count
 * 3. Reports any discrepancies
 * 4. Fixes incorrect counts automatically
 * 
 * Safe to run anytime - read-only except when fixing discrepancies
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function reconcileFollowerCounts() {
  console.log('🔍 Checking for follower/following count discrepancies...\n');
  const startTime = Date.now();
  
  try {
    const usersSnapshot = await db.collection('users').get();
    console.log(`📊 Checking ${usersSnapshot.size} users...\n`);
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found. Nothing to do.');
      return;
    }
    
    let checkedCount = 0;
    let discrepancyCount = 0;
    let fixedCount = 0;
    const discrepancies = [];
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      checkedCount++;
      
      // Count actual followers/following from subcollections
      const followersSnapshot = await db.collectionGroup('following')
        .where('id', '==', userId)
        .get();
      const actualFollowerCount = followersSnapshot.size;
      
      const followingSnapshot = await db.collection('users')
        .doc(userId)
        .collection('following')
        .get();
      const actualFollowingCount = followingSnapshot.size;
      
      // Get stored counts (default to 0 if missing)
      const storedFollowerCount = userData.followerCount || 0;
      const storedFollowingCount = userData.followingCount || 0;
      
      // Check for discrepancies
      const followerDiff = actualFollowerCount - storedFollowerCount;
      const followingDiff = actualFollowingCount - storedFollowingCount;
      
      if (followerDiff !== 0 || followingDiff !== 0) {
        const username = userData.username || userId;
        console.log(`\n⚠️  Discrepancy found: ${username}`);
        console.log(`   Followers:  stored=${storedFollowerCount}, actual=${actualFollowerCount}, diff=${followerDiff > 0 ? '+' : ''}${followerDiff}`);
        console.log(`   Following:  stored=${storedFollowingCount}, actual=${actualFollowingCount}, diff=${followingDiff > 0 ? '+' : ''}${followingDiff}`);
        
        discrepancies.push({
          username,
          followerDiff,
          followingDiff
        });
        
        // Fix the counts
        await userDoc.ref.update({
          followerCount: actualFollowerCount,
          followingCount: actualFollowingCount
        });
        
        console.log(`   ✅ Fixed!`);
        fixedCount++;
        discrepancyCount++;
      } else {
        // Progress indicator every 10 users
        if (checkedCount % 10 === 0) {
          process.stdout.write('.');
        }
      }
    }
    
    const duration = ((Date.now() - startTime) / 1000).toFixed(2);
    
    console.log(`\n\n${'='.repeat(50)}`);
    console.log(`📊 Reconciliation Summary`);
    console.log(`${'='.repeat(50)}`);
    console.log(`   Total users checked: ${checkedCount}`);
    console.log(`   Discrepancies found: ${discrepancyCount}`);
    console.log(`   Counts fixed: ${fixedCount}`);
    console.log(`   Time taken: ${duration}s`);
    console.log(`${'='.repeat(50)}`);
    
    if (discrepancyCount === 0) {
      console.log(`\n✅ All counts are accurate! No issues found.`);
    } else {
      console.log(`\n⚠️  Found ${discrepancyCount} discrepancies (now fixed):`);
      console.log(`\n   Top issues:`);
      discrepancies.slice(0, 5).forEach(d => {
        console.log(`   - ${d.username}: followers ${d.followerDiff > 0 ? '+' : ''}${d.followerDiff}, following ${d.followingDiff > 0 ? '+' : ''}${d.followingDiff}`);
      });
      
      if (discrepancies.length > 5) {
        console.log(`   ... and ${discrepancies.length - 5} more`);
      }
      
      console.log(`\n💡 Recommendation: Check Cloud Function logs if many discrepancies found.`);
      console.log(`   Function name: updateFollowCounts`);
      console.log(`   Check: https://console.firebase.google.com/project/stampbook-app/functions/logs`);
    }
    
    console.log('');
    
  } catch (error) {
    console.error(`\n❌ Error during reconciliation:`, error);
    throw error;
  }
}

// Run the script
reconcileFollowerCounts()
  .then(() => {
    console.log('👋 Done!');
    process.exit(0);
  })
  .catch(error => {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  });

