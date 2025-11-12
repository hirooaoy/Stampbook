const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkAllCollections() {
  console.log('\n🔍 Checking entire Firestore database...\n');
  
  // 1. Check stampCollections (feed)
  console.log('1️⃣ /stampCollections (feed posts):');
  const stampCollections = await db.collection('stampCollections').get();
  console.log(`   Total feed posts: ${stampCollections.size}`);
  if (stampCollections.size > 0) {
    console.log('   Sample posts:');
    stampCollections.docs.slice(0, 3).forEach(doc => {
      const data = doc.data();
      console.log(`   - ${data.userName}: collected ${data.stampId}`);
    });
  }
  
  // 2. Check userStampCollections
  console.log('\n2️⃣ /userStampCollections (personal collections):');
  const userCollections = await db.collection('userStampCollections').get();
  console.log(`   Total users: ${userCollections.size}`);
  
  for (const userDoc of userCollections.docs) {
    const collectedStamps = await userDoc.ref.collection('collectedStamps').get();
    console.log(`   - User ${userDoc.id}: ${collectedStamps.size} stamps collected`);
  }
  
  // 3. Check userProfiles
  console.log('\n3️⃣ /userProfiles (user stats):');
  const profiles = await db.collection('userProfiles').get();
  for (const profileDoc of profiles.docs) {
    const profile = profileDoc.data();
    console.log(`   - ${profile.userName || profileDoc.id}: totalStamps = ${profile.totalStamps || 0}`);
  }
  
  // 4. Check stamps
  console.log('\n4️⃣ /stamps:');
  const stamps = await db.collection('stamps').get();
  console.log(`   Total stamps in database: ${stamps.size}`);
  
  // 5. Diagnosis
  console.log('\n📊 DIAGNOSIS:');
  
  if (stampCollections.size === 0 && userCollections.size > 0) {
    // Check if users have collected stamps
    let hasCollected = false;
    for (const userDoc of userCollections.docs) {
      const collectedStamps = await userDoc.ref.collection('collectedStamps').get();
      if (collectedStamps.size > 0) {
        hasCollected = true;
        break;
      }
    }
    
    if (hasCollected) {
      console.log('   ⚠️  POTENTIAL BUG: Users have collected stamps, but no feed posts exist!');
      console.log('   This suggests the feed post creation is not working.');
    } else {
      console.log('   ✅ NORMAL: No one has collected any stamps yet.');
      console.log('   Feed will be created when first stamp is collected.');
    }
  } else if (stampCollections.size > 0) {
    console.log('   ✅ NORMAL: Feed posts exist, everything working as expected.');
  }
  
  console.log('\n');
  process.exit(0);
}

checkAllCollections().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});

