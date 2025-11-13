const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixHirooFollowerCount() {
  try {
    console.log('🔧 Fixing hiroo follower count...\n');
    
    // Find hiroo's userId
    const usersSnapshot = await db.collection('users').get();
    let hirooUserId = null;
    
    for (const doc of usersSnapshot.docs) {
      const data = doc.data();
      if (data.username === 'hiroo') {
        hirooUserId = doc.id;
        break;
      }
    }
    
    if (!hirooUserId) {
      console.log('❌ hiroo user not found');
      return;
    }
    
    console.log(`✅ Found hiroo: ${hirooUserId}`);
    
    // Update profile followerCount to 0
    await db.collection('users').doc(hirooUserId).update({
      followerCount: 0
    });
    
    console.log('✅ Updated hiroo\'s followerCount to 0');
    
    // Verify the fix
    const updatedProfile = await db.collection('users').doc(hirooUserId).get();
    console.log('\n📊 Verification:');
    console.log(`   Profile followerCount: ${updatedProfile.data().followerCount}`);
    console.log(`   Profile followingCount: ${updatedProfile.data().followingCount}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

fixHirooFollowerCount();

