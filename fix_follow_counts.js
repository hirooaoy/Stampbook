const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixFollowCounts() {
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo
  
  console.log('🔧 Fixing follow counts for user:', userId);
  console.log('');
  
  // 1. Get user profile
  const userDoc = await db.collection('users').doc(userId).get();
  const userData = userDoc.data();
  console.log(`Current profile: followers=${userData.followerCount || 0}, following=${userData.followingCount || 0}`);
  console.log('');
  
  // 2. Count actual following
  console.log('📊 Counting actual data...');
  const followingSnapshot = await db
    .collection('users')
    .doc(userId)
    .collection('following')
    .get();
  
  const actualFollowing = followingSnapshot.size;
  console.log(`   Following: ${actualFollowing} users`);
  
  // 3. Count actual followers by checking other users
  console.log('   Checking followers...');
  let actualFollowers = 0;
  const usersSnapshot = await db.collection('users').get();
  
  for (const userDoc of usersSnapshot.docs) {
    const followingDoc = await db
      .collection('users')
      .doc(userDoc.id)
      .collection('following')
      .doc(userId)
      .get();
    
    if (followingDoc.exists) {
      actualFollowers++;
      const followerData = userDoc.data();
      console.log(`      → @${followerData.username} follows you`);
    }
  }
  
  console.log(`   Followers: ${actualFollowers} users`);
  console.log('');
  
  // 4. Update profile if needed
  if (actualFollowers !== userData.followerCount || actualFollowing !== userData.followingCount) {
    console.log('⚠️  Mismatch detected!');
    console.log(`   Profile says: followers=${userData.followerCount || 0}, following=${userData.followingCount || 0}`);
    console.log(`   Actual data: followers=${actualFollowers}, following=${actualFollowing}`);
    console.log('');
    console.log('🔄 Updating profile...');
    
    await db.collection('users').doc(userId).update({
      followerCount: actualFollowers,
      followingCount: actualFollowing,
      lastActiveAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    console.log('✅ Profile updated!');
    console.log(`   New counts: followers=${actualFollowers}, following=${actualFollowing}`);
  } else {
    console.log('✅ Counts are already correct!');
  }
}

fixFollowCounts()
  .then(() => {
    console.log('\n✅ Done');
    process.exit(0);
  })
  .catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
  });

