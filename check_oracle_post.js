const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function checkOraclePost() {
  console.log('\n🔍 Checking Oracle Park post data...\n');
  
  const userId = 'ziI5xSvHhyXZ9MbKDDX9sKvHSjC3';
  const stampId = 'us-ca-sf-oracle-park';
  const postId = `${userId}-${stampId}`;
  
  try {
    // Get the collected stamp document
    const collectedStampDoc = await db
      .collection('users')
      .doc(userId)
      .collection('collectedStamps')
      .doc(stampId)
      .get();
    
    if (!collectedStampDoc.exists) {
      console.log('❌ Post not found');
      process.exit(1);
    }
    
    const data = collectedStampDoc.data();
    console.log('📄 Collected Stamp Document:');
    console.log(`   stampId: ${stampId}`);
    console.log(`   likeCount: ${data.likeCount ?? 'undefined'}`);
    console.log(`   commentCount: ${data.commentCount ?? 'undefined'}`);
    console.log(`   collectedDate: ${data.collectedDate?.toDate?.() || data.collectedDate}`);
    
    // Count actual likes
    const likesSnapshot = await db
      .collection('likes')
      .where('postId', '==', postId)
      .get();
    console.log(`\n❤️  Actual likes in likes collection: ${likesSnapshot.size}`);
    
    if (likesSnapshot.size > 0) {
      console.log('   Liked by:');
      likesSnapshot.forEach(doc => {
        const likeData = doc.data();
        console.log(`     - ${likeData.userId} at ${likeData.createdAt?.toDate?.() || likeData.createdAt}`);
      });
    }
    
    // Count actual comments
    const commentsSnapshot = await db
      .collection('comments')
      .where('postId', '==', postId)
      .get();
    console.log(`\n💬 Actual comments in comments collection: ${commentsSnapshot.size}`);
    
    if (commentsSnapshot.size > 0) {
      console.log('   Comments:');
      commentsSnapshot.forEach(doc => {
        const commentData = doc.data();
        console.log(`     - ${commentData.userId}: "${commentData.text}"`);
      });
    }
    
    // Check for drift
    const storedLikeCount = data.likeCount ?? 0;
    const storedCommentCount = data.commentCount ?? 0;
    const actualLikeCount = likesSnapshot.size;
    const actualCommentCount = commentsSnapshot.size;
    
    console.log(`\n📊 Summary:`);
    console.log(`   Stored likeCount: ${storedLikeCount}`);
    console.log(`   Actual likes: ${actualLikeCount}`);
    console.log(`   Match: ${storedLikeCount === actualLikeCount ? '✅' : '❌'}`);
    console.log();
    console.log(`   Stored commentCount: ${storedCommentCount}`);
    console.log(`   Actual comments: ${actualCommentCount}`);
    console.log(`   Match: ${storedCommentCount === actualCommentCount ? '✅' : '❌'}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkOraclePost();

