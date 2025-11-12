const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Reset the test-lottie-animation stamp for testing
 * Removes it from users' collections and fixes their stats
 * Keeps the stamp itself so you can collect it again
 */
async function resetTestStamp() {
  const stampId = 'test-lottie-animation';
  
  console.log('\n🧹 Resetting test stamp...\n');
  
  // Step 1: Delete from users' collected_stamps
  console.log('1️⃣ Removing from user collections (/users/{userId}/collected_stamps)...');
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
        console.log(`   ✅ Removed from ${userData.userName || userDoc.id}'s collection`);
        usersAffected.push({
          id: userDoc.id,
          name: userData.userName || userDoc.id,
          currentTotal: userData.totalStamps || 0
        });
      }
    }
  }
  
  if (usersAffected.length === 0) {
    console.log('   ℹ️  No users had collected this stamp');
  }
  
  // Step 2: Fix user profile stats
  if (usersAffected.length > 0) {
    console.log('\n2️⃣ Fixing user stats (/users)...');
    for (const user of usersAffected) {
      const newTotal = Math.max(0, user.currentTotal - 1);
      await db.collection('users').doc(user.id).update({
        totalStamps: newTotal
      });
      console.log(`   ✅ ${user.name}: ${user.currentTotal} → ${newTotal} stamps`);
    }
  }
  
  // Step 3: Delete statistics
  console.log('\n3️⃣ Deleting stamp statistics (/stamp_statistics)...');
  const statsRef = db.collection('stamp_statistics').doc(stampId);
  const statsDoc = await statsRef.get();
  
  if (statsDoc.exists) {
    await statsRef.delete();
    const stats = statsDoc.data();
    console.log(`   ✅ Deleted statistics (had ${stats.totalCollectors || 0} collectors)`);
  } else {
    console.log('   ℹ️  No statistics found');
  }
  
  console.log('\n✅ Test stamp reset complete!');
  console.log('📍 Stamp location: 690 Guerrero St, San Francisco');
  console.log('ℹ️  The stamp is ready to collect again for testing\n');
  
  process.exit(0);
}

resetTestStamp().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});
