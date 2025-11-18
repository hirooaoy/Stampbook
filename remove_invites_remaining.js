// remove_invites_remaining.js
// Removes the unused 'invitesRemaining' field from all user profiles

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function removeInvitesRemaining() {
  console.log('🧹 Removing unused invitesRemaining field from all users...\n');
  
  try {
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`📊 Found ${usersSnapshot.size} total users\n`);
    
    let usersWithField = 0;
    let removed = 0;
    let errors = 0;
    
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const username = userData.username || 'unknown';
      
      // Check if user has the field
      if (!('invitesRemaining' in userData)) {
        console.log(`✅ ${username} (${userId}) - Already clean (no invitesRemaining field)`);
        continue;
      }
      
      usersWithField++;
      console.log(`🧹 ${username} (${userId}) - Has invitesRemaining: ${userData.invitesRemaining}`);
      
      try {
        // Remove the field
        await db.collection('users').doc(userId).update({
          invitesRemaining: admin.firestore.FieldValue.delete()
        });
        
        console.log(`   ✅ Removed invitesRemaining field`);
        removed++;
        
      } catch (error) {
        console.log(`   ❌ Error: ${error.message}`);
        errors++;
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 CLEANUP SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total users:              ${usersSnapshot.size}`);
    console.log(`Users with field:         ${usersWithField}`);
    console.log(`Fields removed:           ${removed}`);
    console.log(`Errors:                   ${errors}`);
    console.log('='.repeat(60));
    
    if (removed > 0) {
      console.log('\n✅ Cleanup complete! All user profiles are now clean.');
    } else if (usersWithField === 0) {
      console.log('\n✅ All users already clean. Nothing to do.');
    } else {
      console.log('\n⚠️  Some errors occurred. Check the output above.');
    }
    
  } catch (error) {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  }
  
  process.exit(0);
}

// Run the cleanup
removeInvitesRemaining();

