#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function deleteSnakeCaseSubcollection() {
    console.log('🗑️  Deleting collected_stamps (snake_case) subcollection...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const collected_stamps = await db
        .collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
    
    console.log(`Found ${collected_stamps.size} stamps to delete\n`);
    
    const batch = db.batch();
    
    for (const doc of collected_stamps.docs) {
        console.log(`   Deleting: ${doc.id}`);
        batch.delete(doc.ref);
    }
    
    await batch.commit();
    
    console.log(`\n✅ Deleted ${collected_stamps.size} stamps from collected_stamps\n`);
    console.log('The app should now use collectedStamps (camelCase) with the correct IDs.\n');
    
    process.exit(0);
}

deleteSnakeCaseSubcollection().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

