const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Check if already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();
const auth = admin.auth();

async function verifyHirooAccount() {
  try {
    console.log('🔍 Checking hiroo account status...\n');
    
    // Check Firestore profile
    const usersSnapshot = await db.collection('users').get();
    let hirooProfile = null;
    
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      if (data.username === 'hiroo') {
        hirooProfile = {
          userId: doc.id,
          ...data
        };
        break;
      }
    }
    
    if (hirooProfile) {
      console.log('✅ HIROO FIRESTORE PROFILE EXISTS:');
      console.log(`   userId: ${hirooProfile.userId}`);
      console.log(`   username: ${hirooProfile.username}`);
      console.log(`   displayName: ${hirooProfile.displayName}`);
      console.log(`   totalStamps: ${hirooProfile.totalStamps}`);
      console.log(`   followerCount: ${hirooProfile.followerCount}`);
      console.log(`   followingCount: ${hirooProfile.followingCount}`);
      
      // Check Auth account
      try {
        const authUser = await auth.getUser(hirooProfile.userId);
        console.log('\n✅ HIROO AUTH ACCOUNT EXISTS:');
        console.log(`   email: ${authUser.email}`);
        console.log(`   created: ${authUser.metadata.creationTime}`);
        console.log(`   lastSignIn: ${authUser.metadata.lastSignInTime}`);
      } catch (authError) {
        console.log('\n❌ HIROO AUTH ACCOUNT NOT FOUND');
        console.log(`   Error: ${authError.message}`);
      }
      
      // Check collected stamps
      const collectedStamps = await db.collection('users')
        .doc(hirooProfile.userId)
        .collection('collectedStamps')
        .get();
      console.log(`\n📊 Collected stamps: ${collectedStamps.size}`);
      
    } else {
      console.log('❌ HIROO PROFILE NOT FOUND IN FIRESTORE');
    }
    
    console.log('\n' + '='.repeat(50));
    console.log('ACCOUNT STATUS: ' + (hirooProfile ? '✅ INTACT' : '❌ DELETED'));
    console.log('='.repeat(50));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

verifyHirooAccount();

