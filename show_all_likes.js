const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function showAllLikes() {
  try {
    console.log('💖 Fetching all likes from database...\n');
    
    // Get all likes
    const likesSnapshot = await db.collection('likes').get();
    
    if (likesSnapshot.empty) {
      console.log('📭 No likes in the database yet!\n');
      return;
    }
    
    console.log(`Found ${likesSnapshot.size} like(s):\n`);
    console.log('═'.repeat(80));
    
    for (const [index, likeDoc] of likesSnapshot.docs.entries()) {
      const like = likeDoc.data();
      
      console.log(`\n${index + 1}. Like ID: ${likeDoc.id}`);
      console.log('─'.repeat(80));
      
      // Get user who liked
      const userDoc = await db.collection('users').doc(like.userId).get();
      const userData = userDoc.exists ? userDoc.data() : null;
      
      // Get post owner
      const ownerDoc = await db.collection('users').doc(like.postOwnerId).get();
      const ownerData = ownerDoc.exists ? ownerDoc.data() : null;
      
      console.log(`👤 Who liked:    ${userData?.displayName || 'Unknown'} (@${userData?.username || 'unknown'})`);
      console.log(`📍 Which post:   ${like.postId}`);
      console.log(`🏷️  Stamp ID:     ${like.stampId}`);
      console.log(`👥 Post owner:   ${ownerData?.displayName || 'Unknown'} (@${ownerData?.username || 'unknown'})`);
      console.log(`⏰ When:         ${like.createdAt?.toDate() || 'Unknown'}`);
      
      // Try to get the actual stamp name
      const [userId, stampId] = like.postId.split('-');
      if (userId && stampId) {
        const stampDoc = await db.collection('users').doc(like.postOwnerId)
          .collection('collected_stamps')
          .doc(like.stampId)
          .get();
        
        if (stampDoc.exists) {
          const stampData = stampDoc.data();
          console.log(`📸 Post caption: ${stampData.caption || '(no caption)'}`);
        }
      }
    }
    
    console.log('\n' + '═'.repeat(80));
    console.log(`\n✅ Total likes: ${likesSnapshot.size}\n`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

showAllLikes();

