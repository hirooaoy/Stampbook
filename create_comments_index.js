const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

console.log('📝 Creating Firestore index for comments...\n');
console.log('Index configuration:');
console.log('  Collection: comments');
console.log('  Fields:');
console.log('    - postId (Ascending)');
console.log('    - createdAt (Ascending)\n');

console.log('⚠️  Unfortunately, Firestore indexes cannot be created via Admin SDK.');
console.log('    You must create them via the Firebase Console.\n');

console.log('🔧 Manual steps:');
console.log('1. Go to: https://console.firebase.google.com/project/stampbook-app/firestore/indexes');
console.log('2. Click "Add Index" button');
console.log('3. Set Collection ID: comments');
console.log('4. Add fields:');
console.log('   - Field: postId, Order: Ascending');
console.log('   - Field: createdAt, Order: Ascending');
console.log('5. Click "Create Index"');
console.log('6. Wait ~2 minutes for index to build\n');

console.log('✨ Or use the Firebase CLI (if installed):');
console.log('   Run: firebase deploy --only firestore:indexes\n');

process.exit(0);

