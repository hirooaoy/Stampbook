#!/usr/bin/env node

/**
 * Upload stamp images from Assets.xcassets to Firebase Storage
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin SDK
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();

// Images to upload from Assets.xcassets
const imagesToUpload = [
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-baker-beach.imageset/baker beach.png',
        destination: 'stamps/us-ca-sf-baker-beach.jpg'
    },
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-dolores-park.imageset/Dolores Park.png',
        destination: 'stamps/us-ca-sf-dolores-park.jpg'
    },
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-equator-coffee.imageset/equator coffee.png',
        destination: 'stamps/us-ca-sf-equator-coffee.jpg'
    },
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-ferry-building.imageset/fery.png',
        destination: 'stamps/us-ca-sf-ferry-building.jpg'
    },
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-four-barrel.imageset/four barrel.png',
        destination: 'stamps/us-ca-sf-four-barrel.jpg'
    },
    {
        source: 'Stampbook/Assets.xcassets/us-ca-sf-pier-39.imageset/iPhone 16 Pro - 33.png',
        destination: 'stamps/us-ca-sf-pier-39.jpg'
    }
];

async function uploadImages() {
    console.log('🖼️  Uploading stamp images to Firebase Storage...\n');
    
    let uploaded = 0;
    let failed = 0;
    
    for (const image of imagesToUpload) {
        try {
            const sourcePath = path.join(__dirname, image.source);
            
            // Check if file exists
            if (!fs.existsSync(sourcePath)) {
                console.error(`  ✗ File not found: ${image.source}`);
                failed++;
                continue;
            }
            
            // Upload to Firebase Storage
            await bucket.upload(sourcePath, {
                destination: image.destination,
                metadata: {
                    contentType: 'image/jpeg',
                    cacheControl: 'public, max-age=31536000', // Cache for 1 year
                },
                public: true // Make publicly accessible
            });
            
            console.log(`  ✓ Uploaded: ${image.destination}`);
            uploaded++;
            
        } catch (error) {
            console.error(`  ✗ Failed to upload ${image.destination}: ${error.message}`);
            failed++;
        }
    }
    
    console.log('\n======================================');
    console.log(`✅ Upload complete!`);
    console.log(`   Uploaded: ${uploaded} images`);
    if (failed > 0) {
        console.log(`   Failed: ${failed} images`);
    }
    console.log('======================================\n');
    
    process.exit(0);
}

uploadImages().catch(error => {
    console.error('❌ Upload failed:', error.message);
    process.exit(1);
});

