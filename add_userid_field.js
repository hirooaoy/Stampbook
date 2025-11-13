#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function addUserIdField() {
    console.log('🔧 Adding userId field to all stamps...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    const batch = db.batch();
    
    for (const doc of collectedStamps.docs) {
        console.log(`✓ Adding userId to ${doc.id}`);
        batch.update(doc.ref, { userId: userId });
    }
    
    await batch.commit();
    
    console.log(`\n✅ Added userId field to ${collectedStamps.size} stamps\n`);
    
    process.exit(0);
}

addUserIdField().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

