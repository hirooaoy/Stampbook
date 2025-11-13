#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function emergencyDiagnostic() {
    console.log('🚨 EMERGENCY DIAGNOSTIC\n');
    console.log('============================================\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // 1. Check user profile
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data();
    
    console.log('👤 USER PROFILE:');
    console.log(`   Username: ${userData.username}`);
    console.log(`   totalStampsCollected: ${userData.totalStampsCollected}`);
    console.log(`   totalCountries: ${userData.totalCountries}`);
    console.log('');
    
    // 2. Check BOTH subcollections
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    const collected_stamps = await db
        .collection('users')
        .doc(userId)
        .collection('collected_stamps')
        .get();
    
    console.log('📦 COLLECTED STAMPS:');
    console.log(`   collectedStamps (camelCase): ${collectedStamps.size} stamps`);
    collectedStamps.docs.forEach(doc => {
        const data = doc.data();
        console.log(`      ✓ ${doc.id}`);
    });
    
    console.log(`\n   collected_stamps (snake_case): ${collected_stamps.size} stamps`);
    collected_stamps.docs.forEach(doc => {
        console.log(`      ✓ ${doc.id}`);
    });
    
    console.log('\n============================================\n');
    
    // 3. Verify each stamp exists
    console.log('🔍 VERIFYING STAMPS EXIST IN SYSTEM:\n');
    
    const allStampIds = new Set([
        ...collectedStamps.docs.map(d => d.id),
        ...collected_stamps.docs.map(d => d.id)
    ]);
    
    for (const stampId of allStampIds) {
        const stampDoc = await db.collection('stamps').doc(stampId).get();
        if (stampDoc.exists) {
            console.log(`   ✅ ${stampId} - "${stampDoc.data().name}"`);
        } else {
            console.log(`   ❌ ${stampId} - DOES NOT EXIST IN STAMPS COLLECTION`);
        }
    }
    
    console.log('\n============================================\n');
    console.log('💡 RECOMMENDATION:\n');
    
    if (collected_stamps.size > 0) {
        console.log('⚠️  You still have the snake_case collection!');
        console.log('   This is causing confusion. Let me fix it...\n');
    }
    
    if (collectedStamps.size < 6) {
        console.log('⚠️  You only have ' + collectedStamps.size + ' stamps in collectedStamps');
        console.log('   Expected 6 stamps. Some are missing!\n');
    }
    
    process.exit(0);
}

emergencyDiagnostic().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

