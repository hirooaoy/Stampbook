/**
 * Check Mention Notifications
 * Verifies if mention notifications are being created in Firestore
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkMentionNotifications() {
  console.log('\n🔍 CHECKING MENTION NOTIFICATIONS\n');
  console.log('='.repeat(80));
  
  try {
    // 1. Check all notifications of type "mention"
    console.log('\n📬 Looking for mention notifications...\n');
    const mentionNotifs = await db.collection('notifications')
      .where('type', '==', 'mention')
      .get();
    
    if (mentionNotifs.empty) {
      console.log('⚠️  NO MENTION NOTIFICATIONS FOUND');
      console.log('\nPossible reasons:');
      console.log('  1. Cloud Functions not deployed with mention logic');
      console.log('  2. No one has used @mentions yet');
      console.log('  3. All mentions were invalid (self-mention, non-existent users, etc.)');
    } else {
      console.log(`✅ Found ${mentionNotifs.size} mention notification(s):\n`);
      
      for (const doc of mentionNotifs.docs) {
        const notif = doc.data();
        console.log(`Notification ID: ${doc.id}`);
        console.log(`  Recipient: ${notif.recipientId}`);
        console.log(`  Actor: ${notif.actorId}`);
        console.log(`  Type: ${notif.type}`);
        console.log(`  Comment Preview: "${notif.commentPreview}"`);
        console.log(`  Created: ${notif.createdAt?.toDate()}`);
        console.log(`  Is Read: ${notif.isRead}`);
        console.log('');
      }
    }
    
    // 2. Check all notifications (any type)
    console.log('\n📊 ALL NOTIFICATIONS (last 20):\n');
    const allNotifs = await db.collection('notifications')
      .orderBy('createdAt', 'desc')
      .limit(20)
      .get();
    
    if (allNotifs.empty) {
      console.log('⚠️  No notifications found at all');
    } else {
      const typeCounts = {};
      allNotifs.docs.forEach(doc => {
        const type = doc.data().type;
        typeCounts[type] = (typeCounts[type] || 0) + 1;
      });
      
      console.log('Notification type breakdown (last 20):');
      Object.entries(typeCounts).forEach(([type, count]) => {
        console.log(`  ${type}: ${count}`);
      });
    }
    
    // 3. Check recent comments with @mentions
    console.log('\n\n💬 RECENT COMMENTS (checking for @mentions):\n');
    const comments = await db.collection('comments')
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get();
    
    if (comments.empty) {
      console.log('⚠️  No comments found');
    } else {
      console.log(`Found ${comments.size} recent comments:\n`);
      
      for (const doc of comments.docs) {
        const comment = doc.data();
        const hasMention = /@[a-z0-9_]{3,20}\b/i.test(comment.text);
        
        console.log(`Comment ID: ${doc.id}`);
        console.log(`  User: ${comment.userId}`);
        console.log(`  Post Owner: ${comment.postOwnerId}`);
        console.log(`  Text: "${comment.text}"`);
        console.log(`  Has @mention: ${hasMention ? '✅ YES' : '❌ NO'}`);
        console.log(`  Created: ${comment.createdAt?.toDate()}`);
        console.log('');
      }
    }
    
    // 4. Check if extractMentions function exists in Cloud Functions
    console.log('\n\n🔧 CLOUD FUNCTION STATUS:\n');
    console.log('To verify if mention logic is deployed:');
    console.log('  1. Go to Firebase Console → Functions');
    console.log('  2. Check "createCommentNotification" function');
    console.log('  3. View logs to see if mention extraction is happening');
    console.log('\nOr run: firebase functions:log --only createCommentNotification');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
  
  console.log('\n' + '='.repeat(80));
}

checkMentionNotifications()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

