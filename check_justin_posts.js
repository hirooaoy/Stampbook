const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkJustinPosts() {
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
    
    // Check feed posts for Justin
    console.log('\n=== CHECKING FEED POSTS FOR JUSTIN ===');
    const postsSnapshot = await db.collection('feed')
      .where('userId', '==', justinUserId)
      .get();
    
    console.log('Total posts by Justin:', postsSnapshot.size);
    
    postsSnapshot.forEach(doc => {
      const data = doc.data();
      console.log('\n---');
      console.log('Post ID:', doc.id);
      console.log('Type:', data.type);
      console.log('Stamp Name:', data.stampName);
      console.log('Has note field:', 'note' in data);
      console.log('Has notesFromOthers field:', 'notesFromOthers' in data);
      if (data.note) {
        console.log('Note content:', data.note);
      }
      if (data.notesFromOthers) {
        console.log('NotesFromOthers:', data.notesFromOthers);
      }
      console.log('Created:', data.createdAt?.toDate?.() || data.createdAt);
      console.log('All fields:', Object.keys(data));
    });
    
  } catch (error) {
    console.error('Error:', error);
  }
  
  process.exit(0);
}

checkJustinPosts();

