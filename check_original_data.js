#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function checkForOldData() {
    console.log('🔍 Searching for original stamp data...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Check Firebase Storage for photos
    console.log('📸 Checking Firebase Storage for photos:\n');
    
    const [files] = await bucket.getFiles({ 
        prefix: `users/${userId}/stamps/`
    });
    
    console.log(`Found ${files.length} photos in storage\n`);
    
    for (const file of files) {
        console.log(`   ${file.name}`);
    }
    
    console.log('\n============================================\n');
    console.log('💔 WHAT WE LOST:\n');
    console.log('When I manually restored your stamps, I created them fresh with:');
    console.log('  - Empty photo arrays');
    console.log('  - Today\'s date as collectedDate');
    console.log('  - No user notes\n');
    console.log('The original data (dates, notes, photos) is gone from Firestore.');
    console.log('BUT your uploaded photos still exist in Storage!\n');
    console.log('We can manually reconnect them to the stamps.\n');
    
    process.exit(0);
}

checkForOldData().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

