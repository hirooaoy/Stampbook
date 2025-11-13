#!/usr/bin/env node

/**
 * Automatically fetch all stamp image URLs from Firebase Storage
 * and update stamps.json with the correct download URLs
 * 
 * Usage: node update_stamp_urls_from_storage.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();

// Generate a download token if one doesn't exist
async function generateDownloadToken(file) {
    // Generate a UUID-like token
    const token = require('crypto').randomUUID();
    
    // Update file metadata with the token
    await file.setMetadata({
        metadata: {
            firebaseStorageDownloadTokens: token
        }
    });
    
    return token;
}

async function updateStampUrls() {
    console.log('🔍 Fetching all images from Firebase Storage...\n');
    
    // Get all files from stamps/ folder
    const [files] = await bucket.getFiles({ prefix: 'stamps/' });
    
    if (files.length === 0) {
        console.log('❌ No images found in stamps/ folder');
        console.log('Make sure you\'ve uploaded images first!\n');
        process.exit(1);
    }
    
    console.log(`✅ Found ${files.length} images in Firebase Storage\n`);
    
    // Create a map of filename -> download URL
    const urlMap = {};
    
    for (const file of files) {
        const filename = path.basename(file.name);
        
        // Get public download URL (token-based, not signed URL)
        // This creates the correct Firebase Storage URL format
        const [metadata] = await file.getMetadata();
        const token = metadata.metadata?.firebaseStorageDownloadTokens || await generateDownloadToken(file);
        
        // Construct proper Firebase Storage URL
        // Format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}
        const encodedPath = encodeURIComponent(file.name);
        const url = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
        
        // Extract stamp ID from filename (remove extension)
        const stampId = filename.replace(/\.(jpg|jpeg|png)$/i, '');
        
        urlMap[stampId] = url;
        console.log(`📸 ${stampId}`);
    }
    
    console.log('\n✅ Generated download URLs for all stamps\n');
    
    console.log('📚 Reading stamps.json...');
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    console.log(`✅ Found ${stamps.length} stamps\n`);
    
    // Update each stamp with the new imageUrl
    let updatedCount = 0;
    let notFoundCount = 0;
    
    for (const stamp of stamps) {
        if (urlMap[stamp.id]) {
            stamp.imageUrl = urlMap[stamp.id];
            console.log(`✅ Updated: ${stamp.name}`);
            updatedCount++;
        } else {
            console.log(`⚠️  No image found for: ${stamp.name} (${stamp.id})`);
            notFoundCount++;
        }
    }
    
    // Save updated stamps.json
    console.log('\n💾 Saving stamps.json...');
    fs.writeFileSync(stampsPath, JSON.stringify(stamps, null, 2), 'utf8');
    
    console.log('\n============================================');
    console.log(`✅ Updated ${updatedCount} stamps`);
    if (notFoundCount > 0) {
        console.log(`⚠️  ${notFoundCount} stamps have no image in Firebase Storage`);
    }
    console.log('============================================\n');
    
    console.log('Next step:');
    console.log('Run: node upload_stamps_to_firestore.js');
    console.log('');
    
    process.exit(0);
}

// Run the update
updateStampUrls().catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
});
