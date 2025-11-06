/**
 * PHASE 2: Reconciliation Script
 * 
 * WHAT THIS DOES:
 * - Counts actual likes/comments in subcollections (source of truth)
 * - Compares to stored likeCount/commentCount in posts
 * - Reports drift (network failures, race conditions, etc.)
 * - Optionally fixes drift automatically
 * 
 * WHY WE NEED THIS:
 * - Distributed systems can drift (network failures, timeouts)
 * - This is NORMAL and expected
 * - Regular reconciliation keeps system healthy
 * 
 * HOW TO USE:
 * 1. Run in DRY_RUN mode first: node reconcile_like_comment_counts.js
 * 2. Review the output (what would be fixed)
 * 3. If looks good, run with fixes: DRY_RUN=false node reconcile_like_comment_counts.js
 * 
 * FREQUENCY:
 * - Run weekly (or whenever you want peace of mind)
 * - Takes ~30 seconds to run
 * 
 * SAFETY:
 * - DRY_RUN mode by default (just reports, doesn't fix)
 * - Sets counts to ACTUAL reality (can't make them wrong)
 * - No risk to app code (separate script)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

// DRY_RUN mode: true = just report, false = actually fix
// Override with: DRY_RUN=false node reconcile_like_comment_counts.js
const DRY_RUN = process.env.DRY_RUN !== 'false';

async function reconcileCounts() {
  console.log('\n🔄 PHASE 2: Reconciliation - Like & Comment Counts\n');
  console.log('=' .repeat(60));
  console.log(`Mode: ${DRY_RUN ? '🔍 DRY RUN (report only)' : '🔧 FIXING (will update counts)'}`);
  console.log('=' .repeat(60));
  
  let totalPostsChecked = 0;
  let driftFound = 0;
  let likeDrifts = 0;
  let commentDrifts = 0;
  let totalLikesDiff = 0;
  let totalCommentsDiff = 0;
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    console.log(`\n📊 Checking ${usersSnapshot.size} users...\n`);
    
    // Process each user's posts
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const username = userData.username || userId;
      
      // Get all collected stamps (posts) for this user
      const postsSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
      
      if (postsSnapshot.empty) {
        console.log(`👤 ${username}: No posts to check`);
        continue;
      }
      
      console.log(`\n👤 ${username}: Checking ${postsSnapshot.size} posts...`);
      
      // Check each post
      for (const postDoc of postsSnapshot.docs) {
        totalPostsChecked++;
        const stampId = postDoc.id;
        const postData = postDoc.data();
        const postId = `${userId}-${stampId}`;
        
        // Stored counts
        const storedLikeCount = postData.likeCount ?? 0;
        const storedCommentCount = postData.commentCount ?? 0;
        
        // Count actual likes in subcollection
        const likesSnapshot = await db
          .collection('likes')
          .where('postId', '==', postId)
          .get();
        const actualLikeCount = likesSnapshot.size;
        
        // Count actual comments in subcollection
        const commentsSnapshot = await db
          .collection('comments')
          .where('postId', '==', postId)
          .get();
        const actualCommentCount = commentsSnapshot.size;
        
        // Check for drift
        const likeDrift = actualLikeCount !== storedLikeCount;
        const commentDrift = actualCommentCount !== storedCommentCount;
        
        if (likeDrift || commentDrift) {
          driftFound++;
          
          console.log(`\n   ⚠️  DRIFT DETECTED: ${stampId}`);
          
          if (likeDrift) {
            likeDrifts++;
            const diff = actualLikeCount - storedLikeCount;
            totalLikesDiff += Math.abs(diff);
            console.log(`      Likes: stored=${storedLikeCount}, actual=${actualLikeCount} (${diff > 0 ? '+' : ''}${diff})`);
          }
          
          if (commentDrift) {
            commentDrifts++;
            const diff = actualCommentCount - storedCommentCount;
            totalCommentsDiff += Math.abs(diff);
            console.log(`      Comments: stored=${storedCommentCount}, actual=${actualCommentCount} (${diff > 0 ? '+' : ''}${diff})`);
          }
          
          // Fix if not in dry-run mode
          if (!DRY_RUN) {
            const updates = {};
            if (likeDrift) updates.likeCount = actualLikeCount;
            if (commentDrift) updates.commentCount = actualCommentCount;
            
            await postDoc.ref.update(updates);
            console.log(`      ✅ FIXED`);
          } else {
            console.log(`      💡 Would fix (run with DRY_RUN=false to fix)`);
          }
        }
      }
      
      if (driftFound === 0) {
        console.log(`   ✅ All counts accurate!`);
      }
    }
    
    // Summary
    console.log('\n' + '='.repeat(60));
    console.log('📋 RECONCILIATION SUMMARY\n');
    console.log(`Total posts checked: ${totalPostsChecked}`);
    console.log(`Posts with drift: ${driftFound}`);
    
    if (driftFound > 0) {
      console.log(`\nDrift breakdown:`);
      console.log(`  - Like count drift: ${likeDrifts} posts (${totalLikesDiff} total difference)`);
      console.log(`  - Comment count drift: ${commentDrifts} posts (${totalCommentsDiff} total difference)`);
      
      if (DRY_RUN) {
        console.log(`\n💡 To fix these drifts, run:`);
        console.log(`   DRY_RUN=false node reconcile_like_comment_counts.js`);
      } else {
        console.log(`\n✅ All drifts have been fixed!`);
        console.log(`   Counts now match actual reality.`);
      }
    } else {
      console.log(`\n✅ Perfect! No drift detected.`);
      console.log(`   All counts are accurate.`);
    }
    
    // Health score
    const healthScore = totalPostsChecked > 0 
      ? ((totalPostsChecked - driftFound) / totalPostsChecked * 100).toFixed(1)
      : 100;
    
    console.log(`\n📊 System Health: ${healthScore}% accurate`);
    
    if (parseFloat(healthScore) >= 99) {
      console.log(`   🎉 Excellent! System is very healthy.`);
    } else if (parseFloat(healthScore) >= 95) {
      console.log(`   ✅ Good. Minor drift is normal.`);
    } else if (parseFloat(healthScore) >= 90) {
      console.log(`   ⚠️  Fair. Consider running reconciliation more often.`);
    } else {
      console.log(`   🚨 Needs attention. Run fixes and investigate root cause.`);
    }
    
    console.log('\n' + '='.repeat(60));
    
    // Recommendations
    if (driftFound === 0) {
      console.log('\n💚 RECOMMENDATION: System is healthy!');
      console.log('   Run this script weekly for ongoing health checks.\n');
    } else if (driftFound < 5) {
      console.log('\n💛 RECOMMENDATION: Minor drift detected.');
      console.log('   This is normal. Fix when convenient.\n');
    } else {
      console.log('\n🧡 RECOMMENDATION: Multiple drifts detected.');
      console.log('   Fix these and monitor more frequently.\n');
    }
    
  } catch (error) {
    console.error('\n❌ Error during reconciliation:', error);
    throw error;
  }
  
  process.exit(0);
}

// Run reconciliation
console.log('🚀 Starting reconciliation...');
console.log(`   Checking actual vs. stored counts...\n`);

reconcileCounts();

