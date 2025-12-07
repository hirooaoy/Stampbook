/**
 * Migration Script: Add likeCount field to all existing comments
 * 
 * This script adds likeCount: 0 to all existing comments in Firestore.
 * Run this ONCE after deploying comment likes feature.
 * 
 * Usage: node add_likecount_to_comments.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function addLikeCountToComments() {
  console.log('🚀 Starting migration: Adding likeCount to all comments...\n');
  
  try {
    // Fetch all comments
    const commentsSnapshot = await db.collection('comments').get();
    
    if (commentsSnapshot.empty) {
      console.log('✅ No comments found. Migration complete.');
      return;
    }
    
    console.log(`📊 Found ${commentsSnapshot.size} comments to process\n`);
    
    let updatedCount = 0;
    let skippedCount = 0;
    let errorCount = 0;
    
    // Process in batches of 500 (Firestore batch limit)
    const batchSize = 500;
    let batch = db.batch();
    let operationsInBatch = 0;
    
    for (const doc of commentsSnapshot.docs) {
      const commentData = doc.data();
      
      // Skip if likeCount already exists
      if ('likeCount' in commentData) {
        skippedCount++;
        console.log(`⏭️  Skipped comment ${doc.id} (likeCount already exists: ${commentData.likeCount})`);
        continue;
      }
      
      try {
        // Add likeCount: 0 to comment
        batch.update(doc.ref, { likeCount: 0 });
        operationsInBatch++;
        updatedCount++;
        
        console.log(`✅ Queued comment ${doc.id} for update (will add likeCount: 0)`);
        
        // Commit batch if we hit the limit
        if (operationsInBatch >= batchSize) {
          await batch.commit();
          console.log(`\n📦 Committed batch of ${operationsInBatch} updates\n`);
          batch = db.batch();
          operationsInBatch = 0;
        }
      } catch (error) {
        errorCount++;
        console.error(`❌ Error processing comment ${doc.id}:`, error);
      }
    }
    
    // Commit any remaining operations
    if (operationsInBatch > 0) {
      await batch.commit();
      console.log(`\n📦 Committed final batch of ${operationsInBatch} updates\n`);
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total comments:     ${commentsSnapshot.size}`);
    console.log(`Updated:            ${updatedCount} ✅`);
    console.log(`Skipped (exists):   ${skippedCount} ⏭️`);
    console.log(`Errors:             ${errorCount} ❌`);
    console.log('='.repeat(60));
    console.log('\n✅ Migration complete!');
    
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    process.exit(1);
  }
}

// Run migration
addLikeCountToComments()
  .then(() => {
    console.log('\n👋 Exiting...');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Fatal error:', error);
    process.exit(1);
  });

