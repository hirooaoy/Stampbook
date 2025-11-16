const admin = require('firebase-admin');

// Initialize Firebase Admin (reuse existing credentials)
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function findAllUsersWithPhotos() {
  console.log('🔍 Scanning all users for photos...\n');
  
  try {
    // Get all users from Firestore
    const usersSnapshot = await db.collection('users').get();
    
    console.log(`📊 Found ${usersSnapshot.size} total users\n`);
    
    const usersWithPhotos = [];
    
    // Check each user for collected stamps with photos
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      const username = userData.username || 'unknown';
      
      // Get user's collected stamps
      const stampsSnapshot = await db.collection('users').doc(userId).collection('collectedStamps').get();
      
      let photoCount = 0;
      for (const stampDoc of stampsSnapshot.docs) {
        const stampData = stampDoc.data();
        const userImagePaths = stampData.userImagePaths || [];
        photoCount += userImagePaths.length;
      }
      
      if (photoCount > 0) {
        usersWithPhotos.push({
          userId,
          username,
          photoCount,
          stampCount: stampsSnapshot.size
        });
        console.log(`✅ ${username} (@${userId.substring(0, 8)}...): ${photoCount} photos across ${stampsSnapshot.size} stamps`);
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log(`📸 Summary: ${usersWithPhotos.length} users have photos`);
    console.log('='.repeat(60));
    
    if (usersWithPhotos.length > 0) {
      console.log('\nTo fix all users, run:');
      usersWithPhotos.forEach(user => {
        console.log(`  node fix_firebase_thumbnails.js --user ${user.userId}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

findAllUsersWithPhotos();

