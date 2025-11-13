const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Test script to manually run notification cleanup
 * (Same logic as the scheduled Cloud Function)
 */
async function testCleanup() {
  console.log('🧹 Testing notification cleanup logic...\n');
  
  const now = admin.firestore.Timestamp.now();
  
  // Calculate cutoff dates
  const thirtyDaysAgo = new Date(now.toDate());
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const ninetyDaysAgo = new Date(now.toDate());
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);
  
  console.log(`Current time: ${now.toDate()}`);
  console.log(`30 days ago: ${thirtyDaysAgo}`);
  console.log(`90 days ago: ${ninetyDaysAgo}\n`);
  
  let totalDeleted = 0;
  
  try {
    // Step 1: Check for read notifications older than 30 days
    console.log('📋 Checking for read notifications older than 30 days...');
    const readOldQuery = db.collection('notifications')
      .where('isRead', '==', true)
      .where('createdAt', '<', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .limit(500);
    
    const readOldSnapshot = await readOldQuery.get();
    
    if (!readOldSnapshot.empty) {
      console.log(`Found ${readOldSnapshot.size} read notifications to delete`);
      const batch1 = db.batch();
      readOldSnapshot.docs.forEach(doc => {
        batch1.delete(doc.ref);
      });
      await batch1.commit();
      console.log(`✅ Deleted ${readOldSnapshot.size} read notifications (30+ days old)\n`);
      totalDeleted += readOldSnapshot.size;
    } else {
      console.log('✓ No read notifications older than 30 days\n');
    }
    
    // Step 2: Check for all notifications older than 90 days
    console.log('📋 Checking for all notifications older than 90 days...');
    const allOldQuery = db.collection('notifications')
      .where('createdAt', '<', admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
      .limit(500);
    
    const allOldSnapshot = await allOldQuery.get();
    
    if (!allOldSnapshot.empty) {
      console.log(`Found ${allOldSnapshot.size} notifications to delete`);
      const batch2 = db.batch();
      allOldSnapshot.docs.forEach(doc => {
        batch2.delete(doc.ref);
      });
      await batch2.commit();
      console.log(`✅ Deleted ${allOldSnapshot.size} notifications (90+ days old)\n`);
      totalDeleted += allOldSnapshot.size;
    } else {
      console.log('✓ No notifications older than 90 days\n');
    }
    
    // Step 3: Show current notification stats
    console.log('📊 Current notification statistics:');
    const allNotifications = await db.collection('notifications').get();
    const readCount = allNotifications.docs.filter(doc => doc.data().isRead === true).length;
    const unreadCount = allNotifications.docs.filter(doc => doc.data().isRead === false).length;
    
    console.log(`Total notifications: ${allNotifications.size}`);
    console.log(`Read: ${readCount}`);
    console.log(`Unread: ${unreadCount}`);
    
    console.log(`\n🎉 Cleanup complete! Total deleted: ${totalDeleted} notifications`);
    
  } catch (error) {
    console.error('❌ Error during notification cleanup:', error);
  }
  
  process.exit(0);
}

testCleanup();

