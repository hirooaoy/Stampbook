const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooStamps() {
  console.log('📋 Checking hiroo\'s collected stamps...\n');
  
  const userId = 'hiroo';
  
  try {
    // Get all collected stamps
    const collectedStampsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('collected_stamps')
      .get();
    
    if (collectedStampsSnapshot.empty) {
      console.log('❌ No stamps found in hiroo\'s collection');
      process.exit(0);
      return;
    }
    
    console.log(`✅ Found ${collectedStampsSnapshot.size} stamp(s) in hiroo's collection:\n`);
    
    collectedStampsSnapshot.docs.forEach((doc, index) => {
      const data = doc.data();
      console.log(`${index + 1}. Stamp ID: ${doc.id}`);
      console.log(`   User ID: ${data.userId}`);
      console.log(`   Collected Date: ${data.collectedDate?.toDate?.() || data.collectedDate}`);
      console.log(`   Notes: ${data.userNotes || '(none)'}`);
      console.log(`   Like Count: ${data.likeCount || 0}`);
      console.log(`   Comment Count: ${data.commentCount || 0}`);
      console.log('');
    });
    
    // Check user profile
    const userDoc = await db.collection('users').doc(userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      console.log(`\n📊 User Profile Stats:`);
      console.log(`   Total Stamps: ${userData.totalStamps || 0}`);
      console.log(`   Username: ${userData.username || 'N/A'}`);
      console.log(`   Display Name: ${userData.displayName || 'N/A'}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

checkHirooStamps();

