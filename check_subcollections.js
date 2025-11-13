#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkBothSubcollections() {
    console.log('🔍 Checking for BOTH subcollection names...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Check collectedStamps
    console.log('📦 collectedStamps (camelCase):');
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`   Found: ${collectedStamps.size} stamps`);
    if (collectedStamps.size > 0) {
        collectedStamps.docs.forEach(doc => {
            console.log(`      - ${doc.id}`);
        });
    }
    
    console.log('');
    
    // Check collected_stamps
    console.log('📦 collected_stamps (snake_case):');
    const collected_stamps = await db
        .collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
    
    console.log(`   Found: ${collected_stamps.size} stamps`);
    if (collected_stamps.size > 0) {
        collected_stamps.docs.forEach(doc => {
            console.log(`      - ${doc.id}`);
        });
    }
    
    console.log('\n============================================');
    
    if (collectedStamps.size > 0 && collected_stamps.size > 0) {
        console.log('⚠️  WARNING: BOTH subcollections exist!');
        console.log('   This could cause sync issues.');
    } else if (collectedStamps.size > 0) {
        console.log('✅ Using collectedStamps (camelCase)');
    } else if (collected_stamps.size > 0) {
        console.log('✅ Using collected_stamps (snake_case)');
    } else {
        console.log('❌ No stamps found in either subcollection!');
    }
    
    console.log('============================================\n');
    
    process.exit(0);
}

checkBothSubcollections().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

