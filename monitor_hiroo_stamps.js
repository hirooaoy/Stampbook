const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function monitorHirooStamps() {
  console.log('👀 Monitoring hiroo\'s stamps in real-time...\n');
  
  const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
  
  // Set up a listener
  const unsubscribe = db
    .collection('users')
    .doc(userId)
    .collection('collected_stamps')
    .onSnapshot(snapshot => {
      console.log(`\n📸 Snapshot at ${new Date().toLocaleTimeString()}`);
      console.log(`   Total stamps: ${snapshot.size}`);
      console.log(`   Stamp IDs:`);
      snapshot.docs.forEach(doc => {
        const data = doc.data();
        console.log(`     - ${doc.id} (collected: ${data.collectedDate?.toDate?.() || 'unknown'})`);
      });
      
      // Check if your-first-stamp appeared
      const hasFirstStamp = snapshot.docs.some(doc => doc.id === 'your-first-stamp');
      if (hasFirstStamp) {
        console.log('\n⚠️  WARNING: your-first-stamp RE-APPEARED in Firebase!');
        console.log('    This means the app is re-uploading it from local cache.');
      }
    });
  
  console.log('Listening for changes... (Press Ctrl+C to stop)\n');
  
  // Keep the script running
  await new Promise(() => {});
}

monitorHirooStamps();

