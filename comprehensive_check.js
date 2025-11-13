#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function comprehensiveCheck() {
    console.log('🔍 COMPREHENSIVE FIREBASE CHECK\n');
    console.log('============================================\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // 1. CHECK STAMPS COLLECTION
    console.log('📚 STAMPS COLLECTION - Looking for ballast and beals:\n');
    
    const allStamps = await db.collection('stamps').get();
    const ballastStamps = [];
    const bealsStamps = [];
    
    for (const doc of allStamps.docs) {
        const id = doc.id;
        const name = doc.data().name;
        
        if (id.includes('ballast')) {
            ballastStamps.push({ id, name });
        }
        if (id.includes('beal')) {
            bealsStamps.push({ id, name });
        }
    }
    
    console.log('Ballast stamps in system:');
    ballastStamps.forEach(s => console.log(`   ${s.id} - "${s.name}"`));
    
    console.log('\nBeal\'s stamps in system:');
    bealsStamps.forEach(s => console.log(`   ${s.id} - "${s.name}"`));
    
    console.log('\n============================================\n');
    
    // 2. CHECK USER DOCUMENT
    console.log('👤 USER DOCUMENT FIELDS:\n');
    
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data();
    
    console.log('All fields in user document:');
    Object.keys(userData).forEach(key => {
        if (key.toLowerCase().includes('stamp') || key.toLowerCase().includes('collect')) {
            console.log(`   ${key}: ${JSON.stringify(userData[key])}`);
        }
    });
    
    console.log('\n============================================\n');
    
    // 3. CHECK COLLECTED STAMPS SUBCOLLECTION
    console.log('📦 COLLECTED STAMPS SUBCOLLECTION:\n');
    
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`Total stamps: ${collectedStamps.size}`);
    collectedStamps.docs.forEach(doc => {
        console.log(`   ${doc.id}`);
    });
    
    console.log('\n============================================\n');
    
    // 4. CHECK FIREBASE STORAGE
    console.log('💾 FIREBASE STORAGE FOLDERS:\n');
    
    const [files] = await bucket.getFiles({ 
        prefix: `users/${userId}/stamps/`,
        delimiter: '/'
    });
    
    const folders = new Set();
    files.forEach(file => {
        const parts = file.name.split('/');
        if (parts.length >= 4) {
            folders.add(parts[3]); // stamp folder name
        }
    });
    
    console.log('Stamp folders in storage:');
    [...folders].sort().forEach(folder => {
        console.log(`   ${folder}`);
    });
    
    console.log('\n============================================\n');
    
    // 5. CHECK USER STATISTICS
    console.log('📊 USER STATISTICS:\n');
    console.log(`   totalStampsCollected: ${userData.totalStampsCollected || 0}`);
    console.log(`   totalCountries: ${userData.totalCountries || 0}`);
    
    console.log('\n============================================\n');
    console.log('🎯 SUMMARY:\n');
    console.log(`Stamps in system with "ballast": ${ballastStamps.length}`);
    console.log(`Stamps in system with "beal": ${bealsStamps.length}`);
    console.log(`Stamps in user collection: ${collectedStamps.size}`);
    console.log(`User totalStampsCollected field: ${userData.totalStampsCollected || 0}`);
    console.log(`Storage folders: ${folders.size}`);
    
    console.log('\n❓ ISSUE: User has collected 6 stamps but totalStampsCollected = 0');
    console.log('   This might be why the app isn\'t showing them!\n');
    
    process.exit(0);
}

comprehensiveCheck().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

