const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixLikeCounts() {
  try {
    console.log('🔧 Starting like count reconciliation...\n');
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      console.log(`\n👤 Checking posts for ${userData.displayName || userId}...`);
      
      // Get all collected stamps for this user
      const stampsSnapshot = await db.collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
      
      for (const stampDoc of stampsSnapshot.docs) {
        const stampId = stampDoc.id;
        const stampData = stampDoc.data();
        const postId = `${userId}-${stampId}`;
        
        // Count actual likes in the likes collection
        const likesSnapshot = await db.collection('likes')
          .where('postId', '==', postId)
          .get();
        
        const actualLikeCount = likesSnapshot.size;
        const storedLikeCount = stampData.likeCount || 0;
        
        // Only update if there's a discrepancy
        if (actualLikeCount !== storedLikeCount) {
          console.log(`   📍 ${stampId}`);
          console.log(`      Stored count: ${storedLikeCount}`);
          console.log(`      Actual count: ${actualLikeCount}`);
          console.log(`      ✅ Fixing...`);
          
          await db.collection('users')
            .doc(userId)
            .collection('collected_stamps')
            .doc(stampId)
            .update({
              likeCount: actualLikeCount
            });
          
          console.log(`      ✅ Fixed!`);
        }
      }
    }
    
    console.log('\n✅ Like count reconciliation complete!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

fixLikeCounts();

