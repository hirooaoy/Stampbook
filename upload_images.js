const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { imageSize } = require('image-size');

const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
  });
}

const bucket = admin.storage().bucket();

// Get folder name from command line argument
const folderName = process.argv[2];

if (!folderName) {
  console.error('❌ Error: Please provide a folder name');
  console.log('Usage: node upload_images.js "Stampbook_ collect stamps around the world"');
  process.exit(1);
}

const imageDir = path.join('/Users/haoyama/Downloads', folderName);

if (!fs.existsSync(imageDir)) {
  console.error(`❌ Error: Folder not found: ${imageDir}`);
  process.exit(1);
}

/**
 * Generate 512x512 thumbnail using aspect-fit (preserves full image with padding)
 * Matches iOS ImageManager.generateThumbnail() logic
 */
async function generateThumbnail(imageBuffer, size = 512) {
  const metadata = await sharp(imageBuffer).metadata();
  const width = metadata.width;
  const height = metadata.height;
  
  // Calculate aspect-fit scaling (show full image, add padding)
  const scale = Math.min(size / width, size / height);
  const scaledWidth = Math.round(width * scale);
  const scaledHeight = Math.round(height * scale);
  
  // Resize with padding to center (transparent background for PNGs)
  return await sharp(imageBuffer)
    .resize(scaledWidth, scaledHeight, {
      fit: 'contain',
      background: { r: 0, g: 0, b: 0, alpha: 0 }
    })
    .extend({
      top: Math.round((size - scaledHeight) / 2),
      bottom: Math.round((size - scaledHeight) / 2),
      left: Math.round((size - scaledWidth) / 2),
      right: Math.round((size - scaledWidth) / 2),
      background: { r: 0, g: 0, b: 0, alpha: 0 }
    })
    .png()
    .toBuffer();
}

async function uploadImages() {
  console.log(`📁 Reading images from: ${imageDir}\n`);
  
  // Get all PNG files in the directory
  const files = fs.readdirSync(imageDir).filter(file => file.endsWith('.png'));
  
  if (files.length === 0) {
    console.log('⚠️  No PNG files found in folder');
    process.exit(0);
  }
  
  console.log(`Found ${files.length} PNG files\n`);
  
  const results = [];
  
  for (const fileName of files) {
    const stampId = fileName.replace('.png', '');
    const filePath = path.join(imageDir, fileName);
    
    console.log(`Processing ${fileName}...`);
    
    // Read image buffer
    const buffer = fs.readFileSync(filePath);
    const dimensions = imageSize(buffer);
    // aspectRatio should be HEIGHT / WIDTH (not width/height)
    const aspectRatio = parseFloat((dimensions.height / dimensions.width).toFixed(2));
    console.log(`  Dimensions: ${dimensions.width}x${dimensions.height}`);
    console.log(`  Aspect Ratio: ${aspectRatio} (height/width)`);
    
    // STEP 1: Upload main image
    const destination = `stamps/${fileName}`;
    await bucket.upload(filePath, {
      destination: destination,
      metadata: {
        contentType: 'image/png',
        metadata: {
          firebaseStorageDownloadTokens: require('crypto').randomBytes(16).toString('hex')
        }
      }
    });
    
    const file = bucket.file(destination);
    const [metadata] = await file.getMetadata();
    const token = metadata.metadata.firebaseStorageDownloadTokens;
    const imageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destination)}?alt=media&token=${token}`;
    
    console.log(`  ✅ Main image uploaded (${(buffer.length / 1024).toFixed(1)} KB)`);
    
    // STEP 2: Generate thumbnail
    console.log(`  🖼️  Generating 512x512 thumbnail...`);
    const thumbnailBuffer = await generateThumbnail(buffer, 512);
    console.log(`  ✅ Thumbnail generated (${(thumbnailBuffer.length / 1024).toFixed(1)} KB)`);
    
    // STEP 3: Upload thumbnail
    const thumbnailDestination = `stamps/${stampId}_thumb.png`;
    await bucket.file(thumbnailDestination).save(thumbnailBuffer, {
      metadata: {
        contentType: 'image/png',
        metadata: {
          firebaseStorageDownloadTokens: require('crypto').randomBytes(16).toString('hex')
        }
      }
    });
    
    console.log(`  ✅ Thumbnail uploaded: ${thumbnailDestination}\n`);
    
    results.push({
      id: stampId,
      imageUrl: imageUrl,
      aspectRatio: aspectRatio
    });
  }
  
  console.log('\n=== UPLOAD RESULTS ===');
  console.log(JSON.stringify(results, null, 2));
  console.log('\n🎉 All images uploaded successfully!');
  console.log(`   📦 Uploaded ${files.length} main images + ${files.length} thumbnails`);
  
  process.exit(0);
}

uploadImages().catch(err => {
  console.error('❌ Error:', err);
  process.exit(1);
});

