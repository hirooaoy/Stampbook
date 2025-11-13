#!/usr/bin/env node

/**
 * Rename Firebase Storage folders to match new stamp IDs
 * Copies files from old folders to new folders, then deletes old folders
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();
const db = admin.firestore();

async function copyFolder(oldPath, newPath) {
    console.log(`📂 Copying ${oldPath} → ${newPath}`);
    
    // List all files in old folder
    const [files] = await bucket.getFiles({ prefix: oldPath });
    
    if (files.length === 0) {
        console.log('   ⚠️  No files found\n');
        return 0;
    }
    
    console.log(`   Found ${files.length} files`);
    
    // Copy each file
    for (const file of files) {
        const oldFilePath = file.name;
        const newFilePath = oldFilePath.replace(oldPath, newPath);
        
        console.log(`   📄 ${oldFilePath} → ${newFilePath}`);
        
        await file.copy(bucket.file(newFilePath));
    }
    
    // Delete old files
    console.log('   🗑️  Deleting old files...');
    for (const file of files) {
        await file.delete();
    }
    
    console.log('   ✅ Done\n');
    return files.length;
}

async function renameStampFolders() {
    console.log('🔄 Renaming Firebase Storage folders...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    // Rename ballast folder
    const ballastOld = `users/${userId}/stamps/us-ca-sf-ballast/`;
    const ballastNew = `users/${userId}/stamps/us-ca-sf-ballast-coffee/`;
    const ballastCount = await copyFolder(ballastOld, ballastNew);
    
    // Rename beals folder
    const bealsOld = `users/${userId}/stamps/us-me-acadia-beals-lobster-pier/`;
    const bealsNew = `users/${userId}/stamps/us-me-bar-harbor-beals/`;
    const bealsCount = await copyFolder(bealsOld, bealsNew);
    
    console.log('============================================');
    console.log(`✅ Renamed ${ballastCount + bealsCount} total files`);
    console.log('============================================\n');
    
    // Now update Firestore paths
    console.log('📝 Updating Firestore paths...\n');
    
    // Update ballast
    if (ballastCount > 0) {
        const ballastRef = db
            .collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .doc('us-ca-sf-ballast-coffee');
        
        const ballastDoc = await ballastRef.get();
        if (ballastDoc.exists) {
            const data = ballastDoc.data();
            const updatedPaths = (data.userImagePaths || []).map(path => 
                path.replace('us-ca-sf-ballast/', 'us-ca-sf-ballast-coffee/')
            );
            
            await ballastRef.update({ userImagePaths: updatedPaths });
            console.log('✅ Updated Ballast Coffee paths in Firestore');
        }
    }
    
    // Update beals
    if (bealsCount > 0) {
        const bealsRef = db
            .collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .doc('us-me-bar-harbor-beals');
        
        const bealsDoc = await bealsRef.get();
        if (bealsDoc.exists) {
            const data = bealsDoc.data();
            const updatedPaths = (data.userImagePaths || []).map(path => 
                path.replace('us-me-acadia-beals-lobster-pier/', 'us-me-bar-harbor-beals/')
            );
            
            await bealsRef.update({ userImagePaths: updatedPaths });
            console.log('✅ Updated Beal\'s Lobster Pier paths in Firestore');
        }
    }
    
    console.log('\n✅ All folders renamed and Firestore updated!\n');
    process.exit(0);
}

renameStampFolders().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

