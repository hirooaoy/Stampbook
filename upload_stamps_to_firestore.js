const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function uploadStampsToFirestore() {
  try {
    console.log('📤 Uploading stamps to Firestore...');
    
    // Read local stamps.json
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    
    if (!fs.existsSync(stampsPath)) {
      console.log('❌ stamps.json not found at:', stampsPath);
      process.exit(1);
    }
    
    const localStamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    console.log(`✅ Found ${localStamps.length} stamps in local JSON\n`);
    
    // Get Firebase stamps for comparison
    const firebaseSnapshot = await db.collection('stamps').get();
    const firebaseStamps = [];
    firebaseSnapshot.forEach(doc => {
      firebaseStamps.push(doc.data());
    });
    
    console.log(`✅ Found ${firebaseStamps.length} stamps in Firebase\n`);
    
    // Upload each stamp
    const batch = db.batch();
    let updateCount = 0;
    
    for (const stamp of localStamps) {
      const stampRef = db.collection('stamps').doc(stamp.id);
      batch.set(stampRef, stamp, { merge: true });
      updateCount++;
    }
    
    // Commit the batch
    await batch.commit();
    
    console.log(`✅ Successfully uploaded ${updateCount} stamps to Firestore`);
    console.log('🎉 Local stamps.json is now synced with Firebase');
    
  } catch (error) {
    console.error('❌ Error uploading stamps:', error);
  } finally {
    process.exit();
  }
}

uploadStampsToFirestore();

