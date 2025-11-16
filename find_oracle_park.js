const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function findOraclePark() {
  try {
    console.log('=== SEARCHING FOR ORACLE PARK ===\n');
    
    // Check feed collection
    console.log('1. Checking feed collection...');
    const feed = await db.collection('feed')
      .where('stampId', '==', 'us-ca-sf-oracle-park')
      .get();
    console.log('   Found in feed:', feed.size);
    feed.forEach(doc => {
      console.log('   Doc ID:', doc.id);
      console.log('   Data:', JSON.stringify(doc.data(), null, 2));
    });
    
    // Check activity collection
    console.log('\n2. Checking activity collection...');
    const activity = await db.collection('activity')
      .where('stampId', '==', 'us-ca-sf-oracle-park')
      .get();
    console.log('   Found in activity:', activity.size);
    activity.forEach(doc => {
      console.log('   Doc ID:', doc.id);
      const data = doc.data();
      console.log('   Type:', data.type);
      console.log('   Username:', data.username);
      console.log('   Has userNotes:', 'userNotes' in data);
      if (data.userNotes) console.log('   userNotes:', data.userNotes);
    });
    
    // Search in stamps collection (main)
    console.log('\n3. Checking main stamps collection...');
    const stamps = await db.collection('stamps')
      .where('stampId', '==', 'us-ca-sf-oracle-park')
      .get();
    console.log('   Found in stamps:', stamps.size);
    
    // Try to get the specific document by ID
    console.log('\n4. Trying to get us-ca-sf-oracle-park directly from stamps...');
    const stampDoc = await db.collection('stamps').doc('us-ca-sf-oracle-park').get();
    if (stampDoc.exists) {
      console.log('   ✅ Found!');
      console.log('   Name:', stampDoc.data().name);
    } else {
      console.log('   ❌ Not found');
    }
    
    // List all collections at root
    console.log('\n5. Listing all root collections...');
    const collections = await db.listCollections();
    console.log('   Root collections:', collections.map(c => c.id).join(', '));
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

findOraclePark();

