#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function thoroughCheck() {
    console.log('🔍 THOROUGH CHECK OF HIROO\'S COLLECTION\n');
    console.log('============================================\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Get user profile
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data();
    
    console.log('👤 USER PROFILE:');
    console.log(`   Username: ${userData.username}`);
    console.log(`   Display: ${userData.displayName}`);
    console.log(`   Total Stamps: ${userData.totalStampsCollected || 0}`);
    console.log('');
    
    // Get all collected stamps
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    console.log(`📦 COLLECTED STAMPS: ${collectedStamps.size}\n`);
    
    if (collectedStamps.empty) {
        console.log('❌ NO STAMPS FOUND!\n');
        return;
    }
    
    // List each stamp with full details
    for (const doc of collectedStamps.docs) {
        const stampId = doc.id;
        const data = doc.data();
        
        console.log(`✓ ${stampId}`);
        console.log(`   Collected: ${data.collectedDate?.toDate().toLocaleString()}`);
        console.log(`   Photos: ${data.userImageNames?.length || 0}`);
        console.log(`   Photo paths: ${JSON.stringify(data.userImagePaths || [])}`);
        console.log(`   Notes: ${data.userNotes || '(none)'}`);
        console.log(`   Likes: ${data.likeCount || 0}`);
        console.log(`   Comments: ${data.commentCount || 0}`);
        
        // Check if stamp exists in stamps collection
        const stampDoc = await db.collection('stamps').doc(stampId).get();
        if (stampDoc.exists) {
            const stamp = stampDoc.data();
            console.log(`   ✅ Stamp exists: "${stamp.name}"`);
        } else {
            console.log(`   ❌ STAMP DOES NOT EXIST IN STAMPS COLLECTION!`);
        }
        console.log('');
    }
    
    console.log('============================================');
    console.log('🔍 SEARCHING FOR BALLAST AND BEALS...\n');
    
    const ballastFound = collectedStamps.docs.find(doc => doc.id.includes('ballast'));
    const bealsFound = collectedStamps.docs.find(doc => doc.id.includes('beal'));
    
    if (ballastFound) {
        console.log(`✅ Ballast found: ${ballastFound.id}`);
    } else {
        console.log('❌ Ballast NOT found in collection');
    }
    
    if (bealsFound) {
        console.log(`✅ Beal's found: ${bealsFound.id}`);
    } else {
        console.log('❌ Beal\'s NOT found in collection');
    }
    
    console.log('\n============================================');
    
    process.exit(0);
}

thoroughCheck().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

