#!/usr/bin/env node

/**
 * Restore collected stamps for a user
 * 
 * Usage: node restore_collected_stamps.js <userId> <stampId1> <stampId2> ...
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function restoreStamps() {
    const args = process.argv.slice(2);
    
    if (args.length < 2) {
        console.log('Usage: node restore_collected_stamps.js <userId> <stampId1> <stampId2> ...');
        console.log('\nExample:');
        console.log('  node restore_collected_stamps.js mpd4k2n13adMFMY52nksmaQTbMQ2 us-ca-sf-ballast-coffee us-ca-sf-dolores-park');
        process.exit(1);
    }
    
    const userId = args[0];
    const stampIds = args.slice(1);
    
    console.log(`👤 Restoring stamps for user: ${userId}`);
    console.log(`📦 Stamps to restore: ${stampIds.length}\n`);
    
    const batch = db.batch();
    const now = new Date();
    
    for (const stampId of stampIds) {
        console.log(`   ✓ ${stampId}`);
        
        const stampRef = db
            .collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .doc(stampId);
        
        batch.set(stampRef, {
            stampId: stampId,
            collectedDate: now,
            userImageNames: [],
            userImagePaths: [],
            userNotes: '',
            likeCount: 0,
            commentCount: 0
        });
    }
    
    await batch.commit();
    
    console.log(`\n✅ Restored ${stampIds.length} stamps!\n`);
    
    process.exit(0);
}

restoreStamps().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

