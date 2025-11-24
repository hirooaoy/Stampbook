const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');
const fs = require('fs');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

// Get stamp ID from command line
const stampIdToRemove = process.argv[2];

if (!stampIdToRemove) {
  console.log('❌ Usage: node remove_duplicate_stamp.js <stamp-id>');
  console.log('\nExample: node remove_duplicate_stamp.js us-california-south-lake-tahoe-heavenly-2');
  process.exit(1);
}

async function removeDuplicateStamp() {
  console.log(`🔍 Checking stamp: ${stampIdToRemove}\n`);
  
  // Step 1: Fetch the stamp from Firebase
  const stampRef = db.collection('stamps').doc(stampIdToRemove);
  const stampDoc = await stampRef.get();
  
  if (!stampDoc.exists) {
    console.log('❌ Stamp not found in Firebase');
    process.exit(1);
  }
  
  const stampData = stampDoc.data();
  console.log('Found stamp:');
  console.log(`  Name: ${stampData.name}`);
  console.log(`  Location: ${stampData.city}, ${stampData.state}`);
  console.log(`  GPS: ${stampData.latitude}, ${stampData.longitude}`);
  
  // Step 2: Check if anyone has collected it
  const collectorsSnapshot = await db.collectionGroup('collectedStamps')
    .where('stampId', '==', stampIdToRemove)
    .get();
  
  console.log(`\n📊 Collection status: ${collectorsSnapshot.size} user(s) have collected this stamp`);
  
  if (collectorsSnapshot.size > 0) {
    console.log('\n⚠️  WARNING: This stamp has been collected by users!');
    console.log('Collectors:');
    collectorsSnapshot.forEach(doc => {
      const userId = doc.ref.parent.parent.id;
      const collectedDate = doc.data().collectedDate?.toDate();
      console.log(`  - User: ${userId}, Collected: ${collectedDate}`);
    });
    
    console.log('\n❌ CANNOT DELETE: Stamp has collectors.');
    console.log('💡 Solution: Keep this stamp and delete the UNCOLLECTED duplicate instead.');
    process.exit(1);
  }
  
  // Step 3: Check if it's in any collections
  if (stampData.collectionIds && stampData.collectionIds.length > 0) {
    console.log(`\n📚 Part of ${stampData.collectionIds.length} collection(s):`);
    stampData.collectionIds.forEach(id => console.log(`  - ${id}`));
  }
  
  // Step 4: Check stamp statistics
  const statsRef = db.collection('stamp_statistics').doc(stampIdToRemove);
  const statsDoc = await statsRef.get();
  const hasStats = statsDoc.exists;
  
  if (hasStats) {
    const stats = statsDoc.data();
    console.log(`\n📈 Statistics: ${stats.totalCollectors || 0} total collectors`);
  }
  
  // Step 5: Remove from local stamps.json
  const stampsJsonPath = './Stampbook/Data/stamps.json';
  const stampsJson = JSON.parse(fs.readFileSync(stampsJsonPath, 'utf8'));
  const originalCount = stampsJson.length;
  const filteredStamps = stampsJson.filter(s => s.id !== stampIdToRemove);
  
  if (originalCount === filteredStamps.length) {
    console.log('\n⚠️  Stamp not found in local stamps.json');
  } else {
    console.log('\n✅ Found stamp in local stamps.json');
  }
  
  // Step 6: Confirm deletion
  console.log('\n' + '='.repeat(60));
  console.log('⚠️  READY TO DELETE DUPLICATE STAMP');
  console.log('='.repeat(60));
  console.log('This will:');
  console.log('  1. Delete stamp from Firebase stamps collection');
  if (hasStats) {
    console.log('  2. Delete stamp statistics from Firebase');
  }
  if (originalCount !== filteredStamps.length) {
    console.log('  3. Remove from local stamps.json');
  }
  console.log('\n❓ To confirm, run:');
  console.log(`   node remove_duplicate_stamp.js ${stampIdToRemove} --confirm`);
  console.log('='.repeat(60));
  
  // Check for --confirm flag
  if (!process.argv.includes('--confirm')) {
    console.log('\n⏸️  Dry run complete. Use --confirm to execute.');
    process.exit(0);
  }
  
  // Step 7: Execute deletion
  console.log('\n🗑️  DELETING STAMP...\n');
  
  // Delete from Firebase
  await stampRef.delete();
  console.log('✅ Deleted from Firebase stamps collection');
  
  // Delete statistics if exists
  if (hasStats) {
    await statsRef.delete();
    console.log('✅ Deleted stamp statistics');
  }
  
  // Remove from local JSON
  if (originalCount !== filteredStamps.length) {
    fs.writeFileSync(stampsJsonPath, JSON.stringify(filteredStamps, null, 2));
    console.log('✅ Removed from local stamps.json');
  }
  
  // Step 8: Update collection counts if needed
  if (stampData.collectionIds && stampData.collectionIds.length > 0) {
    console.log('\n📚 Updating collection counts...');
    for (const collectionId of stampData.collectionIds) {
      const collectionRef = db.collection('collections').doc(collectionId);
      const collectionDoc = await collectionRef.get();
      
      if (collectionDoc.exists) {
        const currentTotal = collectionDoc.data().totalStamps || 0;
        const newTotal = Math.max(0, currentTotal - 1);
        await collectionRef.update({ totalStamps: newTotal });
        console.log(`  ✅ Updated ${collectionId}: ${currentTotal} → ${newTotal} stamps`);
      }
    }
  }
  
  console.log('\n✅ DUPLICATE STAMP REMOVED SUCCESSFULLY');
  console.log('\n💡 Next steps:');
  console.log('   1. Run: node upload_stamps_to_firestore.js (to sync collections to Firebase)');
  console.log('   2. Delete/reinstall app to clear cache on your device');
  
  process.exit(0);
}

removeDuplicateStamp().catch(console.error);

