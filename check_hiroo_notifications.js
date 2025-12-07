// Check recent notifications for hiroo to see if they were created

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkRecentNotifications() {
  console.log('🔍 Checking recent notifications for hiroo...\n');
  
  try {
    // Find hiroo's user ID
    const usersSnapshot = await db.collection('users')
      .where('username', '==', 'hiroo')
      .limit(1)
      .get();
    
    if (usersSnapshot.empty) {
      console.log('❌ User "hiroo" not found');
      return;
    }
    
    const hirooId = usersSnapshot.docs[0].id;
    console.log(`✅ Found hiroo: ${hirooId}\n`);
    
    // Get recent notifications for hiroo (last 10)
    const notificationsSnapshot = await db.collection('notifications')
      .where('recipientId', '==', hirooId)
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get();
    
    if (notificationsSnapshot.empty) {
      console.log('❌ No notifications found for hiroo');
      return;
    }
    
    console.log(`📬 Found ${notificationsSnapshot.size} recent notifications:\n`);
    
    notificationsSnapshot.forEach((doc, index) => {
      const notif = doc.data();
      const createdAt = notif.createdAt ? notif.createdAt.toDate() : 'unknown';
      const now = new Date();
      const minutesAgo = notif.createdAt ? ((now - notif.createdAt.toDate()) / (1000 * 60)).toFixed(1) : '?';
      
      console.log(`${index + 1}. Notification ${doc.id}`);
      console.log(`   Type: ${notif.type}`);
      console.log(`   From: ${notif.actorId}`);
      console.log(`   Post: ${notif.postId || '(none)'}`);
      console.log(`   Stamp: ${notif.stampId || '(none)'}`);
      console.log(`   Preview: ${notif.commentPreview || '(none)'}`);
      console.log(`   Read: ${notif.isRead ? 'Yes' : 'No'}`);
      console.log(`   Created: ${createdAt} (${minutesAgo} min ago)`);
      console.log();
    });
    
    // Count unread
    const unreadCount = notificationsSnapshot.docs.filter(doc => !doc.data().isRead).length;
    console.log(`📊 Summary: ${unreadCount} unread, ${notificationsSnapshot.size - unreadCount} read`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

checkRecentNotifications()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

