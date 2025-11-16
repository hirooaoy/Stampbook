const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkFeedCollection() {
  try {
    console.log('=== CHECKING ENTIRE FEED COLLECTION ===\n');
    
    const feedSnapshot = await db.collection('feed').get();
    console.log('Total documents in feed:', feedSnapshot.size, '\n');
    
    feedSnapshot.forEach(doc => {
      const data = doc.data();
      console.log('---');
      console.log('Document ID:', doc.id);
      console.log('User ID:', data.userId);
      console.log('Username:', data.username);
      console.log('Stamp ID:', data.stampId);
      console.log('Stamp Name:', data.stampName);
      console.log('Has note:', 'note' in data);
      console.log('Has userNotes:', 'userNotes' in data);
      console.log('Has notesFromOthers:', 'notesFromOthers' in data);
      if (data.note) console.log('  note:', data.note);
      if (data.userNotes) console.log('  userNotes:', data.userNotes);
      if (data.notesFromOthers) console.log('  notesFromOthers:', data.notesFromOthers);
      console.log('Created:', data.createdAt?.toDate?.() || data.createdAt);
      console.log('');
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

checkFeedCollection();

