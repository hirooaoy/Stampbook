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
    const allFiles = fs.readdirSync(folderPath).filter(file => 
        /\.(jpg|jpeg|png)$/i.test(file)
    );
    
    if (allFiles.length === 0) {
        console.error('❌ No images found in folder');
        process.exit(1);
    }
    
    // SAFETY CHECK: Filter for legitimate stamp images only
    // Valid patterns: us-ca-city-name.png, us-state-city-name.png, your-first-stamp.png
    const validStampPattern = /^(us-[a-z]{2}-[a-z-]+|your-first-stamp)\.(png|jpg|jpeg)$/i;
    
    const validFiles = [];
    const invalidFiles = [];
    
    allFiles.forEach(file => {
        if (validStampPattern.test(file)) {
            validFiles.push(file);
        } else {
            invalidFiles.push(file);
        }
    });
    
    console.log(`📊 Found ${allFiles.length} total image(s) in folder`);
    console.log(`   ✅ Valid stamp images: ${validFiles.length}`);
    console.log(`   ⚠️  Invalid/personal files: ${invalidFiles.length}\n`);
    
    // If there are invalid files, show them and ask for confirmation
    if (invalidFiles.length > 0) {
        console.log('⚠️  WARNING: Found files that don\'t match stamp naming pattern:');
        console.log('==============================================');
        invalidFiles.slice(0, 10).forEach(f => console.log(`   - ${f}`));
        if (invalidFiles.length > 10) {
            console.log(`   ... and ${invalidFiles.length - 10} more`);
        }
        console.log('==============================================\n');
        console.log('❌ SAFETY CHECK FAILED!');
        console.log('📋 Only files matching pattern will be uploaded: us-state-city-name.png');
        console.log('💡 To upload these files, move ONLY stamp images to a dedicated folder.\n');
    }
    
    if (validFiles.length === 0) {
        console.error('❌ No valid stamp images to upload.');
        console.error('📋 Expected pattern: us-state-city-name.png (e.g., us-ca-sf-golden-gate-bridge.png)');
        process.exit(1);
    }
    
    console.log(`\n📤 Uploading ${validFiles.length} valid stamp image(s) to Firebase Storage...\n`);
    
    let uploaded = 0;
    let failed = 0;
    
    for (const filename of validFiles) {
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

