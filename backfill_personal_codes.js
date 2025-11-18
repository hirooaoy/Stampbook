// backfill_personal_codes.js
// Generates personal invite codes for existing users who don't have one yet

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

// Generate random 8-character code (no confusing characters)
function generateRandomCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

async function backfillPersonalCodes() {
  console.log('🔄 Starting personal code backfill for existing users...\n');
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`📊 Found ${usersSnapshot.size} total users\n`);
    
    let usersWithoutCode = 0;
    let codesGenerated = 0;
    let errors = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const username = userData.username || 'unknown';
      
      // Check if user already has a personal code
      if (userData.personalInviteCode) {
        console.log(`✅ ${username} (${userId}) - Already has code: ${userData.personalInviteCode}`);
        continue;
      }
      
      usersWithoutCode++;
      console.log(`⚠️  ${username} (${userId}) - Missing personal code`);
      
      try {
        // Generate unique code
        let code = generateRandomCode();
        let attempts = 0;
        
        // Check for collisions
        while (attempts < 10) {
          const codeDoc = await db.collection('invite_codes').doc(code).get();
          
          if (!codeDoc.exists) {
            // Code is unique
            break;
          }
          
          console.log(`   🔄 Collision detected: ${code}, regenerating...`);
          code = generateRandomCode();
          attempts++;
        }
        
        if (attempts >= 10) {
          console.log(`   ❌ Failed to generate unique code after 10 attempts`);
          errors++;
          continue;
        }
        
        // Use a batch to ensure atomicity
        const batch = db.batch();
        
        // Create invite code document
        const codeRef = db.collection('invite_codes').doc(code);
        batch.set(codeRef, {
          code: code,
          type: 'personal',
          createdBy: userId,
          createdByUsername: username,
          maxUses: 5,
          usedCount: 0,
          usedBy: [],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: null,
          status: 'active'
        });
        
        // Update user profile
        const userRef = db.collection('users').doc(userId);
        batch.update(userRef, {
          personalInviteCode: code
        });
        
        // Commit batch
        await batch.commit();
        
        console.log(`   ✅ Generated code: ${code}`);
        codesGenerated++;
        
      } catch (error) {
        console.log(`   ❌ Error: ${error.message}`);
        errors++;
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 BACKFILL SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total users:              ${usersSnapshot.size}`);
    console.log(`Users without codes:      ${usersWithoutCode}`);
    console.log(`Codes generated:          ${codesGenerated}`);
    console.log(`Errors:                   ${errors}`);
    console.log('='.repeat(60));
    
    if (codesGenerated > 0) {
      console.log('\n✅ Backfill complete! All existing users now have personal invite codes.');
    } else if (usersWithoutCode === 0) {
      console.log('\n✅ All users already have personal invite codes. Nothing to do.');
    } else {
      console.log('\n⚠️  Some errors occurred. Check the output above.');
    }
    
  } catch (error) {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  }
  
  process.exit(0);
}

// Run the backfill
backfillPersonalCodes();

