#!/usr/bin/env node

/**
 * Generate Firebase Storage URLs for stamps
 * 
 * This script reads stamps.json and generates the correct Firebase Storage URLs
 * for each stamp based on its ID.
 * 
 * Usage: node generate_image_urls.js YOUR-FIREBASE-PROJECT-ID
 */

const fs = require('fs');
const path = require('path');

// Get project ID from command line
const projectId = process.argv[2];

if (!projectId) {
    console.error('❌ Please provide your Firebase project ID');
    console.error('');
    console.error('Usage:');
    console.error('  node generate_image_urls.js YOUR-PROJECT-ID');
    console.error('');
    console.error('Example:');
    console.error('  node generate_image_urls.js stampbook-app');
    console.error('');
    console.error('Find your project ID at:');
    console.error('  https://console.firebase.google.com/ → Project Settings');
    process.exit(1);
}

const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');

// Read stamps.json
console.log('📚 Reading stamps.json...');
const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));

console.log(`✅ Found ${stamps.length} stamps\n`);

// Update each stamp with imageUrl
let updatedCount = 0;
let skippedCount = 0;

for (const stamp of stamps) {
    // Generate Firebase Storage URL
    const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${projectId}.appspot.com/o/stamps%2F${stamp.id}.jpg?alt=media`;
    
    // Check if stamp already has imageUrl
    if (stamp.imageUrl && stamp.imageUrl === imageUrl) {
        console.log(`⏭️  Skipped: ${stamp.name} (already has correct URL)`);
        skippedCount++;
        continue;
    }
    
    // Add imageUrl field
    stamp.imageUrl = imageUrl;
    
    // Remove old imageName field (optional)
    if (stamp.imageName) {
        delete stamp.imageName;
    }
    
    console.log(`✅ Updated: ${stamp.name}`);
    console.log(`   ${imageUrl}\n`);
    updatedCount++;
}

// Write back to stamps.json
console.log('💾 Saving stamps.json...');
fs.writeFileSync(stampsPath, JSON.stringify(stamps, null, 2), 'utf8');

console.log('\n============================================');
console.log(`✅ Updated ${updatedCount} stamps`);
if (skippedCount > 0) {
    console.log(`⏭️  Skipped ${skippedCount} stamps (already up to date)`);
}
console.log('============================================\n');

console.log('Next steps:');
console.log('1. Upload your images to Firebase Storage → stamps/ folder');
console.log('   • Image filename must match stamp ID + .jpg');
console.log('   • Example: us-ca-sf-baker-beach.jpg');
console.log('');
console.log('2. Use the upload helper script:');
console.log('   ./upload_stamp_images.sh /path/to/images');
console.log('');
console.log('3. Upload to Firestore:');
console.log('   node upload_stamps_to_firestore.js');
console.log('');
console.log('4. If some stamps don\'t have images yet, edit stamps.json:');
console.log('   "imageUrl": ""  ← Empty string = shows placeholder');
console.log('');

