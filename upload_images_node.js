#!/usr/bin/env node

/**
 * Upload stamp images to Firebase Storage
 * Usage: node upload_images_node.js /path/to/images/folder
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

async function uploadImages(folderPath) {
    console.log('\n🖼️  Uploading stamp images to Firebase Storage');
    console.log('==============================================\n');
    
    // Check if folder exists
    if (!fs.existsSync(folderPath)) {
        console.error(`❌ Folder not found: ${folderPath}`);
        process.exit(1);
    }
    
    // Get all image files
    const files = fs.readdirSync(folderPath).filter(file => 
        /\.(jpg|jpeg|png)$/i.test(file)
    );
    
    if (files.length === 0) {
        console.error('❌ No images found in folder');
        process.exit(1);
    }
    
    console.log(`✅ Found ${files.length} images\n`);
    console.log('📤 Uploading to Firebase Storage → stamps/ folder...\n');
    
    let uploaded = 0;
    let failed = 0;
    
    for (const filename of files) {
        const filePath = path.join(folderPath, filename);
        const destination = `stamps/${filename}`;
        
        try {
            await bucket.upload(filePath, {
                destination: destination,
                metadata: {
                    contentType: filename.endsWith('.png') ? 'image/png' : 'image/jpeg',
                    cacheControl: 'public, max-age=31536000'
                }
            });
            
            console.log(`  ✅ Uploaded: ${filename}`);
            uploaded++;
        } catch (error) {
            console.error(`  ❌ Failed: ${filename} - ${error.message}`);
            failed++;
        }
    }
    
    console.log('\n==============================================');
    console.log(`✅ Upload complete!`);
    console.log(`   Uploaded: ${uploaded}`);
    if (failed > 0) {
        console.log(`   Failed: ${failed}`);
    }
    console.log('==============================================\n');
    
    console.log('Next step:');
    console.log('Run: node update_stamp_urls_from_storage.js');
    console.log('');
    
    process.exit(0);
}

// Get folder path from command line
const folderPath = process.argv[2];

if (!folderPath) {
    console.error('❌ Please provide the path to your images folder\n');
    console.error('Usage:');
    console.error('  node upload_images_node.js /path/to/images/folder\n');
    process.exit(1);
}

// Run upload
uploadImages(folderPath).catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
});

