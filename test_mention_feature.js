/**
 * Test Mention Feature
 * Creates a test comment with @mention to verify notification generation
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testMentionFeature() {
  console.log('\n🧪 TESTING @MENTION FEATURE\n');
  console.log('='.repeat(80));
  
  try {
    // 1. Get test users
    console.log('\n1️⃣ Finding test users...\n');
    
    const usersSnapshot = await db.collection('users').limit(3).get();
    
    if (usersSnapshot.size < 2) {
      console.log('❌ Need at least 2 users for testing');
      return;
    }
    
    const users = usersSnapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    console.log('Found users:');
    users.forEach((user, i) => {
      console.log(`  ${i + 1}. ${user.username} (${user.displayName}) - ID: ${user.id}`);
    });
    
    // User 0 will post, User 1 will comment and mention User 2
    const postOwner = users[0];
    const commenter = users[1];
    const mentionedUser = users[2] || users[0]; // Fallback if only 2 users
    
    console.log(`\n✅ Test setup:`);
    console.log(`  Post owner: ${postOwner.username}`);
    console.log(`  Commenter: ${commenter.username}`);
    console.log(`  Mentioned user: @${mentionedUser.username}`);
    
    // 2. Find a recent post by the post owner
    console.log('\n2️⃣ Finding a recent post...\n');
    
    const postsSnapshot = await db.collectionGroup('collectedStamps')
      .where('userId', '==', postOwner.id)
      .orderBy('collectedDate', 'desc')
      .limit(1)
      .get();
    
    if (postsSnapshot.empty) {
      console.log('❌ Post owner has no stamps collected');
      return;
    }
    
    const post = postsSnapshot.docs[0];
    const postData = post.data();
    
    console.log(`✅ Found post: ${postData.stampId} (collected by ${postOwner.username})`);
    
    // 3. Count current notifications for mentioned user
    console.log('\n3️⃣ Checking current notifications...\n');
    
    const beforeNotifs = await db.collection('notifications')
      .where('recipientId', '==', mentionedUser.id)
      .get();
    
    console.log(`Current notifications for @${mentionedUser.username}: ${beforeNotifs.size}`);
    
    // 4. Create a comment with @mention
    console.log('\n4️⃣ Creating test comment with @mention...\n');
    
    const commentText = `Hey @${mentionedUser.username} check this out! This is a test mention.`;
    
    console.log(`Comment text: "${commentText}"`);
    
    const commentRef = await db.collection('comments').add({
      userId: commenter.id,
      postId: post.id,
      postOwnerId: postOwner.id,
      stampId: postData.stampId,
      text: commentText,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      likeCount: 0
    });
    
    console.log(`✅ Comment created: ${commentRef.id}`);
    console.log('\n⏳ Waiting 3 seconds for Cloud Function to trigger...\n');
    
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // 5. Check if mention notification was created
    console.log('5️⃣ Checking for new mention notification...\n');
    
    const afterNotifs = await db.collection('notifications')
      .where('recipientId', '==', mentionedUser.id)
      .where('type', '==', 'mention')
      .get();
    
    if (afterNotifs.size > 0) {
      console.log(`✅ SUCCESS! Found ${afterNotifs.size} mention notification(s):\n`);
      
      afterNotifs.docs.forEach(doc => {
        const notif = doc.data();
        console.log(`Notification ID: ${doc.id}`);
        console.log(`  Recipient: ${mentionedUser.username} (${notif.recipientId})`);
        console.log(`  Actor: ${commenter.username} (${notif.actorId})`);
        console.log(`  Type: ${notif.type}`);
        console.log(`  Comment Preview: "${notif.commentPreview}"`);
        console.log(`  Created: ${notif.createdAt?.toDate()}`);
        console.log('');
      });
      
      console.log('🎉 @MENTION FEATURE IS WORKING!\n');
    } else {
      console.log('❌ No mention notification created');
      console.log('\nPossible issues:');
      console.log('  1. Cloud Function failed (check Firebase Console logs)');
      console.log('  2. Firestore index not ready yet (wait a few minutes)');
      console.log('  3. Username lookup failed (check if username exists)');
      
      // Check if ANY notification was created for the comment
      const allNewNotifs = await db.collection('notifications')
        .where('recipientId', '==', postOwner.id)
        .where('type', '==', 'comment')
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
      
      if (allNewNotifs.size > 0) {
        console.log('\n✅ BUT: Regular comment notification WAS created for post owner');
        console.log('   This means the Cloud Function is working, but mention logic may have failed');
      }
    }
    
    // 6. Cleanup - delete test comment
    console.log('\n6️⃣ Cleaning up test comment...\n');
    await commentRef.delete();
    console.log('✅ Test comment deleted');
    
    // Delete test notifications
    if (afterNotifs.size > 0) {
      console.log('✅ Cleaning up test notifications...');
      const batch = db.batch();
      afterNotifs.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      console.log('✅ Test notifications deleted');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  }
  
  console.log('\n' + '='.repeat(80));
}

testMentionFeature()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

