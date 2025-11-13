#!/usr/bin/env node

/**
 * Fix User Image Names
 * Generates userImageNames from userImagePaths so photos show in feed
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');
const path = require('path');

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

async function fixUserImageNames() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo
  
  log('\n========================================', 'cyan');
  log('  FIXING USER IMAGE NAMES', 'cyan');
  log('========================================\n', 'cyan');
  
  try {
    const collectedStamps = await db.collection('users')
      .doc(userId)
      .collection('collectedStamps')
      .get();
    
    for (const doc of collectedStamps.docs) {
      const data = doc.data();
      const stampId = doc.id;
      const userImagePaths = data.userImagePaths || [];
      
      if (userImagePaths.length === 0) {
        log(`⏭️  ${stampId} - No photos, skipping`, 'yellow');
        continue;
      }
      
      log(`📋 ${stampId}`, 'blue');
      log(`   Found ${userImagePaths.length} photo paths`, 'cyan');
      
      // Extract filenames from paths
      // Path format: users/{userId}/stamps/{stampId}/{filename}.jpg
      const userImageNames = userImagePaths.map(photoPath => {
        const filename = path.basename(photoPath);
        log(`   - ${filename}`, 'cyan');
        return filename;
      });
      
      // Update the document
      await doc.ref.update({
        userImageNames: userImageNames
      });
      
      log(`   ✅ Updated userImageNames`, 'green');
      log('');
    }
    
    log('========================================', 'green');
    log('  ✅ FIX COMPLETE!', 'green');
    log('========================================\n', 'green');
    log('Photos should now appear in the feed.\n', 'cyan');
    log('Pull down to refresh in the app to sync changes.\n', 'yellow');
    
  } catch (error) {
    log('\n❌ Error:', 'red');
    console.error(error);
    process.exit(1);
  }
}

fixUserImageNames()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

