#!/usr/bin/env node

/**
 * Check if Dylan liked his own Powell Hyde Cable Car post
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function checkDylanPowellHydeLike() {
  try {
    const dylanId = 'bT76nSxOaQOLT8sgJmB7TeLuFcQ2';
    const stampId = 'us-ca-sf-powell-hyde-cable-car';
    
    console.log('\n🔍 Checking if Dylan liked his own Powell Hyde Cable Car post...\n');
    
    // First, check if Dylan has collected this stamp
    const stampDoc = await db.collection('users').doc(dylanId).collection('collectedStamps').doc(stampId).get();
    
    if (!stampDoc.exists) {
      console.log('❌ Dylan has not collected the Powell Hyde Cable Car stamp');
      console.log('   (No post exists, so no like is possible)\n');
      return;
    }
    
    const stampData = stampDoc.data();
    console.log('✅ Dylan has collected this stamp');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`Stamp ID:      ${stampId}`);
    console.log(`Collected:     ${stampData.collectedDate?.toDate() || 'N/A'}`);
    console.log(`Like Count:    ${stampData.likeCount || 0}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    // Construct postId (format: "{userId}-{stampId}")
    const postId = `${dylanId}-${stampId}`;
    console.log(`Post ID: ${postId}\n`);
    
    // Check if Dylan liked his own post
    // Like document ID format: "{userId}_{postId}"
    const likeDocId = `${dylanId}_${postId}`;
    const likeDoc = await db.collection('likes').doc(likeDocId).get();
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('LIKE CHECK');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    if (likeDoc.exists) {
      const likeData = likeDoc.data();
      console.log('✅ YES - Dylan liked his own post!');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log(`Like Document ID: ${likeDocId}`);
      console.log(`User ID:          ${likeData.userId}`);
      console.log(`Post ID:          ${likeData.postId}`);
      console.log(`Post Owner ID:    ${likeData.postOwnerId}`);
      console.log(`Created At:       ${likeData.createdAt?.toDate() || 'N/A'}`);
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      if (likeData.userId === likeData.postOwnerId) {
        console.log('⚠️  Note: Dylan liked his own post (self-like)\n');
      }
    } else {
      console.log('❌ NO - Dylan did not like his own post');
      console.log(`   (No like document found with ID: ${likeDocId})\n`);
    }
    
    // Also check all likes on this post for context
    const allLikesSnapshot = await db.collection('likes')
      .where('postId', '==', postId)
      .get();
    
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('ALL LIKES ON THIS POST');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    console.log(`Total likes: ${allLikesSnapshot.size}\n`);
    
    if (allLikesSnapshot.empty) {
      console.log('No likes found on this post\n');
    } else {
      for (const doc of allLikesSnapshot.docs) {
        const likeData = doc.data();
        const likerDoc = await db.collection('users').doc(likeData.userId).get();
        const likerData = likerDoc.data();
        
        const isSelfLike = likeData.userId === likeData.postOwnerId;
        const marker = isSelfLike ? '🔴' : '  ';
        
        console.log(`${marker} @${likerData.username} (${likerData.displayName})`);
        if (isSelfLike) {
          console.log(`   ⚠️  Self-like`);
        }
        console.log(`   Liked at: ${likeData.createdAt?.toDate() || 'N/A'}\n`);
      }
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

checkDylanPowellHydeLike()
  .then(() => {
    console.log('✅ Check complete\n');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

