#!/usr/bin/env node

/**
 * Check Collected Stamp Photos
 * Verifies that user photos are attached to collected stamps
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

async function checkStampPhotos() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo
  
  log('\n========================================', 'cyan');
  log('  CHECKING COLLECTED STAMP PHOTOS', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    const collectedStamps = await db.collection('users')
      .doc(userId)
      .collection('collectedStamps')
      .get();
    
    if (collectedStamps.empty) {
      log('⚠️  No collected stamps found', 'yellow');
      return;
    }
    
    log(`📊 Found ${collectedStamps.size} collected stamps\n`, 'blue');
    
    collectedStamps.forEach(doc => {
      const data = doc.data();
      const stampId = doc.id;
      
      log(`📋 ${stampId}`, 'blue');
      log(`   Stamp ID: ${data.stampId}`, 'cyan');
      log(`   User Notes: "${data.userNotes || '(empty)'}"`, 'cyan');
      log(`   User Image Names: [${data.userImageNames?.length || 0}]`, 'cyan');
      if (data.userImageNames && data.userImageNames.length > 0) {
        data.userImageNames.forEach(name => {
          log(`     - ${name}`, 'cyan');
        });
      }
      log(`   User Image Paths: [${data.userImagePaths?.length || 0}]`, 'cyan');
      if (data.userImagePaths && data.userImagePaths.length > 0) {
        data.userImagePaths.forEach(path => {
          log(`     - ${path}`, data.userImagePaths.length > 0 ? 'green' : 'yellow');
        });
      } else {
        log(`     (no photos)`, 'yellow');
      }
      log(`   Like Count: ${data.likeCount || 0}`, 'cyan');
      log(`   Comment Count: ${data.commentCount || 0}`, 'cyan');
      log('');
    });
    
    log('========================================\n', 'cyan');
    
  } catch (error) {
    log('\n❌ Error:', 'red');
    console.error(error);
    process.exit(1);
  }
}

checkStampPhotos()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

