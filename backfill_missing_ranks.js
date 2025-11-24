/**
 * Backfill Missing User Ranks
 * 
 * ROOT CAUSE: The updateUserRank() function was only saving ranks to local cache,
 * not syncing them back to Firestore. This meant:
 * 1. User collects stamp → saved to Firestore with userRank: undefined
 * 2. Rank is fetched and cached locally
 * 3. Rank NEVER gets saved back to Firestore
 * 
 * This script finds all collected stamps missing userRank and calculates/saves them.
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (admin.apps.length === 0) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

async function backfillMissingRanks() {
  console.log('🔍 Checking all collected stamps for missing userRank fields...\n');
  
  const usersSnapshot = await db.collection('users').get();
  
  let totalStamps = 0;
  let stampsWithRank = 0;
  let stampsWithoutRank = 0;
  let updated = 0;
  
  const missingRanks = [];
  
  // Step 1: Find all stamps missing ranks
  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    const username = userDoc.data().username || userId;
    
    const stampsSnapshot = await db.collection('users').doc(userId).collection('collectedStamps').get();
    
    for (const stampDoc of stampsSnapshot.docs) {
      totalStamps++;
      const data = stampDoc.data();
      const stampId = stampDoc.id;
      
      if (data.userRank !== undefined) {
        stampsWithRank++;
      } else {
        stampsWithoutRank++;
        missingRanks.push({
          userId,
          username,
          stampId,
          collectedDate: data.collectedDate.toDate()
        });
        console.log(`❌ Missing rank: ${username} - ${stampId}`);
      }
    }
  }
  
  console.log(`\n==================`);
  console.log(`Total stamps: ${totalStamps}`);
  console.log(`With rank: ${stampsWithRank}`);
  console.log(`Without rank: ${stampsWithoutRank}`);
  
  if (missingRanks.length === 0) {
    console.log(`\n✅ All stamps have ranks! No backfill needed.`);
    return;
  }
  
  console.log(`\n🔧 Calculating and saving missing ranks...\n`);
  
  // Step 2: Calculate and save missing ranks
  for (const missing of missingRanks) {
    try {
      // Get all collectors for this stamp (from stamp_statistics)
      const statsDoc = await db.collection('stamp_statistics').doc(missing.stampId).get();
      
      if (!statsDoc.exists) {
        console.log(`⚠️  No statistics found for ${missing.stampId} - skipping`);
        continue;
      }
      
      const collectorIds = statsDoc.data().collectorUserIds || [];
      
      if (!collectorIds.includes(missing.userId)) {
        console.log(`⚠️  User ${missing.username} not in collector list for ${missing.stampId} - skipping`);
        continue;
      }
      
      // User's rank is their position in the array + 1
      const rank = collectorIds.indexOf(missing.userId) + 1;
      
      // Update Firestore
      await db.collection('users')
        .doc(missing.userId)
        .collection('collectedStamps')
        .doc(missing.stampId)
        .update({ userRank: rank });
      
      console.log(`✅ ${missing.username} - ${missing.stampId}: rank #${rank}`);
      updated++;
      
    } catch (error) {
      console.error(`❌ Error processing ${missing.username} - ${missing.stampId}:`, error.message);
    }
  }
  
  console.log(`\n==================`);
  console.log(`✅ Backfill complete!`);
  console.log(`Updated ${updated} / ${missingRanks.length} stamps`);
}

backfillMissingRanks()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });

