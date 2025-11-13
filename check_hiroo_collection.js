#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkHirooStamps() {
    // Get hiroo's user ID
    const usersSnapshot = await db.collection('users').where('username', '==', 'hiroo').get();
    
    if (usersSnapshot.empty) {
        console.log('❌ User hiroo not found');
        return;
    }
    
    const userId = usersSnapshot.docs[0].id;
    console.log(`👤 Found hiroo: ${userId}\n`);
    
    // Get collected stamps
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`📦 Collected stamps: ${collectedStamps.size}\n`);
    
    // List all stamp IDs
    const stampIds = collectedStamps.docs.map(doc => doc.id).sort();
    for (const stampId of stampIds) {
        console.log(`   ${stampId}`);
    }
    
    console.log('\n🔍 Looking for ballast...');
    const ballastStamps = stampIds.filter(id => id.includes('ballast'));
    if (ballastStamps.length > 0) {
        console.log(`✅ Found: ${ballastStamps.join(', ')}`);
    } else {
        console.log('❌ No ballast stamps found in collection');
    }
    
    process.exit(0);
}

checkHirooStamps().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

