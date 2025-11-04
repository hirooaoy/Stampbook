const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkFollowData() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo
  
  console.log('🔍 Checking follow data for user:', userId);
  console.log('');
  
  // 1. Check user profile
  console.log('1️⃣ User Profile:');
  const userDoc = await db.collection('users').doc(userId).get();
  if (userDoc.exists) {
    const data = userDoc.data();
    console.log(`   Username: @${data.username}`);
    console.log(`   Display Name: ${data.displayName}`);
    console.log(`   Follower Count (in profile): ${data.followerCount || 0}`);
    console.log(`   Following Count (in profile): ${data.followingCount || 0}`);
  }
  console.log('');
  
  // 2. Check who this user is following
  console.log('2️⃣ Following (who this user follows):');
  const followingSnapshot = await db
    .collection('users')
    .doc(userId)
    .collection('following')
    .get();
  
  if (followingSnapshot.empty) {
    console.log('   ❌ Not following anyone');
  } else {
    console.log(`   ✅ Following ${followingSnapshot.size} users:`);
    for (const doc of followingSnapshot.docs) {
      const followeeId = doc.id;
      const followeeDoc = await db.collection('users').doc(followeeId).get();
      if (followeeDoc.exists) {
        const followeeData = followeeDoc.data();
        console.log(`      - @${followeeData.username} (${followeeData.displayName})`);
      } else {
        console.log(`      - ${followeeId} (user not found)`);
      }
    }
  }
  console.log('');
  
  // 3. Check who follows this user (collectionGroup query)
  console.log('3️⃣ Followers (who follows this user):');
  const followersSnapshot = await db
    .collectionGroup('following')
    .where('id', '==', userId)
    .get();
  
  if (followersSnapshot.empty) {
    console.log('   ❌ No followers');
  } else {
    console.log(`   ✅ ${followersSnapshot.size} followers:`);
    for (const doc of followersSnapshot.docs) {
      // Extract follower userId from path: users/{followerId}/following/{followeeId}
      const pathParts = doc.ref.path.split('/');
      const followerId = pathParts[1];
      
      const followerDoc = await db.collection('users').doc(followerId).get();
      if (followerDoc.exists) {
        const followerData = followerDoc.data();
        console.log(`      - @${followerData.username} (${followerData.displayName})`);
      } else {
        console.log(`      - ${followerId} (user not found)`);
      }
    }
  }
  console.log('');
  
  // 4. Summary
  console.log('📊 Summary:');
  console.log(`   Profile says: ${userDoc.data().followerCount || 0} followers, ${userDoc.data().followingCount || 0} following`);
  console.log(`   Actual data: ${followersSnapshot.size} followers, ${followingSnapshot.size} following`);
  
  if (followersSnapshot.size !== (userDoc.data().followerCount || 0) || 
      followingSnapshot.size !== (userDoc.data().followingCount || 0)) {
    console.log('   ⚠️  MISMATCH DETECTED! Profile counts are wrong.');
    console.log('');
    console.log('🔧 Fix: Run profile refresh or manually update counts.');
  } else {
    console.log('   ✅ Profile counts are correct!');
  }
}

checkFollowData()
  .then(() => {
    console.log('\n✅ Check complete');
    process.exit(0);
  })
  .catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
  });

