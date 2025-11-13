#!/usr/bin/env node

/**
 * Fix user photo paths after stamp ID changes
 * Updates userImagePaths in collected stamps to point to actual storage locations
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixPhotoPaths() {
    console.log('📸 Fixing user photo paths for hiroo...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Fix ballast coffee - photos are in old folder
    const ballastRef = db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .doc('us-ca-sf-ballast-coffee');
    
    const ballastDoc = await ballastRef.get();
    
    if (ballastDoc.exists) {
        const data = ballastDoc.data();
        console.log('🔍 Ballast Coffee:');
        console.log(`   Current paths: ${JSON.stringify(data.userImagePaths || [])}`);
        
        // Update paths to point to old folder location
        if (data.userImagePaths && data.userImagePaths.length > 0) {
            const updatedPaths = data.userImagePaths.map(path => 
                path.replace('us-ca-sf-ballast-coffee', 'us-ca-sf-ballast')
            );
            
            await ballastRef.update({
                userImagePaths: updatedPaths
            });
            
            console.log(`   ✅ Updated to: ${JSON.stringify(updatedPaths)}\n`);
        } else {
            console.log('   ⚠️  No photos found\n');
        }
    }
    
    // Fix Beal's - photos are in old folder
    const bealsRef = db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .doc('us-me-bar-harbor-beals');
    
    const bealsDoc = await bealsRef.get();
    
    if (bealsDoc.exists) {
        const data = bealsDoc.data();
        console.log('🔍 Beal\'s Lobster Pier:');
        console.log(`   Current paths: ${JSON.stringify(data.userImagePaths || [])}`);
        
        // Update paths to point to old folder location
        if (data.userImagePaths && data.userImagePaths.length > 0) {
            const updatedPaths = data.userImagePaths.map(path => 
                path.replace('us-me-bar-harbor-beals', 'us-me-acadia-beals-lobster-pier')
            );
            
            await bealsRef.update({
                userImagePaths: updatedPaths
            });
            
            console.log(`   ✅ Updated to: ${JSON.stringify(updatedPaths)}\n`);
        } else {
            console.log('   ⚠️  No photos found\n');
        }
    }
    
    console.log('✅ Photo paths fixed!\n');
    process.exit(0);
}

fixPhotoPaths().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

