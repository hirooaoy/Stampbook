#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkStampFields() {
    console.log('🔍 Checking stamp fields...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`Found ${collectedStamps.size} stamps\n`);
    
    for (const doc of collectedStamps.docs) {
        const data = doc.data();
        console.log(`📄 ${doc.id}`);
        console.log(`   userId: ${data.userId || 'MISSING!'}`);
        console.log(`   stampId: ${data.stampId || 'MISSING!'}`);
        console.log(`   collectedDate: ${data.collectedDate ? 'EXISTS' : 'MISSING!'}`);
        console.log('');
    }
    
    process.exit(0);
}

checkStampFields().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

