const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function findAllUsers() {
  console.log('👥 Finding all users...\n');
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found');
      process.exit(0);
      return;
    }
    
    console.log(`✅ Found ${usersSnapshot.size} user(s):\n`);
    
    for (const doc of usersSnapshot.docs) {
      const userData = doc.data();
      console.log(`User ID: ${doc.id}`);
      console.log(`  Username: ${userData.username || 'N/A'}`);
      console.log(`  Display Name: ${userData.displayName || 'N/A'}`);
      console.log(`  Total Stamps: ${userData.totalStamps || 0}`);
      
      // Check how many stamps in their collection
      const stampsSnapshot = await db
        .collection('users')
        .doc(doc.id)
        .collection('collected_stamps')
        .get();
      
      console.log(`  Collected Stamps: ${stampsSnapshot.size}`);
      
      if (stampsSnapshot.size > 0) {
        console.log(`  Stamp IDs:`);
        stampsSnapshot.docs.forEach(stampDoc => {
          console.log(`    - ${stampDoc.id}`);
        });
      }
      
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

findAllUsers();

