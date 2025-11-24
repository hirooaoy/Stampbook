/**
 * Check Hiroo Mention Notifications
 * Investigate why hiroo didn't get mention notification from watagumo
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooMention() {
  console.log('\n🔍 CHECKING HIROO MENTION ISSUE\n');
  console.log('='.repeat(80));
  
  try {
    // 1. Find hiroo and watagumo user IDs
    console.log('\n1️⃣ Finding users...\n');
    
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
    
    const hirooId = hirooSnapshot.docs[0].id;
    const watagumoId = watagumoSnapshot.docs[0].id;
    
    console.log(`✅ Hiroo ID: ${hirooId}`);
    console.log(`✅ Watagumo ID: ${watagumoId}`);
    
    // 2. Find all comments by watagumo that mention @hiroo
    console.log('\n2️⃣ Searching for comments by watagumo that mention @hiroo...\n');
    
    const allComments = await db.collection('comments')
      .where('userId', '==', watagumoId)
      .get();
    
    console.log(`Found ${allComments.size} comments by watagumo\n`);
    
    const commentsWithMention = [];
    
    allComments.docs.forEach(doc => {
      const comment = doc.data();
      const hasMention = /@hiroo\b/i.test(comment.text);
      
      if (hasMention) {
        commentsWithMention.push({
          id: doc.id,
          ...comment
        });
      }
    });
    
    if (commentsWithMention.length === 0) {
      console.log('❌ No comments found with @hiroo mention');
      return;
    }
    
    console.log(`✅ Found ${commentsWithMention.length} comment(s) with @hiroo mention:\n`);
    
    for (const comment of commentsWithMention) {
      console.log(`Comment ID: ${comment.id}`);
      console.log(`  Text: "${comment.text}"`);
      console.log(`  Post Owner: ${comment.postOwnerId}`);
      console.log(`  Post Owner is Hiroo: ${comment.postOwnerId === hirooId ? '✅ YES' : '❌ NO'}`);
      console.log(`  Created: ${comment.createdAt?.toDate()}`);
      console.log('');
      
      // 3. Check what notifications were created for this comment
      console.log(`  📬 Checking notifications created for this comment...\n`);
      
      // Check comment notifications
      const commentNotifs = await db.collection('notifications')
        .where('postId', '==', comment.postId)
        .where('actorId', '==', watagumoId)
        .where('type', '==', 'comment')
        .get();
      
      if (commentNotifs.size > 0) {
        console.log(`  ✅ Found ${commentNotifs.size} comment notification(s):`);
        commentNotifs.docs.forEach(doc => {
          const notif = doc.data();
          console.log(`    - Recipient: ${notif.recipientId} (${notif.recipientId === hirooId ? 'hiroo' : 'someone else'})`);
          console.log(`    - Type: ${notif.type}`);
          console.log(`    - Created: ${notif.createdAt?.toDate()}`);
        });
      } else {
        console.log(`  ❌ No comment notification found`);
      }
      
      // Check mention notifications
      const mentionNotifs = await db.collection('notifications')
        .where('postId', '==', comment.postId)
        .where('actorId', '==', watagumoId)
        .where('type', '==', 'mention')
        .get();
      
      if (mentionNotifs.size > 0) {
        console.log(`\n  ✅ Found ${mentionNotifs.size} mention notification(s):`);
        mentionNotifs.docs.forEach(doc => {
          const notif = doc.data();
          console.log(`    - Recipient: ${notif.recipientId} (${notif.recipientId === hirooId ? 'hiroo' : 'someone else'})`);
          console.log(`    - Type: ${notif.type}`);
          console.log(`    - Created: ${notif.createdAt?.toDate()}`);
        });
      } else {
        console.log(`\n  ❌ NO MENTION NOTIFICATION FOUND`);
        
        // Diagnose the issue
        console.log(`\n  🔍 DIAGNOSIS:`);
        if (comment.postOwnerId === hirooId) {
          console.log(`  ⚠️  ISSUE FOUND: Hiroo is the post owner!`);
          console.log(`  
  The Cloud Function logic has a bug:
  
  1. Watagumo comments "@hiroo check this out!" on Hiroo's post
  2. Function creates "comment" notification for post owner (Hiroo)
  3. Function extracts @hiroo from comment text
  4. Function checks if Hiroo is already notified (YES, as post owner)
  5. Function SKIPS creating mention notification (to avoid duplicate)
  
  PROBLEM: The "comment" notification doesn't show that hiroo was @mentioned!
  
  SOLUTION OPTIONS:
  A. Create BOTH notifications (comment + mention)
  B. Upgrade comment notification to "mention" type if post owner is mentioned
  C. Keep comment notification but add "wasMentioned" flag to UI
          `);
        } else {
          console.log(`  ❓ Unknown issue - mention notification should have been created`);
        }
      }
      
      console.log('\n' + '-'.repeat(80) + '\n');
    }
    
    // 4. Summary
    console.log('\n📊 SUMMARY:\n');
    console.log(`Total comments by watagumo with @hiroo: ${commentsWithMention.length}`);
    
    const onHirooPosts = commentsWithMention.filter(c => c.postOwnerId === hirooId).length;
    const onOtherPosts = commentsWithMention.length - onHirooPosts;
    
    console.log(`  - Comments on Hiroo's own posts: ${onHirooPosts}`);
    console.log(`  - Comments on other people's posts: ${onOtherPosts}`);
    
    if (onHirooPosts > 0) {
      console.log(`\n⚠️  BUG CONFIRMED: When someone mentions the post owner, mention notification is skipped!`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
  }
  
  console.log('\n' + '='.repeat(80));
}

checkHirooMention()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

