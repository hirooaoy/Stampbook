const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function listAllUsers() {
  try {
    console.log('👥 ALL USERS IN DATABASE:\n');
    
    const usersSnapshot = await db.collection('users').get();
    
    usersSnapshot.docs.forEach((doc, index) => {
      const data = doc.data();
      console.log(`${index + 1}. @${data.username} (${data.displayName})`);
      console.log(`   userId: ${doc.id}`);
      console.log(`   email: Check Auth`);
      console.log(`   stamps: ${data.totalStamps}`);
      console.log('');
    });
    
    console.log(`Total users: ${usersSnapshot.size}\n`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    process.exit(0);
  }
}

listAllUsers();

