// Check if hiroo has FCM token registered

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooFCMToken() {
  console.log('🔍 Checking hiroo\'s FCM token...\n');
  
  try {
    // Find hiroo's user document
    const usersSnapshot = await db.collection('users')
      .where('username', '==', 'hiroo')
      .limit(1)
      .get();
    
    if (usersSnapshot.empty) {
      console.log('❌ User "hiroo" not found');
      return;
    }
    
    const hirooDoc = usersSnapshot.docs[0];
    const hirooData = hirooDoc.data();
    const hirooId = hirooDoc.id;
    
    console.log(`✅ Found hiroo: ${hirooId}`);
    console.log(`   Username: ${hirooData.username}`);
    console.log(`   Display Name: ${hirooData.displayName}`);
    console.log(`   Email: ${hirooData.email || '(none)'}`);
    console.log();
    
    // Check FCM token
    if (hirooData.fcmToken) {
      console.log('✅ FCM Token exists:');
      console.log(`   Token: ${hirooData.fcmToken.substring(0, 30)}...${hirooData.fcmToken.substring(hirooData.fcmToken.length - 10)}`);
      console.log(`   Token length: ${hirooData.fcmToken.length} characters`);
      
      if (hirooData.fcmTokenUpdatedAt) {
        const updateDate = hirooData.fcmTokenUpdatedAt.toDate();
        const now = new Date();
        const hoursSinceUpdate = (now - updateDate) / (1000 * 60 * 60);
        console.log(`   Last updated: ${updateDate.toLocaleString()} (${hoursSinceUpdate.toFixed(1)} hours ago)`);
      } else {
        console.log('   Last updated: (timestamp not recorded)');
      }
    } else {
      console.log('❌ NO FCM Token found!');
      console.log('   This means hiroo cannot receive push notifications.');
      console.log('   Possible causes:');
      console.log('   1. User denied notification permissions');
      console.log('   2. App was deleted and reinstalled without signing in again');
      console.log('   3. FCM token registration failed');
      console.log('   4. User needs to sign out and sign in again');
    }
    
    console.log();
    console.log('📋 All user fields:');
    console.log(JSON.stringify(hirooData, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

checkHirooFCMToken()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

