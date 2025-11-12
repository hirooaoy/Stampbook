const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkTestStampData() {
  console.log('\n🔍 Checking test stamp data...\n');
  
  // 1. Check stamp exists
  console.log('1️⃣ Stamp document:');
  const stampDoc = await db.collection('stamps').doc('test-lottie-animation').get();
  console.log(stampDoc.exists ? '   ✅ EXISTS' : '   ❌ NOT FOUND');
  
  // 2. Check feed posts
  console.log('\n2️⃣ Feed posts (/stampCollections):');
  const feedPosts = await db.collection('stampCollections')
    .where('stampId', '==', 'test-lottie-animation')
    .get();
  console.log(`   Found ${feedPosts.size} feed post(s)`);
  feedPosts.forEach(doc => {
    const data = doc.data();
    console.log(`   - Post ID: ${doc.id}`);
    console.log(`     User: ${data.userId} (${data.userName})`);
    console.log(`     Date: ${data.collectedDate?.toDate()}`);
  });
  
  // 3. Check collected stamps in user collections
  console.log('\n3️⃣ User collection records (/userStampCollections):');
  const userCollections = await db.collection('userStampCollections').get();
  let foundInCollections = 0;
  for (const userDoc of userCollections.docs) {
    const collectedStamps = await userDoc.ref
      .collection('collectedStamps')
      .where('stampId', '==', 'test-lottie-animation')
      .get();
    
    if (!collectedStamps.empty) {
      foundInCollections++;
      console.log(`   - User: ${userDoc.id}`);
      collectedStamps.forEach(stamp => {
        const data = stamp.data();
        console.log(`     Collection ID: ${stamp.id}`);
        console.log(`     Date: ${data.collectedDate?.toDate()}`);
        console.log(`     Rank: ${data.userRank || 'N/A'}`);
      });
    }
  }
  if (foundInCollections === 0) {
    console.log('   ❌ NOT FOUND in any user collections');
  }
  
  // 4. Check statistics
  console.log('\n4️⃣ Stamp statistics (/stampStatistics):');
  const statsDoc = await db.collection('stampStatistics').doc('test-lottie-animation').get();
  if (statsDoc.exists) {
    const stats = statsDoc.data();
    console.log('   ✅ EXISTS');
    console.log(`   Total collectors: ${stats.totalCollectors || 0}`);
  } else {
    console.log('   ❌ NOT FOUND (will be created when first collected)');
  }
  
  // 5. Check user profiles for stamp counts
  console.log('\n5️⃣ User profiles with this stamp:');
  const profiles = await db.collection('userProfiles').get();
  let foundInProfiles = 0;
  for (const profileDoc of profiles.docs) {
    const profile = profileDoc.data();
    // Check if user has collected this stamp by looking at their collection
    const userCollectedStamps = await db.collection('userStampCollections')
      .doc(profileDoc.id)
      .collection('collectedStamps')
      .where('stampId', '==', 'test-lottie-animation')
      .get();
    
    if (!userCollectedStamps.empty) {
      foundInProfiles++;
      console.log(`   - User: ${profile.userName || profileDoc.id}`);
      console.log(`     Total stamps: ${profile.totalStamps || 0}`);
      console.log(`     Country count: ${profile.countryCount || 0}`);
    }
  }
  if (foundInProfiles === 0) {
    console.log('   ❌ No users have collected this stamp yet');
  }
  
  console.log('\n✅ Check complete!\n');
  process.exit(0);
}

checkTestStampData().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});

