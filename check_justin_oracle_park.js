const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkJustinStampDetail() {
  try {
    const justinUserId = 'ziI5xSvHhyXZ9MbKDDX9sKvHSjC3';
    const stampId = 'us-ca-sf-oracle-park';
    
    console.log('=== CHECKING SPECIFIC STAMP ===');
    console.log('User ID:', justinUserId);
    console.log('Stamp ID:', stampId, '\n');
    
    const stampDoc = await db.collection('users')
      .doc(justinUserId)
      .collection('stamps')
      .doc(stampId)
      .get();
    
    if (!stampDoc.exists) {
      console.log('❌ Stamp not found');
      return;
    }
    
    const data = stampDoc.data();
    console.log('✅ Stamp found!');
    console.log('');
    console.log('All fields:');
    Object.keys(data).forEach(key => {
      console.log(`  ${key}:`, typeof data[key] === 'object' ? JSON.stringify(data[key]) : data[key]);
    });
    
    console.log('\n=== NOTE FIELDS ===');
    console.log('Has "note":', 'note' in data);
    console.log('Has "userNotes":', 'userNotes' in data);
    console.log('Has "notesFromOthers":', 'notesFromOthers' in data);
    
    if (data.note) {
      console.log('note content:', data.note);
    }
    if (data.userNotes) {
      console.log('userNotes content:', data.userNotes);
    }
    if (data.notesFromOthers) {
      console.log('notesFromOthers content:', data.notesFromOthers);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkJustinStampDetail();

