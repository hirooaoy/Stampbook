const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixCommentCounts() {
  console.log('🔧 Starting comment count fix...\n');
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    let totalFixed = 0;
    let totalChecked = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userProfile = userDoc.data();
      console.log(`\n👤 Checking user: ${userProfile.username} (${userId})`);
      
      // Get all collected stamps for this user
      const stampsSnapshot = await db.collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
      
      for (const stampDoc of stampsSnapshot.docs) {
        const stampId = stampDoc.id;
        const stampData = stampDoc.data();
        const cachedCount = stampData.commentCount || 0;
        
        // Fetch actual comment count from comments collection
        const postId = `${userId}-${stampId}`;
        const commentsSnapshot = await db.collection('comments')
          .where('postId', '==', postId)
          .get();
        
        const actualCount = commentsSnapshot.size;
        totalChecked++;
        
        if (cachedCount !== actualCount) {
          console.log(`  ⚠️  ${stampData.stampName || stampId}:`);
          console.log(`      Cached: ${cachedCount}, Actual: ${actualCount}`);
          console.log(`      PostId: ${postId}`);
          
          // Fix the count
          await db.collection('users')
            .doc(userId)
            .collection('collected_stamps')
            .doc(stampId)
            .update({
              commentCount: actualCount
            });
          
          console.log(`      ✅ Fixed!`);
          totalFixed++;
        }
      }
    }
    
    console.log(`\n✅ Complete!`);
    console.log(`   Checked: ${totalChecked} stamps`);
    console.log(`   Fixed: ${totalFixed} mismatched counts`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

fixCommentCounts();

