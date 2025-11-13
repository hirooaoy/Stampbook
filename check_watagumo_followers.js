const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkWatagumoFollowers() {
  try {
    // Watagumo's user ID
    const userId = 'LGp7cMqB2tSEVU1O7NEvR0Xib7y2';
    
    // Get Watagumo's profile
    const profileDoc = await db.collection('users').doc(userId).get();
    const profile = profileDoc.data();
    
    console.log('\n========================================');
    console.log('WATAGUMO PROFILE DATA');
    console.log('========================================');
    console.log(`Username: ${profile.username}`);
    console.log(`Display Name: ${profile.displayName}`);
    console.log(`Follower Count (denormalized): ${profile.followerCount}`);
    console.log(`Following Count (denormalized): ${profile.followingCount}`);
    
    // Query actual followers collection
    const followersSnapshot = await db.collection('users').doc(userId).collection('followers').get();
    console.log(`\nActual Followers (queried): ${followersSnapshot.size}`);
    
    if (!followersSnapshot.empty) {
      console.log('\nFollowers list:');
      for (const doc of followersSnapshot.docs) {
        const followerDoc = await db.collection('users').doc(doc.id).get();
        const followerData = followerDoc.data();
        console.log(`  - ${followerData.username} (${doc.id})`);
      }
    }
    
    // Query actual following collection  
    const followingSnapshot = await db.collection('users').doc(userId).collection('following').get();
    console.log(`\nActual Following (queried): ${followingSnapshot.size}`);
    
    if (!followingSnapshot.empty) {
      console.log('\nFollowing list:');
      for (const doc of followingSnapshot.docs) {
        const followeeDoc = await db.collection('users').doc(doc.id).get();
        const followeeData = followeeDoc.data();
        console.log(`  - ${followeeData.username} (${doc.id})`);
      }
    }
    
    console.log('\n========================================');
    console.log('DIAGNOSIS');
    console.log('========================================');
    
    if (profile.followerCount !== followersSnapshot.size) {
      console.log(`❌ MISMATCH: Profile shows ${profile.followerCount} followers but actually has ${followersSnapshot.size}`);
      console.log(`   Cloud Function may have failed to update denormalized count`);
    } else {
      console.log(`✅ Follower count is in sync`);
    }
    
    if (profile.followingCount !== followingSnapshot.size) {
      console.log(`❌ MISMATCH: Profile shows ${profile.followingCount} following but actually following ${followingSnapshot.size}`);
      console.log(`   Cloud Function may have failed to update denormalized count`);
    } else {
      console.log(`✅ Following count is in sync`);
    }
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

checkWatagumoFollowers();

