#!/usr/bin/env node

/**
 * Clear Follow Count Cache Script
 * 
 * This script helps identify stale cached follow counts in the iOS app.
 * The actual cache is stored in UserDefaults on the device, so this script
 * just verifies what the correct counts should be from Firebase.
 * 
 * To fix the issue on the device:
 * 1. Force quit the app
 * 2. Re-open the app (it will refresh counts from Firebase)
 * OR
 * 3. Sign out and sign back in (clears all cached data)
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function verifyFollowCounts() {
  try {
    console.log('\n🔍 Verifying follow counts for all users...\n');
    
    const usersSnapshot = await db.collection('users').get();
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      // Get actual follower count
      const followersSnapshot = await db.collection('users').doc(userId).collection('followers').get();
      const actualFollowers = followersSnapshot.size;
      
      // Get actual following count
      const followingSnapshot = await db.collection('users').doc(userId).collection('following').get();
      const actualFollowing = followingSnapshot.size;
      
      // Check for mismatches
      const followerMismatch = userData.followerCount !== actualFollowers;
      const followingMismatch = userData.followingCount !== actualFollowing;
      
      if (followerMismatch || followingMismatch) {
        console.log(`❌ MISMATCH: @${userData.username} (${userId})`);
        if (followerMismatch) {
          console.log(`   Followers: field=${userData.followerCount}, actual=${actualFollowers}`);
        }
        if (followingMismatch) {
          console.log(`   Following: field=${userData.followingCount}, actual=${actualFollowing}`);
        }
        console.log('');
      } else {
        console.log(`✅ @${userData.username}: followers=${actualFollowers}, following=${actualFollowing}`);
      }
    }
    
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('CORRECT COUNTS FROM FIREBASE');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    for (const userDoc of usersSnapshot.docs) {
      const userData = userDoc.data();
      const userId = userDoc.id;
      
      const followersSnapshot = await db.collection('users').doc(userId).collection('followers').get();
      const followingSnapshot = await db.collection('users').doc(userId).collection('following').get();
      
      console.log(`@${userData.username}:`);
      console.log(`  Followers: ${followersSnapshot.size}`);
      console.log(`  Following: ${followingSnapshot.size}`);
      console.log('');
    }
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('HOW TO FIX STALE CACHE ON DEVICE');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('');
    console.log('The follow counts are cached in UserDefaults on your device.');
    console.log('To clear stale cache and show correct counts:');
    console.log('');
    console.log('OPTION 1 (Quick):');
    console.log('  1. Force quit the Stampbook app');
    console.log('  2. Re-open the app');
    console.log('  3. Navigate to the profile again');
    console.log('     → The app will fetch fresh counts from Firebase');
    console.log('');
    console.log('OPTION 2 (Thorough):');
    console.log('  1. Sign out of the app');
    console.log('  2. Sign back in');
    console.log('     → This clears ALL cached data including follow counts');
    console.log('');
    console.log('OPTION 3 (Developer):');
    console.log('  1. Delete the app from your device');
    console.log('  2. Reinstall from Xcode');
    console.log('     → Fresh install with no cache');
    console.log('');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

verifyFollowCounts()
  .then(() => {
    console.log('✅ Verification complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

