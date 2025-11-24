#!/usr/bin/env node

/**
 * SAFE Watagumostudio Account Deletion Script
 * This script has built-in safety checks to ensure we ONLY delete watagumostudio
 * and never accidentally delete Hiroo's account
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();
const auth = admin.auth();
const storage = admin.storage().bucket();

// ANSI color codes
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

// SAFETY CHECKS
const TARGET_USERNAME = 'watagumostudio';
const PROTECTED_USERNAMES = ['hiroo', 'haoyama', 'rosemaryylin', 'lawonearth', 'roseannechao', 'yuka', 'wholetjustincook']; // List of usernames to protect

async function findUserByUsername(username) {
  log(`\n🔍 Looking up user: @${username}...`, 'blue');
  
  const usersSnapshot = await db.collection('users').get();
  
  let user = null;
  usersSnapshot.forEach(doc => {
    const userData = doc.data();
    if (userData.username === username) {
      user = {
        id: doc.id,
        ...userData
      };
    }
  });
  
  return user;
}

async function safeDeleteWatagumostudio() {
  log('\n========================================', 'cyan');
  log('  SAFE WATAGUMOSTUDIO DELETION', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    // Step 1: Find watagumostudio user
    const targetUser = await findUserByUsername(TARGET_USERNAME);
    
    if (!targetUser) {
      log(`❌ User @${TARGET_USERNAME} not found in database`, 'red');
      log('\nAvailable users:', 'yellow');
      const usersSnapshot = await db.collection('users').get();
      usersSnapshot.forEach(doc => {
        const userData = doc.data();
        log(`  - @${userData.username} (${userData.displayName}) [ID: ${doc.id}]`, 'cyan');
      });
      log('\n');
      process.exit(1);
    }
    
    log('✅ Found target user:', 'green');
    log(`   Username:      @${targetUser.username}`, 'cyan');
    log(`   Display Name:  ${targetUser.displayName}`, 'cyan');
    log(`   User ID:       ${targetUser.id}`, 'cyan');
    log(`   Total Stamps:  ${targetUser.totalStamps}`, 'cyan');
    log(`   Followers:     ${targetUser.followerCount}`, 'cyan');
    log(`   Following:     ${targetUser.followingCount}\n`, 'cyan');
    
    // Step 2: SAFETY CHECK - Verify this is NOT a protected user
    log('🔒 Running safety checks...', 'yellow');
    
    if (PROTECTED_USERNAMES.includes(targetUser.username.toLowerCase())) {
      log('🚨 SAFETY CHECK FAILED! 🚨', 'red');
      log(`❌ User @${targetUser.username} is in the protected list!`, 'red');
      log('❌ ABORTING TO PREVENT ACCIDENTAL DELETION', 'red');
      process.exit(1);
    }
    
    if (targetUser.username !== TARGET_USERNAME) {
      log('🚨 SAFETY CHECK FAILED! 🚨', 'red');
      log(`❌ Username mismatch! Expected @${TARGET_USERNAME}, got @${targetUser.username}`, 'red');
      log('❌ ABORTING TO PREVENT ACCIDENTAL DELETION', 'red');
      process.exit(1);
    }
    
    log('✅ Safety checks passed', 'green');
    log(`✅ Confirmed target is @${TARGET_USERNAME} (NOT a protected user)\n`, 'green');
    
    // Step 3: Check for Hiroo separately to double-verify
    log('🔒 Double-checking Hiroo account is safe...', 'yellow');
    const hirooUser = await findUserByUsername('hiroo');
    
    if (hirooUser && hirooUser.id === targetUser.id) {
      log('🚨 CRITICAL ERROR! 🚨', 'red');
      log('❌ Target user ID matches Hiroo\'s ID!', 'red');
      log('❌ ABORTING TO PREVENT ACCIDENTAL DELETION', 'red');
      process.exit(1);
    }
    
    if (hirooUser) {
      log('✅ Verified Hiroo account is safe:', 'green');
      log(`   Hiroo ID:  ${hirooUser.id}`, 'cyan');
      log(`   Target ID: ${targetUser.id}`, 'cyan');
      log(`   IDs are different ✓\n`, 'green');
    }
    
    // Step 4: Show what will be deleted
    log('📋 Preparing to delete the following:', 'yellow');
    log('   - User profile document', 'cyan');
    log('   - Collected stamps subcollection', 'cyan');
    log('   - Following relationships (and update followed users)', 'cyan');
    log('   - Follower relationships (and update follower users)', 'cyan');
    log('   - Blocked users', 'cyan');
    log('   - Likes', 'cyan');
    log('   - Comments', 'cyan');
    log('   - Feedback', 'cyan');
    log('   - Stamp statistics entries', 'cyan');
    log('   - Invite code slot (free up for reuse)', 'cyan');
    log('   - Notifications', 'cyan');
    log('   - Storage files', 'cyan');
    log('   - Authentication account\n', 'cyan');
    
    // Step 5: Perform the deletion
    log('🗑️  Starting deletion process...', 'blue');
    log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n', 'blue');
    
    const userId = targetUser.id;
    
    // Delete collected stamps
    log('[1/12] Deleting collected stamps...', 'blue');
    const collectedStampsRef = db.collection('users').doc(userId).collection('collectedStamps');
    const collectedStamps = await collectedStampsRef.get();
    if (!collectedStamps.empty) {
      const batch = db.batch();
      collectedStamps.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${collectedStamps.size} collected stamps`, 'green');
    } else {
      log('       No collected stamps found', 'yellow');
    }
    
    // Delete following relationships
    log('\n[2/12] Deleting following relationships...', 'blue');
    const followingRef = db.collection('users').doc(userId).collection('following');
    const following = await followingRef.get();
    if (!following.empty) {
      for (const doc of following.docs) {
        const followedUserId = doc.id;
        await doc.ref.delete();
        await db.collection('users').doc(followedUserId).collection('followers').doc(userId).delete();
        await db.collection('users').doc(followedUserId).update({
          followerCount: admin.firestore.FieldValue.increment(-1)
        });
      }
      log(`       ✅ Deleted ${following.size} following relationships`, 'green');
    } else {
      log('       No following relationships found', 'yellow');
    }
    
    // Delete follower relationships
    log('\n[3/12] Deleting follower relationships...', 'blue');
    const followersRef = db.collection('users').doc(userId).collection('followers');
    const followers = await followersRef.get();
    if (!followers.empty) {
      for (const doc of followers.docs) {
        const followerUserId = doc.id;
        await doc.ref.delete();
        await db.collection('users').doc(followerUserId).collection('following').doc(userId).delete();
        await db.collection('users').doc(followerUserId).update({
          followingCount: admin.firestore.FieldValue.increment(-1)
        });
      }
      log(`       ✅ Deleted ${followers.size} follower relationships`, 'green');
    } else {
      log('       No follower relationships found', 'yellow');
    }
    
    // Delete blocked users
    log('\n[4/12] Deleting blocked users...', 'blue');
    const blockedRef = db.collection('users').doc(userId).collection('blocked');
    const blocked = await blockedRef.get();
    if (!blocked.empty) {
      const batch = db.batch();
      blocked.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${blocked.size} blocked users`, 'green');
    } else {
      log('       No blocked users found', 'yellow');
    }
    
    // Delete likes
    log('\n[5/12] Deleting likes...', 'blue');
    const likesQuery = await db.collection('likes').where('userId', '==', userId).get();
    if (!likesQuery.empty) {
      const batch = db.batch();
      likesQuery.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${likesQuery.size} likes`, 'green');
    } else {
      log('       No likes found', 'yellow');
    }
    
    // Delete comments
    log('\n[6/12] Deleting comments...', 'blue');
    const commentsQuery = await db.collection('comments').where('userId', '==', userId).get();
    if (!commentsQuery.empty) {
      const batch = db.batch();
      commentsQuery.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${commentsQuery.size} comments`, 'green');
    } else {
      log('       No comments found', 'yellow');
    }
    
    // Delete feedback
    log('\n[7/12] Deleting feedback...', 'blue');
    const feedbackQuery = await db.collection('feedback').where('userId', '==', userId).get();
    if (!feedbackQuery.empty) {
      const batch = db.batch();
      feedbackQuery.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${feedbackQuery.size} feedback entries`, 'green');
    } else {
      log('       No feedback found', 'yellow');
    }
    
    // Remove from stamp statistics
    log('\n[8/13] Removing from stamp statistics...', 'blue');
    const statsQuery = await db.collection('stamp_statistics')
      .where('collectorUserIds', 'array-contains', userId)
      .get();
    if (!statsQuery.empty) {
      const batch = db.batch();
      statsQuery.forEach(doc => {
        batch.update(doc.ref, {
          collectorUserIds: admin.firestore.FieldValue.arrayRemove(userId),
          totalCollectors: admin.firestore.FieldValue.increment(-1)
        });
      });
      await batch.commit();
      log(`       ✅ Removed from ${statsQuery.size} stamp statistics`, 'green');
    } else {
      log('       User not found in any stamp statistics', 'yellow');
    }
    
    // Free up invite code slot
    log('\n[9/13] Freeing up invite code slot...', 'blue');
    const inviteCodeUsed = targetUser.inviteCodeUsed;
    if (inviteCodeUsed) {
      try {
        const inviteCodeRef = db.collection('invite_codes').doc(inviteCodeUsed);
        const inviteCodeDoc = await inviteCodeRef.get();
        
        if (inviteCodeDoc.exists) {
          await inviteCodeRef.update({
            usedCount: admin.firestore.FieldValue.increment(-1),
            usedBy: admin.firestore.FieldValue.arrayRemove(userId)
          });
          log(`       ✅ Freed up slot in invite code: ${inviteCodeUsed}`, 'green');
        } else {
          log(`       ⚠️  Invite code "${inviteCodeUsed}" not found`, 'yellow');
        }
      } catch (error) {
        log(`       ⚠️  Could not update invite code: ${error.message}`, 'yellow');
      }
    } else {
      log('       No invite code to free up', 'yellow');
    }
    
    // Delete notifications (both received and sent)
    log('\n[10/13] Deleting notifications...', 'blue');
    
    // Delete notifications received by this user (in their subcollection)
    const notificationsRef = db.collection('users').doc(userId).collection('notifications');
    const notifications = await notificationsRef.get();
    if (!notifications.empty) {
      const batch = db.batch();
      notifications.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${notifications.size} received notifications`, 'green');
    } else {
      log('       No received notifications found', 'yellow');
    }
    
    // Delete notifications sent by this user (where they are the actor in top-level collection)
    const sentNotificationsQuery = await db.collection('notifications').where('actorId', '==', userId).get();
    if (!sentNotificationsQuery.empty) {
      const batch = db.batch();
      sentNotificationsQuery.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      log(`       ✅ Deleted ${sentNotificationsQuery.size} sent notifications (where user was actor)`, 'green');
    } else {
      log('       No sent notifications found', 'yellow');
    }
    
    // Delete storage files
    log('\n[11/13] Deleting storage files...', 'blue');
    const [files] = await storage.getFiles({ prefix: `users/${userId}/` });
    if (files.length > 0) {
      for (const file of files) {
        await file.delete();
      }
      log(`       ✅ Deleted ${files.length} storage files`, 'green');
    } else {
      log('       No storage files found', 'yellow');
    }
    
    // Delete user profile
    log('\n[12/13] Deleting user profile...', 'blue');
    await db.collection('users').doc(userId).delete();
    log('       ✅ User profile deleted', 'green');
    
    // Delete authentication account
    log('\n[13/13] Deleting authentication account...', 'blue');
    try {
      await auth.deleteUser(userId);
      log('       ✅ Authentication account deleted', 'green');
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        log('       ⚠️  Auth account already deleted', 'yellow');
      } else {
        throw error;
      }
    }
    
    // Success!
    log('\n========================================', 'green');
    log('  ✅ DELETION COMPLETE', 'green');
    log('========================================', 'green');
    log(`\n@${TARGET_USERNAME} has been completely removed.`, 'cyan');
    log('They can now create a fresh account.\n', 'cyan');
    
    // Final verification that Hiroo is still there
    log('🔒 Final safety check - verifying Hiroo is still safe...', 'yellow');
    const hirooCheck = await findUserByUsername('hiroo');
    if (hirooCheck) {
      log('✅ Confirmed: Hiroo account is still intact!', 'green');
      log(`   Username: @${hirooCheck.username}`, 'cyan');
      log(`   ID: ${hirooCheck.id}`, 'cyan');
      log(`   Stamps: ${hirooCheck.totalStamps}\n`, 'cyan');
    } else {
      log('🚨 WARNING: Hiroo account not found!', 'red');
      log('This should not happen - please investigate!\n', 'red');
    }
    
  } catch (error) {
    log('\n========================================', 'red');
    log('  ❌ ERROR DURING DELETION', 'red');
    log('========================================\n', 'red');
    log(`Error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  }
}

// Main execution
log(`\n⚠️  This script will delete @${TARGET_USERNAME} account`, 'yellow');
log('⚠️  Built-in safety checks will prevent deleting Hiroo', 'yellow');
log('⚠️  Press Ctrl+C now if you want to cancel\n', 'yellow');

safeDeleteWatagumostudio()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    log(`\n❌ Unexpected error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  });

