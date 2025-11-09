const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function verifyCollectionCounts() {
  try {
    console.log('\n=== Verifying Collection Stamp Counts ===\n');

    // Get all stamps from Firestore
    const stampsSnapshot = await db.collection('stamps').get();
    console.log(`Total stamps in Firebase: ${stampsSnapshot.size}\n`);

    // Count stamps per collection
    const collectionCounts = {};
    
    stampsSnapshot.forEach(doc => {
      const stamp = doc.data();
      const collectionIds = stamp.collectionIds || [];
      
      collectionIds.forEach(collectionId => {
        if (!collectionCounts[collectionId]) {
          collectionCounts[collectionId] = 0;
        }
        collectionCounts[collectionId]++;
      });
    });

    // Read the local collections.json file
    const fs = require('fs');
    const collectionsData = JSON.parse(
      fs.readFileSync('./Stampbook/Data/collections.json', 'utf8')
    );

    console.log('Collection Count Verification:\n');
    console.log('Collection ID'.padEnd(35), '| Expected', '| Actual', '| Status');
    console.log('-'.repeat(70));

    let hasDiscrepancies = false;

    collectionsData.forEach(collection => {
      const expected = collection.totalStamps;
      const actual = collectionCounts[collection.id] || 0;
      const status = expected === actual ? '✓ OK' : '✗ MISMATCH';
      
      if (expected !== actual) {
        hasDiscrepancies = true;
      }

      console.log(
        collection.id.padEnd(35),
        '|',
        String(expected).padStart(8),
        '|',
        String(actual).padStart(6),
        '|',
        status
      );
    });

    // Check for stamps with collection IDs not in collections.json
    console.log('\n\nChecking for stamps with unknown collection IDs:\n');
    
    const knownCollectionIds = new Set(collectionsData.map(c => c.id));
    const unknownCollectionIds = new Set();
    
    stampsSnapshot.forEach(doc => {
      const stamp = doc.data();
      const collectionIds = stamp.collectionIds || [];
      
      collectionIds.forEach(collectionId => {
        if (!knownCollectionIds.has(collectionId)) {
          unknownCollectionIds.add(collectionId);
        }
      });
    });

    if (unknownCollectionIds.size > 0) {
      console.log('Unknown collection IDs found in stamps:');
      unknownCollectionIds.forEach(id => {
        const count = collectionCounts[id];
        console.log(`  - ${id} (${count} stamp${count !== 1 ? 's' : ''})`);
      });
      hasDiscrepancies = true;
    } else {
      console.log('No unknown collection IDs found. ✓');
    }

    console.log('\n' + '='.repeat(70));
    
    if (hasDiscrepancies) {
      console.log('\n⚠️  DISCREPANCIES FOUND! The totalStamps values need to be updated.\n');
    } else {
      console.log('\n✓ All collection counts are correct!\n');
    }

  } catch (error) {
    console.error('Error verifying collection counts:', error);
  } finally {
    process.exit();
  }
}

verifyCollectionCounts();

