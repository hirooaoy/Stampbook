#!/usr/bin/env node

/**
 * Complete User Data Audit Script
 * Shows ALL data associated with a user across all collections
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();
const storage = admin.storage().bucket();

const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

async function auditUserData(userId) {
  log('\n========================================', 'cyan');
  log('  COMPLETE USER DATA AUDIT', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    // 1. User Profile
    log('📋 1. USER PROFILE', 'blue');
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const data = userDoc.data();
      log(`   ✅ Profile exists`, 'green');
      log(`      Username: @${data.username}`, 'cyan');
      log(`      Display Name: ${data.displayName}`, 'cyan');
      log(`      Bio: ${data.bio || '(empty)'}`, 'cyan');
      log(`      Total Stamps: ${data.totalStamps}`, 'cyan');
      log(`      Followers: ${data.followerCount}`, 'cyan');
      log(`      Following: ${data.followingCount}`, 'cyan');
    } else {
      log(`   ❌ Profile NOT found`, 'red');
    }
    
    // 2. Collected Stamps (subcollection)
    log('\n📋 2. COLLECTED STAMPS (users/{userId}/collectedStamps)', 'blue');
    const collectedStamps = await db.collection('users').doc(userId).collection('collectedStamps').get();
    if (collectedStamps.empty) {
      log(`   ⚠️  No collected stamps found`, 'yellow');
    } else {
      log(`   ✅ Found ${collectedStamps.size} collected stamps:`, 'green');
      collectedStamps.forEach(doc => {
        const data = doc.data();
        log(`      - ${doc.id}: ${data.collectedDate?.toDate?.() || 'N/A'}`, 'cyan');
      });
    }
    
    // 3. Following
    log('\n📋 3. FOLLOWING (users/{userId}/following)', 'blue');
    const following = await db.collection('users').doc(userId).collection('following').get();
    if (following.empty) {
      log(`   ⚠️  Not following anyone`, 'yellow');
    } else {
      log(`   ✅ Following ${following.size} users:`, 'green');
      following.forEach(doc => {
        log(`      - ${doc.id}`, 'cyan');
      });
    }
    
    // 4. Followers
    log('\n📋 4. FOLLOWERS (users/{userId}/followers)', 'blue');
    const followers = await db.collection('users').doc(userId).collection('followers').get();
    if (followers.empty) {
      log(`   ⚠️  No followers`, 'yellow');
    } else {
      log(`   ✅ ${followers.size} followers:`, 'green');
      followers.forEach(doc => {
        log(`      - ${doc.id}`, 'cyan');
      });
    }
    
    // 5. Blocked Users
    log('\n📋 5. BLOCKED USERS (users/{userId}/blocked)', 'blue');
    const blocked = await db.collection('users').doc(userId).collection('blocked').get();
    if (blocked.empty) {
      log(`   ⚠️  No blocked users`, 'yellow');
    } else {
      log(`   ✅ ${blocked.size} blocked users`, 'green');
    }
    
    // 6. Likes
    log('\n📋 6. LIKES (likes collection)', 'blue');
    const likes = await db.collection('likes').where('userId', '==', userId).get();
    if (likes.empty) {
      log(`   ⚠️  No likes found`, 'yellow');
    } else {
      log(`   ✅ ${likes.size} likes`, 'green');
    }
    
    // 7. Comments
    log('\n📋 7. COMMENTS (comments collection)', 'blue');
    const comments = await db.collection('comments').where('userId', '==', userId).get();
    if (comments.empty) {
      log(`   ⚠️  No comments found`, 'yellow');
    } else {
      log(`   ✅ ${comments.size} comments`, 'green');
    }
    
    // 8. Feedback
    log('\n📋 8. FEEDBACK (feedback collection)', 'blue');
    const feedback = await db.collection('feedback').where('userId', '==', userId).get();
    if (feedback.empty) {
      log(`   ⚠️  No feedback found`, 'yellow');
    } else {
      log(`   ✅ ${feedback.size} feedback entries`, 'green');
    }
    
    // 9. Stamp Statistics (where user is a collector)
    log('\n📋 9. STAMP STATISTICS (stamps where user is collector)', 'blue');
    const stats = await db.collection('stamp_statistics')
      .where('collectorUserIds', 'array-contains', userId)
      .get();
    if (stats.empty) {
      log(`   ⚠️  Not listed as collector for any stamps`, 'yellow');
    } else {
      log(`   ✅ Listed as collector for ${stats.size} stamps`, 'green');
    }
    
    // 10. Feed Posts (if using separate feed_posts collection)
    log('\n📋 10. FEED POSTS (feed_posts collection)', 'blue');
    try {
      const feedPosts = await db.collection('feed_posts').where('userId', '==', userId).get();
      if (feedPosts.empty) {
        log(`   ⚠️  No feed posts found`, 'yellow');
      } else {
        log(`   ✅ ${feedPosts.size} feed posts:`, 'green');
        feedPosts.forEach(doc => {
          const data = doc.data();
          log(`      - ${doc.id}: ${data.stampId || 'N/A'} (${data.timestamp?.toDate?.() || 'N/A'})`, 'cyan');
        });
      }
    } catch (error) {
      log(`   ⚠️  Feed posts collection may not exist yet`, 'yellow');
    }
    
    // 11. Notifications
    log('\n📋 11. NOTIFICATIONS (users/{userId}/notifications)', 'blue');
    try {
      const notifications = await db.collection('users').doc(userId).collection('notifications').get();
      if (notifications.empty) {
        log(`   ⚠️  No notifications`, 'yellow');
      } else {
        log(`   ✅ ${notifications.size} notifications`, 'green');
      }
    } catch (error) {
      log(`   ⚠️  Notifications subcollection may not exist yet`, 'yellow');
    }
    
    // 12. Firebase Storage Files
    log('\n📋 12. FIREBASE STORAGE FILES', 'blue');
    const [files] = await storage.getFiles({ prefix: `users/${userId}/` });
    if (files.length === 0) {
      log(`   ⚠️  No storage files found`, 'yellow');
    } else {
      log(`   ✅ ${files.length} storage files:`, 'green');
      files.forEach(file => {
        log(`      - ${file.name}`, 'cyan');
      });
    }
    
    // 13. Firebase Authentication
    log('\n📋 13. FIREBASE AUTHENTICATION', 'blue');
    try {
      const auth = admin.auth();
      const userRecord = await auth.getUser(userId);
      log(`   ✅ Auth account exists`, 'green');
      log(`      Email: ${userRecord.email || 'N/A'}`, 'cyan');
      log(`      Provider: ${userRecord.providerData[0]?.providerId || 'N/A'}`, 'cyan');
      log(`      Created: ${userRecord.metadata.creationTime}`, 'cyan');
      log(`      Last Sign In: ${userRecord.metadata.lastSignInTime}`, 'cyan');
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        log(`   ❌ Auth account NOT found`, 'red');
      } else {
        throw error;
      }
    }
    
    log('\n========================================', 'cyan');
    log('  AUDIT COMPLETE', 'cyan');
    log('========================================\n', 'cyan');
    
  } catch (error) {
    log('\n❌ Error during audit:', 'red');
    console.error(error);
    process.exit(1);
  }
}

const userId = process.argv[2];

if (!userId) {
  log('\n❌ Error: No userId provided', 'red');
  log('\nUsage: node audit_user_data.js <userId>', 'yellow');
  log('Example: node audit_user_data.js mpd4k2n13adMFMY52nksmaQTbMQ2\n', 'yellow');
  process.exit(1);
}

auditUserData(userId)
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    log(`\n❌ Unexpected error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  });

