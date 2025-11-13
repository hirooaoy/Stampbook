#!/usr/bin/env node

/**
 * Check Stamp Statistics Accuracy
 * Verifies that stamp collector counts are correct
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

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

async function checkStampStats() {
  log('\n========================================', 'cyan');
  log('  STAMP STATISTICS VERIFICATION', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    // Get all stamp statistics
    const statsSnapshot = await db.collection('stamp_statistics').get();
    
    if (statsSnapshot.empty) {
      log('⚠️  No stamp statistics found', 'yellow');
      return;
    }
    
    log(`📊 Found ${statsSnapshot.size} stamps with statistics\n`, 'blue');
    
    // Get all users' collected stamps to verify counts
    const usersSnapshot = await db.collection('users').get();
    const actualCollections = {}; // stampId -> [userIds]
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const collectedStamps = await db.collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
      
      collectedStamps.forEach(stampDoc => {
        const stampId = stampDoc.id;
        if (!actualCollections[stampId]) {
          actualCollections[stampId] = [];
        }
        actualCollections[stampId].push(userId);
      });
    }
    
    // Check each stamp's statistics
    let correctCount = 0;
    let incorrectCount = 0;
    
    for (const doc of statsSnapshot.docs) {
      const stampId = doc.id;
      const data = doc.data();
      const recordedCount = data.totalCollectors || 0;
      const recordedCollectors = data.collectorUserIds || [];
      
      const actualCollectors = actualCollections[stampId] || [];
      const actualCount = actualCollectors.length;
      
      // Check if counts match
      if (recordedCount === actualCount && recordedCollectors.length === actualCount) {
        log(`✅ ${stampId}`, 'green');
        log(`   Collectors: ${actualCount}`, 'cyan');
        if (actualCount > 0) {
          log(`   Users: ${actualCollectors.join(', ')}`, 'cyan');
        }
        correctCount++;
      } else {
        log(`❌ ${stampId}`, 'red');
        log(`   Recorded count: ${recordedCount}`, 'yellow');
        log(`   Recorded users (${recordedCollectors.length}): ${recordedCollectors.join(', ')}`, 'yellow');
        log(`   Actual count: ${actualCount}`, 'cyan');
        if (actualCount > 0) {
          log(`   Actual users: ${actualCollectors.join(', ')}`, 'cyan');
        }
        incorrectCount++;
      }
      log(''); // blank line
    }
    
    // Summary
    log('========================================', 'cyan');
    log(`✅ Correct: ${correctCount}`, 'green');
    if (incorrectCount > 0) {
      log(`❌ Incorrect: ${incorrectCount}`, 'red');
      log('\n💡 Run fix_stamp_statistics.js to correct these', 'yellow');
    }
    log('========================================\n', 'cyan');
    
  } catch (error) {
    log('\n❌ Error:', 'red');
    console.error(error);
    process.exit(1);
  }
}

checkStampStats()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

