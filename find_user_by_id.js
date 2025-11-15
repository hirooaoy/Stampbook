const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function findUserById(userId) {
  console.log(`👤 Looking up user: ${userId}\n`);
  
  try {
    // Get user document
    const userDoc = await db.collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.log('❌ User not found');
      process.exit(0);
      return;
    }
    
    const userData = userDoc.data();
    console.log('✅ User Found:\n');
    console.log(`User ID: ${userId}`);
    console.log(`Username: ${userData.username || 'N/A'}`);
    console.log(`Display Name: ${userData.displayName || 'N/A'}`);
    console.log(`Email: ${userData.email || 'N/A'}`);
    console.log(`Total Stamps: ${userData.totalStamps || 0}`);
    console.log(`Countries: ${userData.countries || 0}`);
    console.log(`Followers: ${userData.followerCount || 0}`);
    console.log(`Following: ${userData.followingCount || 0}`);
    console.log(`Created At: ${userData.createdAt ? new Date(userData.createdAt.seconds * 1000).toLocaleString() : 'N/A'}`);
    
    // Check collected stamps
    const stampsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('collected_stamps')
      .get();
    
    console.log(`\nCollected Stamps: ${stampsSnapshot.size}`);
    
    if (stampsSnapshot.size > 0 && stampsSnapshot.size <= 10) {
      console.log(`\nStamp IDs:`);
      stampsSnapshot.docs.forEach(stampDoc => {
        const stampData = stampDoc.data();
        console.log(`  - ${stampDoc.id} (collected: ${stampData.collectedAt ? new Date(stampData.collectedAt.seconds * 1000).toLocaleDateString() : 'N/A'})`);
      });
    } else if (stampsSnapshot.size > 10) {
      console.log(`\nFirst 10 Stamp IDs:`);
      stampsSnapshot.docs.slice(0, 10).forEach(stampDoc => {
        const stampData = stampDoc.data();
        console.log(`  - ${stampDoc.id} (collected: ${stampData.collectedAt ? new Date(stampData.collectedAt.seconds * 1000).toLocaleDateString() : 'N/A'})`);
      });
      console.log(`  ... and ${stampsSnapshot.size - 10} more`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

const userId = process.argv[2] || 'bVn0nhgGVrQn4NBwlu1HJdCVVe23';
findUserById(userId);

