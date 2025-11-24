#!/usr/bin/env node

/**
 * Clean Up Orphaned Comment Notifications
 * 
 * This script finds and deletes notifications for comments that no longer exist
 * (i.e., "Post not found" notifications)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

// ANSI color codes
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

async function cleanupOrphanedCommentNotifications() {
  log('\n========================================', 'cyan');
  log('  ORPHANED COMMENT NOTIFICATIONS CLEANUP', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    // Step 1: Get all comment IDs from comments collection
    log('📋 Step 1: Loading all comments...', 'blue');
    const commentsSnapshot = await db.collection('comments').get();
    const validPostIds = new Set();
    const validCommentData = new Map(); // postId -> Set of {actorId, preview}
    
    commentsSnapshot.forEach(doc => {
      const comment = doc.data();
      const postId = comment.postId;
      const actorId = comment.userId;
      const commentPreview = comment.text.length > 100 
        ? comment.text.substring(0, 100) + '...'
        : comment.text;
      
      validPostIds.add(postId);
      
      if (!validCommentData.has(postId)) {
        validCommentData.set(postId, []);
      }
      validCommentData.get(postId).push({
        actorId,
        preview: commentPreview
      });
    });
    
    log(`   ✅ Found ${validPostIds.size} posts with active comments\n`, 'green');
    
    // Step 2: Get all comment and mention notifications
    log('📋 Step 2: Loading all comment/mention notifications...', 'blue');
    const notificationsSnapshot = await db.collection('notifications')
      .where('type', 'in', ['comment', 'mention'])
      .get();
    
    if (notificationsSnapshot.empty) {
      log('   No comment/mention notifications found', 'yellow');
      process.exit(0);
    }
    
    log(`   ✅ Found ${notificationsSnapshot.size} comment/mention notifications\n`, 'green');
    
    // Step 3: Find orphaned notifications (notifications for deleted comments)
    log('📋 Step 3: Checking for orphaned notifications...', 'blue');
    const orphanedNotifications = [];
    
    notificationsSnapshot.forEach(doc => {
      const notif = doc.data();
      const postId = notif.postId;
      const actorId = notif.actorId;
      const commentPreview = notif.commentPreview;
      
      // Check if this notification's comment still exists
      let commentExists = false;
      
      if (validCommentData.has(postId)) {
        const commentsForPost = validCommentData.get(postId);
        commentExists = commentsForPost.some(c => 
          c.actorId === actorId && c.preview === commentPreview
        );
      }
      
      // If comment doesn't exist, this is an orphaned notification
      if (!commentExists) {
        orphanedNotifications.push({
          id: doc.id,
          type: notif.type,
          recipientId: notif.recipientId || 'N/A',
          actorId: actorId || 'N/A',
          postId: postId || 'N/A',
          preview: commentPreview ? commentPreview.substring(0, 50) + '...' : 'N/A',
          createdAt: notif.createdAt ? notif.createdAt.toDate().toISOString() : 'N/A'
        });
      }
    });
    
    if (orphanedNotifications.length === 0) {
      log('   ✅ No orphaned notifications found! Everything is clean.\n', 'green');
      process.exit(0);
    }
    
    // Step 4: Display orphaned notifications
    log(`   ⚠️  Found ${orphanedNotifications.length} orphaned notification(s):\n`, 'yellow');
    
    orphanedNotifications.forEach((notif, index) => {
      log(`   [${index + 1}] Notification ID: ${notif.id}`, 'cyan');
      log(`       Type: ${notif.type}`, 'cyan');
      log(`       Recipient: ${notif.recipientId}`, 'cyan');
      log(`       Actor: ${notif.actorId}`, 'cyan');
      log(`       Post ID: ${notif.postId}`, 'cyan');
      log(`       Preview: "${notif.preview}"`, 'cyan');
      log(`       Created: ${notif.createdAt}\n`, 'cyan');
    });
    
    // Step 5: Ask for confirmation
    log('========================================', 'yellow');
    log('  READY TO DELETE', 'yellow');
    log('========================================\n', 'yellow');
    log(`This will delete ${orphanedNotifications.length} orphaned notification(s).`, 'yellow');
    log('These are notifications for comments that no longer exist.\n', 'yellow');
    
    // Wait for user input
    const readline = require('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
    
    rl.question('Type "DELETE" to proceed (or anything else to cancel): ', async (answer) => {
      rl.close();
      
      if (answer.trim() !== 'DELETE') {
        log('\n❌ Deletion cancelled by user', 'red');
        process.exit(0);
      }
      
      // Step 6: Delete orphaned notifications
      log('\n🗑️  Deleting orphaned notifications...', 'blue');
      
      const batch = db.batch();
      orphanedNotifications.forEach(notif => {
        const notifRef = db.collection('notifications').doc(notif.id);
        batch.delete(notifRef);
      });
      
      await batch.commit();
      
      log('\n========================================', 'green');
      log('  ✅ CLEANUP COMPLETE', 'green');
      log('========================================', 'green');
      log(`\n${orphanedNotifications.length} orphaned notification(s) removed.`, 'cyan');
      log('Users will no longer see "Post not found" errors.\n', 'cyan');
      
      process.exit(0);
    });
    
  } catch (error) {
    log('\n========================================', 'red');
    log('  ❌ ERROR', 'red');
    log('========================================\n', 'red');
    log(`Error: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  }
}

// Main execution
cleanupOrphanedCommentNotifications();

