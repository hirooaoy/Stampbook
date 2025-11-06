const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function removeGuerreroStamp() {
  console.log('🗑️  Removing test-stamp-guerrero from hiroo\'s collection...\n');
  
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo's actual Firebase UID
  const stampId = 'test-stamp-guerrero';
  
  try {
    // 1. Delete the collected stamp document
    const collectedStampRef = db.collection('users').doc(userId).collection('collected_stamps').doc(stampId);
    const collectedStampDoc = await collectedStampRef.get();
    
    if (!collectedStampDoc.exists) {
      console.log(`⚠️  Stamp "${stampId}" not found in hiroo's collection`);
    } else {
      console.log(`✅ Found collected stamp: ${stampId}`);
      await collectedStampRef.delete();
      console.log(`✅ Deleted collected stamp document`);
    }
    
    // 2. Update stamp statistics
    const statsRef = db.collection('stamp_statistics').doc(stampId);
    const statsDoc = await statsRef.get();
    
    if (statsDoc.exists) {
      const stats = statsDoc.data();
      const collectorUserIds = stats.collectorUserIds || [];
      const totalCollectors = stats.totalCollectors || 0;
      
      if (collectorUserIds.includes(userId)) {
        const updatedCollectorUserIds = collectorUserIds.filter(id => id !== userId);
        const updatedTotalCollectors = Math.max(0, totalCollectors - 1);
        
        await statsRef.update({
          collectorUserIds: updatedCollectorUserIds,
          totalCollectors: updatedTotalCollectors
        });
        
        console.log(`✅ Updated stamp statistics (removed hiroo from collectors)`);
        console.log(`   - Total collectors: ${totalCollectors} → ${updatedTotalCollectors}`);
      } else {
        console.log(`⚠️  hiroo was not in the collectors list for this stamp`);
      }
    } else {
      console.log(`⚠️  No statistics document found for stamp ${stampId}`);
    }
    
    // 3. Update user profile to decrement total stamps count
    const userRef = db.collection('users').doc(userId);
    const userDoc = await userRef.get();
    
    if (userDoc.exists) {
      const userData = userDoc.data();
      const totalStamps = userData.totalStamps || 0;
      const updatedTotalStamps = Math.max(0, totalStamps - 1);
      
      await userRef.update({
        totalStamps: updatedTotalStamps
      });
      
      console.log(`✅ Updated user profile`);
      console.log(`   - Total stamps: ${totalStamps} → ${updatedTotalStamps}`);
    } else {
      console.log(`⚠️  User profile not found for ${userId}`);
    }
    
    // 4. Delete any likes on this post
    const likesSnapshot = await db.collection('likes')
      .where('collectedStampUserId', '==', userId)
      .where('stampId', '==', stampId)
      .get();
    
    if (!likesSnapshot.empty) {
      const batch = db.batch();
      likesSnapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
      });
      await batch.commit();
      console.log(`✅ Deleted ${likesSnapshot.size} like(s) on this post`);
    } else {
      console.log(`ℹ️  No likes found on this post`);
    }
    
    // 5. Delete any comments on this post
    const commentsSnapshot = await db.collection('comments')
      .where('collectedStampUserId', '==', userId)
      .where('stampId', '==', stampId)
      .get();
    
    if (!commentsSnapshot.empty) {
      const batch = db.batch();
      commentsSnapshot.docs.forEach(doc => {
        batch.delete(doc.ref);
      });
      await batch.commit();
      console.log(`✅ Deleted ${commentsSnapshot.size} comment(s) on this post`);
    } else {
      console.log(`ℹ️  No comments found on this post`);
    }
    
    console.log('\n✅ Successfully removed test-stamp-guerrero from hiroo\'s collection!');
    
    // 6. Now check what's left
    console.log('\n📋 Checking remaining stamps...\n');
    const remainingStamps = await db
      .collection('users')
      .doc(userId)
      .collection('collected_stamps')
      .get();
    
    console.log(`✅ Hiroo now has ${remainingStamps.size} stamps:`);
    remainingStamps.docs.forEach(doc => {
      console.log(`   - ${doc.id}`);
    });
    
    // Check profile
    const updatedUserDoc = await userRef.get();
    if (updatedUserDoc.exists) {
      const userData = updatedUserDoc.data();
      console.log(`\n📊 Profile shows: ${userData.totalStamps} total stamps`);
    }
    
    console.log('\n⚠️  IMPORTANT: Hiroo needs to FORCE CLOSE the app and reopen it.');
    console.log('    Or go to Profile → pull down to refresh to clear the local cache.\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

removeGuerreroStamp();

