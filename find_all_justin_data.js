const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function findAllJustinData() {
  try {
    console.log('=== SEARCHING FOR JUSTIN ===\n');
    
    // Search by username
    const users = await db.collection('users')
      .where('username', '==', 'wholetjustincook')
      .get();
    
    if (users.empty) {
      console.log('❌ No user found with username "wholetjustincook"');
      
      // Try searching for similar usernames
      console.log('\n=== SEARCHING FOR SIMILAR USERNAMES ===');
      const allUsers = await db.collection('users').get();
      allUsers.forEach(doc => {
        const data = doc.data();
        if (data.username && data.username.toLowerCase().includes('justin')) {
          console.log('Found:', data.username, '(ID:', doc.id, ')');
        }
      });
      return;
    }
    
    let justinUserId;
    users.forEach(doc => {
      const data = doc.data();
      justinUserId = doc.id;
      console.log('✅ Found Justin');
      console.log('User ID:', doc.id);
      console.log('Username:', data.username);
      console.log('Display Name:', data.displayName);
      console.log('Total Stamps:', data.totalStamps || 0);
      console.log('Countries:', data.totalCountries || 0);
      console.log('Created:', data.createdAt?.toDate?.() || data.createdAt);
      console.log('');
    });
    
    // Check all subcollections
    console.log('=== CHECKING SUBCOLLECTIONS ===\n');
    
    // 1. stamps subcollection
    const stamps = await db.collection('users').doc(justinUserId).collection('stamps').get();
    console.log('stamps:', stamps.size, 'documents');
    
    // 2. following
    const following = await db.collection('users').doc(justinUserId).collection('following').get();
    console.log('following:', following.size, 'documents');
    
    // 3. followers
    const followers = await db.collection('users').doc(justinUserId).collection('followers').get();
    console.log('followers:', followers.size, 'documents');
    
    // Check top-level collections
    console.log('\n=== CHECKING TOP-LEVEL COLLECTIONS ===\n');
    
    // Feed posts
    const feedPosts = await db.collection('feed').where('userId', '==', justinUserId).get();
    console.log('feed posts:', feedPosts.size, 'documents');
    if (feedPosts.size > 0) {
      feedPosts.forEach(doc => {
        const data = doc.data();
        console.log('  - Post:', data.stampName, '| note:', data.note || 'none', '| notesFromOthers:', data.notesFromOthers || 'none');
      });
    }
    
    // Notifications
    const notifications = await db.collection('notifications').where('userId', '==', justinUserId).get();
    console.log('notifications:', notifications.size, 'documents');
    
    // Activity log
    const activity = await db.collection('activity').where('userId', '==', justinUserId).get();
    console.log('activity:', activity.size, 'documents');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

findAllJustinData();

