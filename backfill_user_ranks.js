const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function backfillUserRanks() {
  try {
    console.log('=== BACKFILLING USER RANKS ===\n');
    
    // Get all stamp statistics (these contain the collectorUserIds array which shows the order)
    const stampStatsSnapshot = await db.collection('stamp_statistics').get();
    console.log(`Found ${stampStatsSnapshot.size} stamps with statistics\n`);
    
    let totalStampsUpdated = 0;
    let totalUsersProcessed = 0;
    
    for (const stampStatDoc of stampStatsSnapshot.docs) {
      const stampId = stampStatDoc.id;
      const stampData = stampStatDoc.data();
      const collectorUserIds = stampData.collectorUserIds || [];
      
      if (collectorUserIds.length === 0) {
        console.log(`⚠️  Stamp ${stampId}: No collectors yet, skipping`);
        continue;
      }
      
      console.log(`\n📍 Stamp: ${stampId}`);
      console.log(`   Total collectors: ${collectorUserIds.length}`);
      
      // Update userRank for each collector
      for (let i = 0; i < collectorUserIds.length; i++) {
        const userId = collectorUserIds[i];
        const userRank = i + 1; // 1-indexed (1st, 2nd, 3rd, etc.)
        
        try {
          const collectedStampRef = db.collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .doc(stampId);
          
          const collectedStampDoc = await collectedStampRef.get();
          
          if (collectedStampDoc.exists) {
            const data = collectedStampDoc.data();
            
            // Only update if userRank is missing or different
            if (data.userRank !== userRank) {
              await collectedStampRef.update({
                userRank: userRank
              });
              
              console.log(`   ✅ Updated user ${userId}: rank #${userRank}`);
              totalStampsUpdated++;
            } else {
              console.log(`   ℹ️  User ${userId}: already has rank #${userRank}`);
            }
          } else {
            console.log(`   ⚠️  User ${userId}: collected stamp document doesn't exist (might be data inconsistency)`);
          }
          
          totalUsersProcessed++;
          
        } catch (error) {
          console.error(`   ❌ Error updating rank for user ${userId}:`, error.message);
        }
      }
    }
    
    console.log('\n=== SUMMARY ===');
    console.log(`Total users processed: ${totalUsersProcessed}`);
    console.log(`Total stamps updated: ${totalStampsUpdated}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

backfillUserRanks();

