// Test sending push notification to hiroo

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function testPushNotification() {
  console.log('🔔 Testing push notification to hiroo...\n');
  
  try {
    // Find hiroo's user document
    const usersSnapshot = await db.collection('users')
      .where('username', '==', 'hiroo')
      .limit(1)
      .get();
    
    if (usersSnapshot.empty) {
      console.log('❌ User "hiroo" not found');
      return;
    }
    
    const hirooDoc = usersSnapshot.docs[0];
    const hirooData = hirooDoc.data();
    const hirooId = hirooDoc.id;
    
    console.log(`✅ Found hiroo: ${hirooId}`);
    
    // Check FCM token
    if (!hirooData.fcmToken) {
      console.log('❌ No FCM token found for hiroo');
      return;
    }
    
    console.log(`✅ FCM Token found: ${hirooData.fcmToken.substring(0, 30)}...`);
    console.log();
    
    // Get unread notification count
    const unreadSnapshot = await db.collection('notifications')
      .where('recipientId', '==', hirooId)
      .where('isRead', '==', false)
      .get();
    
    const badgeCount = unreadSnapshot.size;
    console.log(`📬 Unread notifications: ${badgeCount}`);
    console.log();
    
    // Send test push notification
    const message = {
      token: hirooData.fcmToken,
      notification: {
        title: 'Test Push Notification',
        body: 'This is a test notification from Stampbook. If you see this, push notifications are working!'
      },
      data: {
        type: 'test',
        timestamp: new Date().toISOString()
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: badgeCount
          }
        }
      }
    };
    
    console.log('📤 Sending push notification...');
    console.log('   Title:', message.notification.title);
    console.log('   Body:', message.notification.body);
    console.log('   Badge:', badgeCount);
    console.log();
    
    const response = await admin.messaging().send(message);
    
    console.log('✅ Push notification sent successfully!');
    console.log('   Message ID:', response);
    console.log();
    console.log('📱 Check hiroo\'s iPhone now - you should see a banner notification');
    console.log('   If you don\'t see it, check:');
    console.log('   1. Settings > Notifications > Stampbook > Allow Notifications is ON');
    console.log('   2. Do Not Disturb / Focus mode is OFF');
    console.log('   3. The app is in the background (notifications don\'t show in foreground by default)');
    
  } catch (error) {
    console.error('❌ Error sending push notification:');
    console.error('   Error code:', error.code);
    console.error('   Error message:', error.message);
    console.error();
    console.error('Full error:', error);
    
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      console.log();
      console.log('⚠️ FCM Token is invalid or expired!');
      console.log('   Solution: Have hiroo sign out and sign back in to refresh the token');
    }
    
    if (error.code === 'messaging/invalid-apns-credentials') {
      console.log();
      console.log('⚠️ APNs credentials are not configured correctly!');
      console.log('   Solution: Check Firebase Console > Project Settings > Cloud Messaging > APNs');
    }
  }
}

testPushNotification()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });

