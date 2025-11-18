#!/usr/bin/env node

/**
 * Complete User Account Deletion Script
 * Deletes a user account and all associated data from Firebase
 * 
 * Usage: node delete_user_account.js <userId>
 * Example: node delete_user_account.js mpd4k2n13adMFMY52nksmaQTbMQ2
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

// ANSI color codes for better readability
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

async function deleteUserAccount(userId) {
  log('\n========================================', 'cyan');
  log('  ACCOUNT DELETION SCRIPT', 'cyan');
  log('========================================\n', 'cyan');
  
  log(`🎯 Target User ID: ${userId}\n`, 'yellow');
  
  try {
    // Step 1: Get user info before deletion
    log('📋 Step 1: Fetching user information...', 'blue');
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      log('⚠️  User profile not found in Firestore', 'yellow');
    } else {
      const userData = userDoc.data();
      log(`   Username: @${userData.username}`, 'cyan');
      log(`   Display Name: ${userData.displayName}`, 'cyan');
      log(`   Total Stamps: ${userData.totalStamps}`, 'cyan');
      log(`   Followers: ${userData.followerCount}`, 'cyan');
      log(`   Following: ${userData.followingCount}\n`, 'cyan');
    }
    
    // Step 2: Delete collected stamps subcollection
    log('📋 Step 2: Deleting collected stamps...', 'blue');
    const collectedStampsRef = db.collection('users').doc(userId).collection('collectedStamps');
    const collectedStamps = await collectedStampsRef.get();
    
    if (collectedStamps.empty) {
      log('   No collected stamps found', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      collectedStamps.forEach(doc => {
        batch.delete(doc.ref);
        count++;
      });
      await batch.commit();
      log(`   ✅ Deleted ${count} collected stamps`, 'green');
    }
    
    // Step 3: Delete following subcollection AND update followed users
    log('\n📋 Step 3: Deleting following relationships...', 'blue');
    const followingRef = db.collection('users').doc(userId).collection('following');
    const following = await followingRef.get();
    
    if (following.empty) {
      log('   No following relationships found', 'yellow');
    } else {
      let count = 0;
      // Process each followed user
      for (const doc of following.docs) {
        const followedUserId = doc.id;
        
        // Delete this user's following document
        await doc.ref.delete();
        
        // Delete reciprocal follower document from the followed user
        await db.collection('users').doc(followedUserId).collection('followers').doc(userId).delete();
        
        // Decrement followed user's followerCount
        await db.collection('users').doc(followedUserId).update({
          followerCount: admin.firestore.FieldValue.increment(-1)
        });
        
        count++;
        log(`   - Removed follow relationship with user ${followedUserId}`, 'cyan');
      }
      log(`   ✅ Deleted ${count} following relationships and updated follower counts`, 'green');
    }
    
    // Step 4: Delete followers subcollection AND update follower users
    log('\n📋 Step 4: Deleting follower relationships...', 'blue');
    const followersRef = db.collection('users').doc(userId).collection('followers');
    const followers = await followersRef.get();
    
    if (followers.empty) {
      log('   No follower relationships found', 'yellow');
    } else {
      let count = 0;
      // Process each follower
      for (const doc of followers.docs) {
        const followerUserId = doc.id;
        
        // Delete this user's follower document
        await doc.ref.delete();
        
        // Delete reciprocal following document from the follower
        await db.collection('users').doc(followerUserId).collection('following').doc(userId).delete();
        
        // Decrement follower's followingCount
        await db.collection('users').doc(followerUserId).update({
          followingCount: admin.firestore.FieldValue.increment(-1)
        });
        
        count++;
        log(`   - Removed follower relationship with user ${followerUserId}`, 'cyan');
      }
      log(`   ✅ Deleted ${count} follower relationships and updated following counts`, 'green');
    }
    
    // Step 5: Delete blocked users subcollection (if exists)
    log('\n📋 Step 5: Deleting blocked users...', 'blue');
    const blockedRef = db.collection('users').doc(userId).collection('blocked');
    const blocked = await blockedRef.get();
    
    if (blocked.empty) {
      log('   No blocked users found', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      blocked.forEach(doc => {
        batch.delete(doc.ref);
        count++;
      });
      await batch.commit();
      log(`   ✅ Deleted ${count} blocked users`, 'green');
    }
    
    // Step 6: Delete likes
    log('\n📋 Step 6: Deleting likes...', 'blue');
    const likesQuery = await db.collection('likes').where('userId', '==', userId).get();
    
    if (likesQuery.empty) {
      log('   No likes found', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      likesQuery.forEach(doc => {
        batch.delete(doc.ref);
        count++;
      });
      await batch.commit();
      log(`   ✅ Deleted ${count} likes`, 'green');
    }
    
    // Step 7: Delete comments
    log('\n📋 Step 7: Deleting comments...', 'blue');
    const commentsQuery = await db.collection('comments').where('userId', '==', userId).get();
    
    if (commentsQuery.empty) {
      log('   No comments found', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      commentsQuery.forEach(doc => {
        batch.delete(doc.ref);
        count++;
      });
      await batch.commit();
      log(`   ✅ Deleted ${count} comments`, 'green');
    }
    
    // Step 8: Delete feedback
    log('\n📋 Step 8: Deleting feedback...', 'blue');
    const feedbackQuery = await db.collection('feedback').where('userId', '==', userId).get();
    
    if (feedbackQuery.empty) {
      log('   No feedback found', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      feedbackQuery.forEach(doc => {
        batch.delete(doc.ref);
        count++;
      });
      await batch.commit();
      log(`   ✅ Deleted ${count} feedback entries`, 'green');
    }
    
    // Step 9: Remove user from stamp_statistics
    log('\n📋 Step 9: Removing from stamp statistics...', 'blue');
    const statsQuery = await db.collection('stamp_statistics')
      .where('collectorUserIds', 'array-contains', userId)
      .get();
    
    if (statsQuery.empty) {
      log('   User not found in any stamp statistics', 'yellow');
    } else {
      const batch = db.batch();
      let count = 0;
      statsQuery.forEach(doc => {
        batch.update(doc.ref, {
          collectorUserIds: admin.firestore.FieldValue.arrayRemove(userId),
          totalCollectors: admin.firestore.FieldValue.increment(-1)
        });
        count++;
      });
      await batch.commit();
      log(`   ✅ Removed from ${count} stamp statistics`, 'green');
    }
    
    // Step 10: Free up invite code slot
    log('\n📋 Step 10: Freeing up invite code slot...', 'blue');
    if (userDoc.exists) {
      const userData = userDoc.data();
      const inviteCodeUsed = userData.inviteCodeUsed;
      
      if (inviteCodeUsed) {
        try {
          const inviteCodeRef = db.collection('invite_codes').doc(inviteCodeUsed);
          const inviteCodeDoc = await inviteCodeRef.get();
          
          if (inviteCodeDoc.exists) {
            await inviteCodeRef.update({
              usedCount: admin.firestore.FieldValue.increment(-1),
              usedBy: admin.firestore.FieldValue.arrayRemove(userId)
            });
            log(`   ✅ Freed up slot in invite code: ${inviteCodeUsed}`, 'green');
          } else {
            log(`   ⚠️  Invite code "${inviteCodeUsed}" not found`, 'yellow');
          }
        } catch (error) {
          log(`   ⚠️  Could not update invite code: ${error.message}`, 'yellow');
        }
      } else {
        log('   ⚠️  User has no inviteCodeUsed field', 'yellow');
      }
    }
    
    // Step 11: Delete personal invite code
    log('\n📋 Step 11: Deleting personal invite code...', 'blue');
    if (userDoc.exists) {
      const userData = userDoc.data();
      const personalCode = userData.personalInviteCode;
      
      if (personalCode) {
        try {
          const personalCodeRef = db.collection('invite_codes').doc(personalCode);
          const personalCodeDoc = await personalCodeRef.get();
          
          if (personalCodeDoc.exists) {
            await personalCodeRef.delete();
            log(`   ✅ Deleted personal invite code: ${personalCode}`, 'green');
          } else {
            log(`   ⚠️  Personal invite code "${personalCode}" not found`, 'yellow');
          }
        } catch (error) {
          log(`   ⚠️  Could not delete personal code: ${error.message}`, 'yellow');
        }
      } else {
        log('   ⚠️  User has no personalInviteCode field', 'yellow');
      }
    }
    
    // Step 12: Delete notifications (if collection exists)
    log('\n📋 Step 12: Deleting notifications...', 'blue');
    try {
      const notificationsRef = db.collection('users').doc(userId).collection('notifications');
      const notifications = await notificationsRef.get();
      
      if (notifications.empty) {
        log('   No notifications found', 'yellow');
      } else {
        const batch = db.batch();
        let count = 0;
        notifications.forEach(doc => {
          batch.delete(doc.ref);
          count++;
        });
        await batch.commit();
        log(`   ✅ Deleted ${count} notifications`, 'green');
      }
    } catch (error) {
      log('   ⚠️  Notifications collection not found (may not exist yet)', 'yellow');
    }
    
    // Step 13: Delete Firebase Storage files
    log('\n📋 Step 13: Deleting storage files...', 'blue');
    const [files] = await storage.getFiles({ prefix: `users/${userId}/` });
    
    if (files.length === 0) {
      log('   No storage files found', 'yellow');
    } else {
      let deletedCount = 0;
      for (const file of files) {
        await file.delete();
        deletedCount++;
      }
      log(`   ✅ Deleted ${deletedCount} storage files`, 'green');
    }
    
    // Step 14: Delete user profile document
    log('\n📋 Step 14: Deleting user profile...', 'blue');
    await db.collection('users').doc(userId).delete();
    log('   ✅ User profile deleted', 'green');
    
    // Step 15: Delete Firebase Authentication account
    log('\n📋 Step 15: Deleting authentication account...', 'blue');
    try {
      await auth.deleteUser(userId);
      log('   ✅ Authentication account deleted', 'green');
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        log('   ⚠️  Auth account not found (may have been deleted already)', 'yellow');
      } else {
        throw error;
      }
    }
    
    // Success!
    log('\n========================================', 'green');
    log('  ✅ ACCOUNT DELETION COMPLETE', 'green');
    log('========================================\n', 'green');
    log('The user can now create a fresh account as if they were a new user.\n', 'cyan');
    
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
const userId = process.argv[2];

if (!userId) {
  log('\n❌ Error: No userId provided', 'red');
  log('\nUsage: node delete_user_account.js <userId>', 'yellow');
  log('Example: node delete_user_account.js mpd4k2n13adMFMY52nksmaQTbMQ2\n', 'yellow');
  process.exit(1);
}

deleteUserAccount(userId)
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    log(`\n❌ Unexpected error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  });

