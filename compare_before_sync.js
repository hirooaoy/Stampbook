const admin = require('firebase-admin');
const fs = require('fs');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function compareBeforeSync() {
  try {
    console.log('🔍 COMPARING LOCAL CHANGES VS FIRESTORE\n');
    console.log('='  .repeat(80));
    
    // Read local stamps.json
    const stampsPath = './Stampbook/Data/stamps.json';
    const localStamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    // Get stamps from Firestore
    const stampsSnapshot = await db.collection('stamps').get();
    const firebaseStamps = {};
    stampsSnapshot.docs.forEach(doc => {
      firebaseStamps[doc.id] = doc.data();
    });
    
    console.log('\n📊 SUMMARY:');
    console.log(`   Local stamps.json: ${localStamps.length} stamps`);
    console.log(`   Firestore: ${stampsSnapshot.size} stamps`);
    
    // Find stamps that will be DELETED (exist in Firebase but not in local)
    const localIds = new Set(localStamps.map(s => s.id));
    const firebaseIds = new Set(Object.keys(firebaseStamps));
    
    const toDelete = [...firebaseIds].filter(id => !localIds.has(id));
    const toAdd = localStamps.filter(s => !firebaseIds.has(s.id));
    const toUpdate = localStamps.filter(s => firebaseIds.has(s.id));
    
    console.log('\n🔴 STAMPS TO DELETE FROM FIRESTORE:');
    if (toDelete.length === 0) {
      console.log('   ✅ None - safe!');
    } else {
      console.log(`   ⚠️  ${toDelete.length} stamps will be DELETED:`);
      toDelete.forEach(id => {
        const stamp = firebaseStamps[id];
        console.log(`      - ${id}`);
        console.log(`        Name: ${stamp.name}`);
        console.log(`        In collections: ${(stamp.collectionIds || []).join(', ') || 'none'}`);
      });
    }
    
    console.log('\n🟢 NEW STAMPS TO ADD TO FIRESTORE:');
    if (toAdd.length === 0) {
      console.log('   None');
    } else {
      console.log(`   ${toAdd.length} new stamps:`);
      toAdd.forEach(stamp => {
        console.log(`      + ${stamp.id}`);
        console.log(`        Name: ${stamp.name}`);
        console.log(`        In collections: ${(stamp.collectionIds || []).join(', ') || 'none'}`);
      });
    }
    
    console.log('\n🔵 STAMPS TO UPDATE IN FIRESTORE:');
    console.log(`   ${toUpdate.length} stamps will be updated/verified`);
    
    // Special focus on the two we changed
    console.log('\n⭐ FOCUS: The stamps we just changed IDs for:');
    const changedStamps = [
      'us-me-acadia-national-park-beehive-trail-summit',
      'us-me-acadia-national-park-bubble-rock'
    ];
    
    const oldStamps = [
      'us-me-bar-harbor-beehive-trail-summit',
      'us-me-bar-harbor-bubble-rock'
    ];
    
    console.log('\n   NEW IDs (in local stamps.json):');
    changedStamps.forEach(id => {
      const stamp = localStamps.find(s => s.id === id);
      if (stamp) {
        console.log(`      ✅ ${id}`);
        console.log(`         Name: ${stamp.name}`);
        console.log(`         Collections: ${(stamp.collectionIds || []).join(', ')}`);
      } else {
        console.log(`      ❌ ${id} - NOT FOUND IN LOCAL!`);
      }
    });
    
    console.log('\n   OLD IDs (to be deleted from Firestore):');
    oldStamps.forEach(id => {
      if (firebaseStamps[id]) {
        console.log(`      🗑️  ${id}`);
        console.log(`         Name: ${firebaseStamps[id].name}`);
        console.log(`         Collections: ${(firebaseStamps[id].collectionIds || []).join(', ')}`);
      } else {
        console.log(`      ✅ ${id} - already gone from Firestore`);
      }
    });
    
    // Check collections.json
    console.log('\n📚 CHECKING COLLECTIONS:');
    const collectionsSnapshot = await db.collection('collections').get();
    console.log(`   Firestore has ${collectionsSnapshot.size} collections`);
    
    const acadiaCollection = await db.collection('collections').doc('acadia-must-visits').get();
    if (acadiaCollection.exists) {
      const data = acadiaCollection.data();
      console.log('\n   Acadia Must Visits collection:');
      console.log(`      Total stamps: ${data.totalStamps}`);
      console.log('      ℹ️  Note: Collection doesn\'t store stamp IDs, just totalStamps count');
      console.log('      ℹ️  Stamps reference collection via their collectionIds field');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n✨ WHAT WILL HAPPEN WHEN YOU RUN upload_stamps_to_firestore.js:');
    console.log('   1. Delete old IDs from Firestore:');
    oldStamps.forEach(id => console.log(`      - ${id}`));
    console.log('   2. Add new IDs to Firestore:');
    changedStamps.forEach(id => console.log(`      + ${id}`));
    console.log('   3. Update/verify all other stamps remain unchanged');
    console.log('\n⚠️  SAFETY CHECK: Are there any unexpected deletions? ' + 
                (toDelete.length === 2 && toDelete.every(id => oldStamps.includes(id)) ? 
                 '✅ NO - only the 2 expected old IDs' : 
                 `❌ YES - ${toDelete.length} deletions (expected 2)`));
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

compareBeforeSync();

