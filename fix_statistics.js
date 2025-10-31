#!/usr/bin/env node

// Script to fix stamp statistics for already collected stamps
// Run with: node fix_statistics.js

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixStampStatistics() {
  console.log('🔍 Checking stamp statistics...\n');
  
  // Get all users
  const usersSnapshot = await db.collection('users').get();
  
  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    const userName = userDoc.data().displayName || 'Unknown';
    console.log(`👤 Checking user: ${userName} (${userId})`);
    
    // Get all collected stamps for this user
    const collectedStampsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('collected_stamps')
      .get();
    
    console.log(`  📍 Found ${collectedStampsSnapshot.docs.length} collected stamps\n`);
    
    for (const stampDoc of collectedStampsSnapshot.docs) {
      const stampId = stampDoc.id;
      const collectedDate = stampDoc.data().collectedDate?.toDate();
      
      console.log(`  Checking stamp: ${stampId}`);
      console.log(`    Collected: ${collectedDate}`);
      
      // Get current statistics
      const statsRef = db.collection('stamp_statistics').doc(stampId);
      const statsDoc = await statsRef.get();
      
      if (!statsDoc.exists) {
        console.log(`    ❌ No statistics document - creating...`);
        await statsRef.set({
          stampId: stampId,
          totalCollectors: 1,
          collectorUserIds: [userId],
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`    ✅ Created statistics with 1 collector\n`);
      } else {
        const stats = statsDoc.data();
        const collectorIds = stats.collectorUserIds || [];
        
        if (!collectorIds.includes(userId)) {
          console.log(`    ⚠️ User not in collector list - adding...`);
          collectorIds.push(userId);
          await statsRef.update({
            totalCollectors: collectorIds.length,
            collectorUserIds: collectorIds,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
          });
          console.log(`    ✅ Added user - now ${collectorIds.length} collector(s)\n`);
        } else {
          console.log(`    ✅ Already counted (${stats.totalCollectors} total collectors)\n`);
        }
      }
    }
  }
  
  console.log('✅ All stamp statistics are now correct!\n');
}

fixStampStatistics()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
  });

