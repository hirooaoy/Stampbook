#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkAllUsers() {
    console.log('🔍 Checking all users and their stamps...\n');
    
    const usersSnapshot = await db.collection('users').get();
    
    for (const userDoc of usersSnapshot.docs) {
        const userData = userDoc.data();
        const userId = userDoc.id;
        
        console.log(`👤 ${userData.username || 'Unknown'} (${userId})`);
        
        // Get collected stamps
        const collectedStamps = await db
            .collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .get();
        
        console.log(`   📦 Collected stamps: ${collectedStamps.size}`);
        
        if (collectedStamps.size > 0) {
            // Check if any stamps reference non-existent stamp IDs
            const stampIds = collectedStamps.docs.map(doc => doc.id);
            
            let validCount = 0;
            let invalidCount = 0;
            
            for (const stampId of stampIds) {
                // Check if stamp exists in stamps collection
                const stampDoc = await db.collection('stamps').doc(stampId).get();
                if (stampDoc.exists) {
                    validCount++;
                } else {
                    console.log(`   ⚠️  Invalid stamp reference: ${stampId}`);
                    invalidCount++;
                }
            }
            
            console.log(`   ✅ Valid stamps: ${validCount}`);
            if (invalidCount > 0) {
                console.log(`   ❌ Invalid stamps: ${invalidCount}`);
            }
        }
        
        console.log('');
    }
    
    console.log('============================================');
    console.log('📊 SYSTEM STATUS:');
    console.log('============================================\n');
    
    // Check total stamps in system
    const stampsSnapshot = await db.collection('stamps').get();
    console.log(`✅ Total stamps in system: ${stampsSnapshot.size}`);
    
    // Check that all stamps have imageUrl
    let stampsWithImages = 0;
    let stampsWithoutImages = 0;
    
    for (const stampDoc of stampsSnapshot.docs) {
        const stamp = stampDoc.data();
        if (stamp.imageUrl && stamp.imageUrl.length > 0) {
            stampsWithImages++;
        } else {
            stampsWithoutImages++;
            console.log(`   ⚠️  No image: ${stampDoc.id} (${stamp.name})`);
        }
    }
    
    console.log(`✅ Stamps with images: ${stampsWithImages}/${stampsSnapshot.size}`);
    if (stampsWithoutImages > 0) {
        console.log(`⚠️  Stamps without images: ${stampsWithoutImages}`);
    }
    
    console.log('\n============================================');
    
    process.exit(0);
}

checkAllUsers().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

