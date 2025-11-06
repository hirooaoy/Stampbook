/**
 * PHASE 1: Data Migration Script
 * 
 * WHAT THIS DOES:
 * 1. Fixes the -1 like count on "your-first-stamp"
 * 2. Sets all undefined likeCount fields to 0
 * 3. Sets all undefined commentCount fields to 0
 * 
 * WHY WE NEED THIS:
 * - Old stamps were collected before social features existed
 * - They don't have likeCount/commentCount fields
 * - This causes undefined - 1 = -1 bug
 * 
 * RUN THIS ONCE TO CLEAN UP DATA
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function fixLikeCommentCounts() {
  console.log('\n🔧 PHASE 1: Fixing Like/Comment Counts\n');
  console.log('=' .repeat(60));
  
  let totalStampsChecked = 0;
  let totalFixed = 0;
  let negativeFixed = 0;
  let undefinedFixed = 0;
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    
    console.log(`\n📊 Found ${usersSnapshot.size} users\n`);
    
    // Process each user's collected stamps
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      
      console.log(`\n👤 Processing user: ${userData.username || userId}`);
      
      // Get all collected stamps for this user
      const stampsSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
      
      if (stampsSnapshot.empty) {
        console.log(`   No stamps to fix`);
        continue;
      }
      
      console.log(`   Found ${stampsSnapshot.size} stamps`);
      
      // Check and fix each stamp
      for (const stampDoc of stampsSnapshot.docs) {
        totalStampsChecked++;
        const stampId = stampDoc.id;
        const stampData = stampDoc.data();
        
        let needsUpdate = false;
        let updates = {};
        let issues = [];
        
        // Check likeCount
        if (stampData.likeCount === undefined) {
          updates.likeCount = 0;
          needsUpdate = true;
          undefinedFixed++;
          issues.push('likeCount undefined → 0');
        } else if (stampData.likeCount < 0) {
          updates.likeCount = 0;
          needsUpdate = true;
          negativeFixed++;
          issues.push(`likeCount ${stampData.likeCount} → 0`);
        }
        
        // Check commentCount
        if (stampData.commentCount === undefined) {
          updates.commentCount = 0;
          needsUpdate = true;
          undefinedFixed++;
          issues.push('commentCount undefined → 0');
        } else if (stampData.commentCount < 0) {
          updates.commentCount = 0;
          needsUpdate = true;
          negativeFixed++;
          issues.push(`commentCount ${stampData.commentCount} → 0`);
        }
        
        // Apply fixes if needed
        if (needsUpdate) {
          await stampDoc.ref.update(updates);
          totalFixed++;
          console.log(`   ✅ Fixed ${stampId}: ${issues.join(', ')}`);
        }
      }
    }
    
    // Summary
    console.log('\n' + '='.repeat(60));
    console.log('📋 MIGRATION SUMMARY\n');
    console.log(`Total stamps checked: ${totalStampsChecked}`);
    console.log(`Total stamps fixed: ${totalFixed}`);
    console.log(`  - Negative counts fixed: ${negativeFixed}`);
    console.log(`  - Undefined counts fixed: ${undefinedFixed}`);
    
    if (totalFixed === 0) {
      console.log('\n✅ All data is clean! No fixes needed.');
    } else {
      console.log(`\n✅ Successfully fixed ${totalFixed} stamps!`);
    }
    
    console.log('\n' + '='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error during migration:', error);
    throw error;
  }
  
  process.exit(0);
}

// Run the migration
console.log('🚀 Starting migration...');
fixLikeCommentCounts();

