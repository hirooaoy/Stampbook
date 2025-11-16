const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkCollectedStamps() {
  try {
    const justinUserId = 'ziI5xSvHhyXZ9MbKDDX9sKvHSjC3';
    
    console.log('=== CHECKING COLLECTEDSTAMPS SUBCOLLECTION ===');
    console.log('User: wholetjustincook');
    console.log('User ID:', justinUserId, '\n');
    
    const collectedStamps = await db.collection('users')
      .doc(justinUserId)
      .collection('collectedStamps')
      .get();
    
    console.log('Total documents:', collectedStamps.size, '\n');
    
    collectedStamps.forEach(doc => {
      const data = doc.data();
      console.log('---');
      console.log('Document ID:', doc.id);
      console.log('Stamp ID:', data.stampId);
      console.log('Collected Date:', data.collectedDate?.toDate?.() || data.collectedDate);
      console.log('');
      console.log('Note fields:');
      console.log('  Has "note":', 'note' in data);
      console.log('  Has "userNotes":', 'userNotes' in data);
      console.log('  Has "notesFromOthers":', 'notesFromOthers' in data);
      
      if (data.note) {
        console.log('  note:', data.note);
      }
      if (data.userNotes) {
        console.log('  userNotes:', data.userNotes);
      }
      if (data.notesFromOthers) {
        console.log('  notesFromOthers:', data.notesFromOthers);
      }
      
      console.log('\nAll fields:', Object.keys(data).join(', '));
      console.log('');
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkCollectedStamps();

