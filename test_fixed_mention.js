/**
 * Test Fixed Mention Feature
 * Tests that post owner gets "mention" notification when they're @mentioned
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testFixedMention() {
  console.log('\n🧪 TESTING FIXED @MENTION FEATURE\n');
  console.log('='.repeat(80));
  
  try {
    // 1. Get test users
    console.log('\n1️⃣ Finding test users...\n');
    
    const hirooSnapshot = await db.collection('users')
      .where('username', '==', 'hiroo')
      .limit(1)
      .get();
    
    const watagumoSnapshot = await db.collection('users')
      .where('username', '==', 'watagumostudio')
      .limit(1)
      .get();
    
    if (hirooSnapshot.empty || watagumoSnapshot.empty) {
      console.log('❌ Could not find both users');
      return;
    }
    
    const hiroo = {
      id: hirooSnapshot.docs[0].id,
      ...hirooSnapshot.docs[0].data()
    };
    
    const watagumo = {
      id: watagumoSnapshot.docs[0].id,
      ...watagumoSnapshot.docs[0].data()
    };
    
    console.log(`✅ Hiroo: ${hiroo.username} (${hiroo.id})`);
    console.log(`✅ Watagumo: ${watagumo.username} (${watagumo.id})`);
    
    // 2. Find a recent post by hiroo (the post owner)
    console.log('\n2️⃣ Finding a recent post by Hiroo...\n');
    
    const postsSnapshot = await db.collectionGroup('collectedStamps')
      .where('userId', '==', hiroo.id)
      .orderBy('collectedDate', 'desc')
      .limit(1)
      .get();
    
    if (postsSnapshot.empty) {
      console.log('❌ Hiroo has no stamps collected');
      return;
    }
    
    const post = postsSnapshot.docs[0];
    const postData = post.data();
    
    console.log(`✅ Found post: ${postData.stampId} (collected by ${hiroo.username})`);
    
    // 3. Create a comment with @hiroo mention (watagumo mentioning the post owner)
    console.log('\n3️⃣ Creating test comment with @hiroo mention...\n');
    
    const commentText = `Hey @hiroo this is awesome! (test comment)`;
    
    console.log(`Comment text: "${commentText}"`);
    console.log(`Post owner: ${hiroo.username}`);
    console.log(`Commenter: ${watagumo.username}`);
    console.log(`Mentioned: @${hiroo.username} (the post owner)`);
    
    const commentRef = await db.collection('comments').add({
      userId: watagumo.id,
      postId: post.id,
      postOwnerId: hiroo.id,
      stampId: postData.stampId,
      text: commentText,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      likeCount: 0
    });
    
    console.log(`\n✅ Comment created: ${commentRef.id}`);
    console.log('⏳ Waiting 3 seconds for Cloud Function to trigger...\n');
    
    await new Promise(resolve => setTimeout(resolve, 3000));
    
    // 4. Check what notification was created
    console.log('4️⃣ Checking notification type...\n');
    
    const notifs = await db.collection('notifications')
      .where('recipientId', '==', hiroo.id)
      .orderBy('createdAt', 'desc')
      .limit(5)
      .get();
    
    if (notifs.empty) {
      console.log('❌ No notification created!');
    } else {
      // Find the notification from watagumo
      const watagumoNotif = notifs.docs.find(doc => doc.data().actorId === watagumo.id);
      
      if (!watagumoNotif) {
        console.log('❌ No notification from watagumo found!');
        console.log('\nAll notifications:');
        notifs.docs.forEach(doc => {
          const notif = doc.data();
          console.log(`  - Type: ${notif.type}, Actor: ${notif.actorId}`);
        });
      } else {
        const notif = watagumoNotif.data();
        
        console.log(`✅ Notification created:`);
        console.log(`  Type: ${notif.type}`);
        console.log(`  Recipient: ${hiroo.username}`);
        console.log(`  Actor: ${watagumo.username}`);
        console.log(`  Comment Preview: "${notif.commentPreview}"`);
        console.log(`  Created: ${notif.createdAt?.toDate()}`);
        
        if (notif.type === 'mention') {
          console.log('\n🎉 SUCCESS! Post owner received "mention" notification (not "comment")!');
          console.log('✅ The bug is FIXED!');
        } else if (notif.type === 'comment') {
          console.log('\n❌ STILL BROKEN: Post owner received "comment" notification');
          console.log('   Expected: "mention" notification');
          console.log('   The fix may not have deployed yet or there was an error');
        }
        
        // 5. Cleanup
        console.log('\n5️⃣ Cleaning up...\n');
        await commentRef.delete();
        if (watagumoNotif) {
          await watagumoNotif.ref.delete();
        }
        console.log('✅ Test comment and notification deleted');
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  }
  
  console.log('\n' + '='.repeat(80));
}

testFixedMention()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

