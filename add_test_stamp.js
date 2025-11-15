const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

const db = admin.firestore();

async function addTestStamp() {
  const testStamp = {
    id: 'test-animation-stamp',
    name: 'Test Animation Stamp',
    latitude: 37.7749,  // San Francisco
    longitude: -122.4194,
    address: '1 Market St, San Francisco, CA 94105',
    imageName: '',
    imageUrl: 'https://firebasestorage.googleapis.com/v0/b/stampbook-439requency17.appspot.com/o/stamps%2Fus-ca-sf-oracle-park.png?alt=media',
    imageStoragePath: 'stamps/us-ca-sf-oracle-park.png',  // Reuse Oracle Park image
    collectionIds: ['test-collection'],
    about: 'A test stamp to verify collection animation works perfectly!',
    thingsToDoFromEditors: ['Test the 1.5→1.0 scale animation', 'Verify no layout shift'],
    geohash: 'dr5ru',
    collectionRadius: 'xlarge',  // 3km radius so you can collect from anywhere nearby
    status: 'active'
  };

  console.log('📝 Creating test stamp...');
  
  await db.collection('stamps').doc(testStamp.id).set(testStamp);
  console.log('✅ Test stamp created:', testStamp.id);
  
  console.log('\n🎯 To test collection animation:');
  console.log('1. Open app on test account');
  console.log('2. Go to Map view');
  console.log('3. Look for "Test Animation Stamp" near SF');
  console.log('4. Tap it → tap "Collect"');
  console.log('5. Watch for smooth 1.5→1.0 scale animation with no layout shift!');
  console.log('\n📍 Location: San Francisco (3km radius, easy to collect)');
  
  process.exit(0);
}

addTestStamp().catch(error => {
  console.error('❌ Error:', error);
  process.exit(1);
});

