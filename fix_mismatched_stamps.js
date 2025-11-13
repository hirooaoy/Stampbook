#!/usr/bin/env node

/**
 * Manually fix the mismatched stamp IDs
 * Maps stamp IDs in JSON to actual image filenames
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

// Manual mapping of stamp IDs to image filenames
const idToFilename = {
    'us-ca-sf-coffee-movement': 'us-ca-sf-the-coffee-movement.png',
    'us-ca-sf-andytown': 'us-ca-sf-andytown-coffee-roasters.png',
    'us-ca-sf-neighbor': 'us-ca-sf-neighbors-corner.png',
    'us-ca-sf-saint-frank': 'us-ca-sf-saint-frank-coffee.png',
    'us-ca-sf-sightglass': 'us-ca-sf-sightglass-coffee.png',
    'us-ca-sf-pinhole': 'us-ca-sf-pinhole-coffee.png',
    'us-ca-sf-ballast': 'us-ca-sf-ballast-coffee.png',
    'us-ca-sf-ggp-japanese-tea-garden': 'us-ca-sf-japanese-tea-garden.png',
    'us-ca-sf-ggp-three-gems': 'us-ca-sf-three-gems-by-james-turrell.png',
    'us-ca-sf-ggp-portals-of-the-past': 'us-ca-sf-portal-of-the-past.png',
    'us-ca-sf-ggp-conservatory-of-flowers': 'us-ca-sf-conservatory-of-flowers.png',
    'us-ca-sf-ggp-bison-paddock': 'us-ca-sf-bison-paddock.png',
    'us-ca-sf-fort-mason-garden': 'us-ca-sf-fort-mason-community-garden.png',
    'us-ca-sf-bernal-heights-garden': 'us-ca-sf-bernal-heights-community-garden.png',
    'us-ca-sf-garden-for-environment': 'us-ca-sf-garden-for-the-environment.png',
    'us-ca-sf-clipper-terrace-garden': 'us-ca-sf-clipper-community-garden.png',
    'us-ca-sf-potrero-hill-garden': 'us-ca-sf-potero-hill-community-garden.png',
    'us-ca-sf-howard-langton-garden': 'us-ca-sf-howard-langton-community-garden.png',
    'us-me-acadia-bubble-rock': 'us-me-bar-harbor-bubble-rock.png',
    'us-me-acadia-beehive-trail': 'us-me-bar-harbor-beehive-trail-summit.png',
    'us-me-acadia-beals-lobster-pier': 'us-me-bar-harbor-beals.png',
    'us-ca-sfo-airport': 'us-ca-sf-san-francisco-airport.png'
};

async function fixMismatchedUrls() {
    console.log('🔧 Fixing mismatched stamp IDs...\n');
    
    // Read stamps.json
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    let fixed = 0;
    
    for (const stamp of stamps) {
        const filename = idToFilename[stamp.id];
        
        if (filename) {
            try {
                // Get the file from storage
                const file = bucket.file(`stamps/${filename}`);
                
                // Get signed URL
                const [url] = await file.getSignedUrl({
                    action: 'read',
                    expires: '03-01-2500'
                });
                
                stamp.imageUrl = url;
                console.log(`✅ Fixed: ${stamp.name} → ${filename}`);
                fixed++;
            } catch (error) {
                console.error(`❌ Error for ${stamp.name}: ${error.message}`);
            }
        }
    }
    
    // Save updated stamps.json
    console.log('\n💾 Saving stamps.json...');
    fs.writeFileSync(stampsPath, JSON.stringify(stamps, null, 2), 'utf8');
    
    console.log('\n============================================');
    console.log(`✅ Fixed ${fixed} stamps`);
    console.log('============================================\n');
    
    process.exit(0);
}

fixMismatchedUrls().catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
});

