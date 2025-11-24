#!/usr/bin/env node

/**
 * Delete Orphaned Notifications Script
 * This script finds and deletes notifications where the actorId no longer exists in the users collection
 * (i.e., notifications from deleted accounts)
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
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

async function findOrphanedNotifications() {
  log('\n========================================', 'cyan');
  log('  ORPHANED NOTIFICATIONS CHECKER', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    // Step 1: Get all active user IDs
    log('📋 Step 1: Loading all active users...', 'blue');
    const usersSnapshot = await db.collection('users').get();
    const activeUserIds = new Set();
    
    usersSnapshot.forEach(doc => {
      activeUserIds.add(doc.id);
    });
    
    log(`   ✅ Found ${activeUserIds.size} active users\n`, 'green');
    
    // Step 2: Get all notifications from the top-level notifications collection
    log('📋 Step 2: Loading all notifications...', 'blue');
    const notificationsSnapshot = await db.collection('notifications').get();
    
    if (notificationsSnapshot.empty) {
      log('   No notifications found in top-level collection', 'yellow');
      process.exit(0);
    }
    
    log(`   ✅ Found ${notificationsSnapshot.size} total notifications\n`, 'green');
    
    // Step 3: Find orphaned notifications
    log('📋 Step 3: Checking for orphaned notifications...', 'blue');
    const orphanedNotifications = [];
    
    notificationsSnapshot.forEach(doc => {
      const notifData = doc.data();
      const actorId = notifData.actorId;
      
      // Check if actorId exists in active users
      if (actorId && !activeUserIds.has(actorId)) {
        orphanedNotifications.push({
          id: doc.id,
          actorId: actorId,
          recipientId: notifData.recipientId || 'N/A',
          type: notifData.type || 'N/A',
          createdAt: notifData.createdAt ? notifData.createdAt.toDate().toISOString() : 'N/A'
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
      log(`       Actor ID (deleted): ${notif.actorId}`, 'red');
      log(`       Recipient ID: ${notif.recipientId}`, 'cyan');
      log(`       Created: ${notif.createdAt}\n`, 'cyan');
    });
    
    // Step 5: Ask for confirmation
    log('========================================', 'yellow');
    log('  READY TO DELETE', 'yellow');
    log('========================================\n', 'yellow');
    log(`This will delete ${orphanedNotifications.length} notification(s) from deleted accounts.`, 'yellow');
    log('These are "ghost" notifications where the actor no longer exists.\n', 'yellow');
    
    // Wait for user input
    const readline = require('readline');
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });
    
    rl.question('Type "DELETE" to proceed with deletion (or anything else to cancel): ', async (answer) => {
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
      log('  ✅ DELETION COMPLETE', 'green');
      log('========================================', 'green');
      log(`\n${orphanedNotifications.length} orphaned notification(s) have been removed.`, 'cyan');
      log('Users will no longer see notifications from deleted accounts.\n', 'cyan');
      
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
findOrphanedNotifications();

