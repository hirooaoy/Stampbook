#!/usr/bin/env node

/**
 * Restore Hiroo's Collected Stamps
 * Recreates the 6 stamps that were accidentally deleted
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
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

async function restoreStamps() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo
  
  log('\n========================================', 'cyan');
  log('  RESTORING HIROO\'S STAMPS', 'cyan');
  log('========================================\n', 'cyan');
  
  // The 6 stamps with their storage files
  const stampsToRestore = [
    {
      stampId: 'your-first-stamp',
      name: 'Welcome Stamp',
      userImagePaths: [],
      notes: ''
    },
    {
      stampId: 'us-ca-sf-ballast-coffee',
      name: 'Ballast Coffee',
      userImagePaths: [
        'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-ca-sf-ballast-coffee/us-ca-sf-ballast-coffee_1763001072_24F35E13.jpg',
        'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-ca-sf-ballast-coffee/us-ca-sf-ballast_1762641998_17CD1473.jpg',
        'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-ca-sf-ballast-coffee/us-ca-sf-ballast_1762641998_80C80E39.jpg'
      ],
      notes: ''
    },
    {
      stampId: 'us-ca-sf-powell-hyde-cable-car',
      name: 'Powell-Hyde Cable Car',
      userImagePaths: [],
      notes: ''
    },
    {
      stampId: 'us-ca-sf-dolores-park',
      name: 'Dolores Park',
      userImagePaths: [],
      notes: ''
    },
    {
      stampId: 'us-me-bar-harbor-beals',
      name: "Beal's Lobster Pier",
      userImagePaths: [
        'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-me-bar-harbor-beals/us-me-acadia-beals-lobster-pier_1761977466_D46C5400.jpg'
      ],
      notes: ''
    },
    {
      stampId: 'us-me-bar-harbor-mckays-public-house',
      name: "McKay's Public House",
      userImagePaths: [
        'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-me-bar-harbor-mckays-public-house/us-me-bar-harbor-mckays-public-house_1762466664_87FAA137.jpg'
      ],
      notes: ''
    }
  ];
  
  try {
    // Create all stamps
    for (let i = 0; i < stampsToRestore.length; i++) {
      const stamp = stampsToRestore[i];
      
      log(`📋 ${i + 1}. Creating: ${stamp.name}`, 'blue');
      
      // Create the collected stamp document
      const collectedStampData = {
        stampId: stamp.stampId,
        userId: userId,
        collectedDate: admin.firestore.Timestamp.now(),
        userNotes: stamp.notes,
        userImageNames: [], // Local filenames - not in Firestore
        userImagePaths: stamp.userImagePaths,
        likeCount: 0,
        commentCount: 0,
        userRank: null
      };
      
      await db.collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .doc(stamp.stampId)
        .set(collectedStampData);
      
      log(`   ✅ Created in Firestore`, 'green');
      
      // Update stamp statistics
      const statsRef = db.collection('stamp_statistics').doc(stamp.stampId);
      const statsDoc = await statsRef.get();
      
      if (statsDoc.exists) {
        // Update existing stats
        await statsRef.update({
          collectorUserIds: admin.firestore.FieldValue.arrayUnion(userId),
          totalCollectors: admin.firestore.FieldValue.increment(1),
          lastUpdated: admin.firestore.Timestamp.now()
        });
        log(`   ✅ Updated stamp statistics`, 'green');
      } else {
        // Create new stats
        await statsRef.set({
          stampId: stamp.stampId,
          collectorUserIds: [userId],
          totalCollectors: 1,
          lastUpdated: admin.firestore.Timestamp.now()
        });
        log(`   ✅ Created stamp statistics`, 'green');
      }
    }
    
    // Update user profile totalStamps count
    log('\n📋 Updating user profile...', 'blue');
    await db.collection('users').doc(userId).update({
      totalStamps: stampsToRestore.length
    });
    log('   ✅ Updated totalStamps to 6', 'green');
    
    log('\n========================================', 'green');
    log('  ✅ RESTORATION COMPLETE!', 'green');
    log('========================================\n', 'green');
    log(`Restored ${stampsToRestore.length} stamps to Firestore\n`, 'cyan');
    log('Note: The app may need to refresh to see the changes.', 'yellow');
    log('Pull down to refresh in the Stamps tab.\n', 'yellow');
    
  } catch (error) {
    log('\n❌ Error during restoration:', 'red');
    console.error(error);
    process.exit(1);
  }
}

restoreStamps()
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

