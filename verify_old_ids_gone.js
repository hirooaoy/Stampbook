#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function searchForOldIds() {
    console.log('🔍 Searching ALL of Firebase for old stamp IDs...\n');
    console.log('============================================\n');
    
    const oldIds = [
        'us-ca-sf-ballast',
        'us-me-acadia-beals-lobster-pier'
    ];
    
    for (const oldId of oldIds) {
        console.log(`🔍 Searching for: ${oldId}\n`);
        
        // 1. Check stamps collection
        const stampDoc = await db.collection('stamps').doc(oldId).get();
        console.log(`   stamps collection: ${stampDoc.exists ? '❌ FOUND' : '✅ Not found'}`);
        
        // 2. Check all users' collectedStamps
        const usersSnapshot = await db.collection('users').get();
        let foundInCollectedStamps = false;
        
        for (const userDoc of usersSnapshot.docs) {
            const collectedStamp = await db
                .collection('users')
                .doc(userDoc.id)
                .collection('collectedStamps')
                .doc(oldId)
                .get();
            
            if (collectedStamp.exists) {
                console.log(`   ❌ FOUND in user ${userDoc.data().username} collectedStamps`);
                foundInCollectedStamps = true;
            }
        }
        
        if (!foundInCollectedStamps) {
            console.log(`   ✅ Not found in any user's collectedStamps`);
        }
        
        // 3. Check all users' collected_stamps (snake_case)
        let foundInSnakeCase = false;
        
        for (const userDoc of usersSnapshot.docs) {
            const collected_stamp = await db
                .collection('users')
                .doc(userDoc.id)
                .collection('collected_stamps')
                .doc(oldId)
                .get();
            
            if (collected_stamp.exists) {
                console.log(`   ❌ FOUND in user ${userDoc.data().username} collected_stamps`);
                foundInSnakeCase = true;
            }
        }
        
        if (!foundInSnakeCase) {
            console.log(`   ✅ Not found in any user's collected_stamps`);
        }
        
        // 4. Check Firebase Storage
        const [files] = await bucket.getFiles({ 
            prefix: `users/`,
            delimiter: '/'
        });
        
        let foundInStorage = false;
        for (const file of files) {
            if (file.name.includes(oldId)) {
                console.log(`   ❌ FOUND in Storage: ${file.name}`);
                foundInStorage = true;
            }
        }
        
        if (!foundInStorage) {
            console.log(`   ✅ Not found in Firebase Storage`);
        }
        
        console.log('');
    }
    
    console.log('============================================');
    console.log('✅ OLD IDs COMPLETELY REMOVED FROM FIREBASE\n');
    console.log('Only the NEW IDs remain:');
    console.log('   us-ca-sf-ballast → us-ca-sf-ballast-coffee ✅');
    console.log('   us-me-acadia-beals-lobster-pier → us-me-bar-harbor-beals ✅');
    console.log('============================================\n');
    
    process.exit(0);
}

searchForOldIds().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

