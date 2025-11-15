const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function removeNotesFromOthers() {
  try {
    console.log('🧹 Starting cleanup: Removing notesFromOthers field from all stamps...\n');
    
    // Get all stamps
    const stampsSnapshot = await db.collection('stamps').get();
    
    if (stampsSnapshot.empty) {
      console.log('⚠️  No stamps found');
      return;
    }
    
    console.log(`📍 Found ${stampsSnapshot.size} stamps to check\n`);
    
    let removed = 0;
    let skipped = 0;
    
    // Use batch for efficiency (max 500 operations per batch)
    let batch = db.batch();
    let batchCount = 0;
    
    for (const doc of stampsSnapshot.docs) {
      const stamp = doc.data();
      
      // Check if field exists
      if (stamp.notesFromOthers !== undefined) {
        batch.update(doc.ref, {
          notesFromOthers: admin.firestore.FieldValue.delete()
        });
        batchCount++;
        removed++;
        console.log(`✅ Removing from: ${stamp.name}`);
        
        // Commit batch if it reaches 500
        if (batchCount >= 500) {
          await batch.commit();
          console.log(`💾 Committed batch of ${batchCount} updates\n`);
          batch = db.batch();
          batchCount = 0;
        }
      } else {
        skipped++;
        console.log(`⏭️  Skipping: ${stamp.name} (field doesn't exist)`);
      }
    }
    
    // Commit remaining operations
    if (batchCount > 0) {
      await batch.commit();
      console.log(`💾 Committed final batch of ${batchCount} updates\n`);
    }
    
    // Summary
    console.log('\n' + '═'.repeat(50));
    console.log('📊 CLEANUP SUMMARY');
    console.log('═'.repeat(50));
    console.log(`✅ Removed:  ${removed} stamps`);
    console.log(`⏭️  Skipped:  ${skipped} stamps (field didn't exist)`);
    console.log(`📍 Total:    ${stampsSnapshot.size} stamps`);
    console.log('═'.repeat(50));
    
    if (removed > 0) {
      console.log('\n🎉 Cleanup complete! All stamps now have consistent structure.');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Cleanup failed:', error);
    process.exit(1);
  }
}

removeNotesFromOthers();

