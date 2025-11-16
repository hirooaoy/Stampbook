const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const { createCanvas, loadImage } = require('canvas');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();
const db = admin.firestore();

/**
 * Generate cropped thumbnail (aspect-fill, no padding)
 * Same logic as generateUserPhotoThumbnail in ImageManager.swift
 */
function generateCroppedThumbnail(imageBuffer, size = 512) {
  return loadImage(imageBuffer).then(img => {
    const canvas = createCanvas(size, size);
    const ctx = canvas.getContext('2d');
    
    // Calculate aspect-fill (crop edges, show center)
    const scale = Math.max(
      size / img.width,
      size / img.height
    );
    
    const scaledWidth = img.width * scale;
    const scaledHeight = img.height * scale;
    
    // Center the image (overflow will be cropped by canvas bounds)
    const x = (size - scaledWidth) / 2;
    const y = (size - scaledHeight) / 2;
    
    // Draw image (fills entire canvas, crops edges)
    ctx.drawImage(img, x, y, scaledWidth, scaledHeight);
    
    return canvas.toBuffer('image/jpeg', { quality: 0.8 });
  });
}

/**
 * Fix Firebase Storage thumbnails for all user photos
 * Downloads full-res, regenerates thumbnail with cropping, re-uploads
 */
async function fixFirebaseThumbnails() {
  console.log('🔍 Scanning Firebase Storage for user photos...\n');
  
  // Get all files in the stamps/ folder (user uploaded photos)
  const [files] = await bucket.getFiles({ prefix: 'stamps/' });
  
  // Filter for full-res photos (not thumbnails)
  const photoFiles = files.filter(file => {
    const name = file.name;
    return name.endsWith('.jpg') && !name.includes('_thumb');
  });
  
  console.log(`📸 Found ${photoFiles.length} user photos\n`);
  
  let fixed = 0;
  let errors = 0;
  
  for (const file of photoFiles) {
    const filename = path.basename(file.name);
    const thumbnailPath = file.name.replace('.jpg', '_thumb.jpg');
    
    try {
      console.log(`🔄 Processing: ${filename}`);
      
      // Download full-res image
      const [buffer] = await file.download();
      console.log(`   ✅ Downloaded full-res (${(buffer.length / 1024).toFixed(1)} KB)`);
      
      // Generate new cropped thumbnail
      const croppedThumbnail = await generateCroppedThumbnail(buffer, 512);
      console.log(`   ✅ Generated cropped thumbnail (${(croppedThumbnail.length / 1024).toFixed(1)} KB)`);
      
      // Upload new thumbnail (overwrites old one)
      await bucket.file(thumbnailPath).save(croppedThumbnail, {
        metadata: {
          contentType: 'image/jpeg',
          metadata: {
            regenerated: new Date().toISOString(),
            version: 'v2_cropped'
          }
        }
      });
      console.log(`   ✅ Uploaded to Firebase: ${thumbnailPath}`);
      console.log(`   ✨ SUCCESS\n`);
      
      fixed++;
      
    } catch (error) {
      console.error(`   ❌ ERROR: ${error.message}\n`);
      errors++;
    }
  }
  
  console.log('\n' + '='.repeat(60));
  console.log(`🎉 Migration Complete!`);
  console.log(`   ✅ Fixed: ${fixed} thumbnails`);
  console.log(`   ❌ Errors: ${errors}`);
  console.log('='.repeat(60));
}

/**
 * Fix thumbnails for a specific user (by userId)
 */
async function fixUserThumbnails(userId) {
  console.log(`🔍 Finding photos for user: ${userId}\n`);
  
  // Query user's collected stamps directly from their subcollection
  const userStampsRef = db.collection('users').doc(userId).collection('collectedStamps');
  const userStampsQuery = await userStampsRef.get();
  
  if (userStampsQuery.empty) {
    console.log('❌ No stamps found for this user');
    return;
  }
  
  console.log(`📸 Found ${userStampsQuery.size} collected stamps\n`);
  
  let fixed = 0;
  let errors = 0;
  
  for (const doc of userStampsQuery.docs) {
    const data = doc.data();
    const userImagePaths = data.userImagePaths || [];
    
    if (userImagePaths.length === 0) continue;
    
    console.log(`📍 Stamp: ${data.stampId} (${userImagePaths.length} photos)`);
    
    for (const imagePath of userImagePaths) {
      if (!imagePath) continue;
      
      try {
        const filename = path.basename(imagePath);
        const thumbnailPath = imagePath.replace('.jpg', '_thumb.jpg');
        
        console.log(`   🔄 Processing: ${filename}`);
        
        // Download full-res image
        const file = bucket.file(imagePath);
        const [buffer] = await file.download();
        console.log(`      ✅ Downloaded (${(buffer.length / 1024).toFixed(1)} KB)`);
        
        // Generate new cropped thumbnail
        const croppedThumbnail = await generateCroppedThumbnail(buffer, 512);
        console.log(`      ✅ Generated cropped thumbnail (${(croppedThumbnail.length / 1024).toFixed(1)} KB)`);
        
        // Upload new thumbnail
        await bucket.file(thumbnailPath).save(croppedThumbnail, {
          metadata: {
            contentType: 'image/jpeg',
            metadata: {
              regenerated: new Date().toISOString(),
              version: 'v2_cropped',
              userId: userId
            }
          }
        });
        console.log(`      ✅ Uploaded to: ${thumbnailPath}`);
        console.log(`      ✨ SUCCESS`);
        
        fixed++;
        
      } catch (error) {
        console.error(`      ❌ ERROR: ${error.message}`);
        errors++;
      }
    }
    
    console.log('');
  }
  
  console.log('='.repeat(60));
  console.log(`🎉 User Migration Complete!`);
  console.log(`   ✅ Fixed: ${fixed} thumbnails`);
  console.log(`   ❌ Errors: ${errors}`);
  console.log('='.repeat(60));
}

// Run based on command line arguments
const args = process.argv.slice(2);

if (args[0] === '--user' && args[1]) {
  // Fix specific user: node fix_firebase_thumbnails.js --user justin123
  fixUserThumbnails(args[1]).then(() => process.exit(0));
} else if (args[0] === '--all') {
  // Fix all users: node fix_firebase_thumbnails.js --all
  fixFirebaseThumbnails().then(() => process.exit(0));
} else {
  console.log('Usage:');
  console.log('  Fix specific user:   node fix_firebase_thumbnails.js --user <userId>');
  console.log('  Fix all users:       node fix_firebase_thumbnails.js --all');
  console.log('\nExamples:');
  console.log('  node fix_firebase_thumbnails.js --user wUdvqr0RVcU3i7Uov6LHWkAl5Rf1  # Justin');
  console.log('  node fix_firebase_thumbnails.js --user hiroo123');
  console.log('  node fix_firebase_thumbnails.js --all');
  process.exit(1);
}

