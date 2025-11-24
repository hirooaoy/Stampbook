const admin = require('firebase-admin');
const sharp = require('sharp');

const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
  });
}

const bucket = admin.storage().bucket();

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

/**
 * Scan Firebase Storage and generate missing thumbnails
 */
async function generateMissingThumbnails() {
  console.log('🔍 Scanning Firebase Storage for stamp images...\n');
  
  // Get all files in stamps/ folder
  const [files] = await bucket.getFiles({ prefix: 'stamps/' });
  
  // Separate main images and thumbnails
  const mainImages = [];
  const existingThumbnails = new Set();
  
  for (const file of files) {
    const filename = file.name.replace('stamps/', '');
    
    if (filename.endsWith('_thumb.png')) {
      // This is a thumbnail
      const stampId = filename.replace('_thumb.png', '');
      existingThumbnails.add(stampId);
    } else if (filename.endsWith('.png')) {
      // This is a main image
      const stampId = filename.replace('.png', '');
      mainImages.push({ stampId, file });
    }
  }
  
  console.log(`📊 Found ${mainImages.length} stamp images`);
  console.log(`📊 Found ${existingThumbnails.size} existing thumbnails\n`);
  
  // Find images missing thumbnails
  const missingThumbnails = mainImages.filter(img => !existingThumbnails.has(img.stampId));
  
  if (missingThumbnails.length === 0) {
    console.log('✅ All stamps have thumbnails! Nothing to do.');
    
    // Check for orphaned thumbnails (thumbnails without main images)
    const mainImageIds = new Set(mainImages.map(img => img.stampId));
    const orphanedThumbnails = Array.from(existingThumbnails).filter(id => !mainImageIds.has(id));
    
    if (orphanedThumbnails.length > 0) {
      console.log(`\n⚠️  Found ${orphanedThumbnails.length} orphaned thumbnails (no main image):`);
      orphanedThumbnails.forEach(id => console.log(`   - ${id}_thumb.png`));
      console.log('\nYou may want to delete these manually.');
    }
    
    process.exit(0);
  }
  
  console.log(`🔧 Missing thumbnails for ${missingThumbnails.length} stamps:\n`);
  missingThumbnails.forEach(img => console.log(`   - ${img.stampId}`));
  console.log('');
  
  // Generate and upload missing thumbnails
  let successful = 0;
  let failed = 0;
  
  for (const { stampId, file } of missingThumbnails) {
    try {
      console.log(`🔄 Processing: ${stampId}`);
      
      // Download main image
      const [buffer] = await file.download();
      console.log(`   ✅ Downloaded (${(buffer.length / 1024).toFixed(1)} KB)`);
      
      // Generate thumbnail
      const thumbnailBuffer = await generateThumbnail(buffer, 512);
      console.log(`   ✅ Generated thumbnail (${(thumbnailBuffer.length / 1024).toFixed(1)} KB)`);
      
      // Upload thumbnail
      const thumbnailPath = `stamps/${stampId}_thumb.png`;
      await bucket.file(thumbnailPath).save(thumbnailBuffer, {
        metadata: {
          contentType: 'image/png',
          metadata: {
            firebaseStorageDownloadTokens: require('crypto').randomBytes(16).toString('hex'),
            generatedAt: new Date().toISOString(),
            version: 'v1_aspect_fit'
          }
        }
      });
      
      console.log(`   ✅ Uploaded: ${thumbnailPath}\n`);
      successful++;
      
    } catch (error) {
      console.error(`   ❌ ERROR: ${error.message}\n`);
      failed++;
    }
  }
  
  // Check for orphaned thumbnails
  const mainImageIds = new Set(mainImages.map(img => img.stampId));
  const orphanedThumbnails = Array.from(existingThumbnails).filter(id => !mainImageIds.has(id));
  
  // Final report
  console.log('\n' + '='.repeat(60));
  console.log('🎉 THUMBNAIL GENERATION COMPLETE');
  console.log('='.repeat(60));
  console.log(`✅ Successfully generated: ${successful} thumbnails`);
  console.log(`❌ Failed: ${failed} thumbnails`);
  console.log(`📦 Total stamps: ${mainImages.length}`);
  console.log(`📦 Total thumbnails: ${existingThumbnails.size + successful}`);
  
  if (orphanedThumbnails.length > 0) {
    console.log(`\n⚠️  Found ${orphanedThumbnails.length} orphaned thumbnails:`);
    orphanedThumbnails.forEach(id => console.log(`   - ${id}_thumb.png`));
    console.log('\n   These thumbnails have no corresponding main image.');
    console.log('   You may want to delete them manually.');
  }
  
  console.log('='.repeat(60));
  
  process.exit(failed > 0 ? 1 : 0);
}

generateMissingThumbnails().catch(err => {
  console.error('❌ Fatal error:', err);
  process.exit(1);
});

