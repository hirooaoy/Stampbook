const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function deleteTestStampCompletely() {
  const stampId = 'test-lottie-animation';
  
  console.log('\n🗑️  COMPLETELY deleting test stamp...\n');
  console.log('⚠️  This will delete the stamp from Firebase.');
  console.log('⚠️  You\'ll also need to manually remove it from stamps.json\n');
  
  // First, reset all collections
  console.log('Step 1: Cleaning up all collections...');
  
  // Delete feed posts
  const feedPosts = await db.collection('stampCollections')
    .where('stampId', '==', stampId)
    .get();
  for (const doc of feedPosts.docs) {
    await doc.ref.delete();
  }
  console.log(`   ✅ Deleted ${feedPosts.size} feed post(s)`);
  
  // Delete from user collections and fix stats
  const users = await db.collection('users').get();
  let usersAffected = [];
  
  for (const userDoc of users.docs) {
    const collectedStamps = await userDoc.ref
      .collection('collected_stamps')
      .get();
    
    for (const stampDoc of collectedStamps.docs) {
      const stampData = stampDoc.data();
      if (stampData.stampId === stampId) {
        await stampDoc.ref.delete();
        const userData = userDoc.data();
        usersAffected.push({
          id: userDoc.id,
          name: userData.userName || userDoc.id,
          currentTotal: userData.totalStamps || 0
        });
      }
    }
  }
  console.log(`   ✅ Removed from ${usersAffected.length} user collection(s)`);
  
  // Fix user stats
  for (const user of usersAffected) {
    const newTotal = Math.max(0, user.currentTotal - 1);
    await db.collection('users').doc(user.id).update({
      totalStamps: newTotal
    });
    console.log(`   ✅ ${user.name}: ${user.currentTotal} → ${newTotal} stamps`);
  }
  
  // Delete statistics
  await db.collection('stampStatistics').doc(stampId).delete();
  console.log('   ✅ Deleted statistics');
  
  // Delete the stamp itself
  console.log('\nStep 2: Deleting stamp document...');
  await db.collection('stamps').doc(stampId).delete();
  console.log('   ✅ Deleted stamp from /stamps');
  
  console.log('\n✅ Test stamp completely deleted from Firebase!');
  console.log('\n📝 TODO: Remove from stamps.json:');
  console.log('   1. Open Stampbook/Data/stamps.json');
  console.log('   2. Delete the test-lottie-animation entry (last stamp in array)');
  console.log('   3. Run: node upload_stamps_to_firestore.js');
  console.log('\n');
  
  process.exit(0);
}

deleteTestStampCompletely().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});

