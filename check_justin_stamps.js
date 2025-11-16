const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkJustinStamps() {
  try {
    // Get Justin's user info
    const userSnapshot = await db.collection('users')
      .where('username', '==', 'wholetjustincook')
      .get();
    
    if (userSnapshot.empty) {
      console.log('User not found!');
      return;
    }
    
    let justinUserId;
    userSnapshot.forEach(doc => {
      justinUserId = doc.id;
      console.log('Justin User ID:', justinUserId);
    });
    
    // Check Justin's collected stamps
    console.log('\n=== JUSTIN\'S COLLECTED STAMPS ===');
    const stampsSnapshot = await db.collection('users')
      .doc(justinUserId)
      .collection('stamps')
      .get();
    
    console.log('Total collected stamps:', stampsSnapshot.size);
    
    stampsSnapshot.forEach(doc => {
      const data = doc.data();
      console.log('\n---');
      console.log('Stamp ID:', doc.id);
      console.log('Name:', data.name);
      console.log('Has note field:', 'note' in data);
      console.log('Has notesFromOthers field:', 'notesFromOthers' in data);
      if (data.note) {
        console.log('Note content:', data.note);
      }
      if (data.notesFromOthers) {
        console.log('NotesFromOthers:', data.notesFromOthers);
      }
      console.log('All fields:', Object.keys(data));
    });
    
  } catch (error) {
    console.error('Error:', error);
  }
  
  process.exit(0);
}

checkJustinStamps();

