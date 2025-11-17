const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkBeehiveCollections() {
  try {
    console.log('Checking if anyone has collected Beehive Trail Summit or Bubble Rock...\n');
    
    const stampsToCheck = [
      'us-me-bar-harbor-beehive-trail-summit',
      'us-me-bar-harbor-bubble-rock'
    ];
    
    for (const stampId of stampsToCheck) {
      console.log(`\n=== Checking: ${stampId} ===`);
      
      // Check all users' collectedStamps
      const usersSnapshot = await db.collection('users').get();
      let collectCount = 0;
      const collectors = [];
      
      for (const userDoc of usersSnapshot.docs) {
        const collectedStampDoc = await db
          .collection('users')
          .doc(userDoc.id)
          .collection('collectedStamps')
          .doc(stampId)
          .get();
        
        if (collectedStampDoc.exists) {
          collectCount++;
          const data = collectedStampDoc.data();
          collectors.push({
            userId: userDoc.id,
            username: userDoc.data().username || 'unknown',
            collectedDate: data.collectedDate?.toDate() || 'unknown',
            hasPhotos: (data.userImagePaths || []).length > 0,
            hasNotes: !!data.userNotes,
            likeCount: data.likeCount || 0,
            commentCount: data.commentCount || 0
          });
        }
      }
      
      console.log(`Total collections: ${collectCount}`);
      if (collectCount > 0) {
        console.log('Collectors:');
        collectors.forEach(c => {
          console.log(`  - ${c.username} (${c.userId})`);
          console.log(`    Collected: ${c.collectedDate}`);
          console.log(`    Photos: ${c.hasPhotos ? 'Yes' : 'No'}`);
          console.log(`    Notes: ${c.hasNotes ? 'Yes' : 'No'}`);
          console.log(`    Likes: ${c.likeCount}, Comments: ${c.commentCount}`);
        });
      }
      
      // Check for comments
      const commentsSnapshot = await db
        .collection('comments')
        .where('stampId', '==', stampId)
        .get();
      console.log(`Comments: ${commentsSnapshot.size}`);
      
      // Check for likes
      const likesSnapshot = await db
        .collection('likes')
        .where('stampId', '==', stampId)
        .get();
      console.log(`Likes: ${likesSnapshot.size}`);
    }
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

checkBeehiveCollections();

