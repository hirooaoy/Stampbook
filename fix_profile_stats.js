#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixProfileStats() {
    console.log('🔧 Fixing hiroo profile stats...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Count actual stamps
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`📦 Found ${collectedStamps.size} stamps in collectedStamps\n`);
    
    // Update user profile
    await db.collection('users').doc(userId).update({
        totalStampsCollected: collectedStamps.size,
        totalStamps: collectedStamps.size
    });
    
    console.log('✅ Updated user profile stats\n');
    console.log(`   totalStampsCollected: ${collectedStamps.size}`);
    console.log(`   totalStamps: ${collectedStamps.size}\n`);
    
    process.exit(0);
}

fixProfileStats().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

