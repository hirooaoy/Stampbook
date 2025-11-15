const admin = require('firebase-admin');
const fs = require('fs').promises;
const path = require('path');
const https = require('https');
const http = require('http');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();

// Function to get image dimensions from URL
function getImageDimensions(url) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;
    
    protocol.get(url, (response) => {
      const chunks = [];
      
      response.on('data', (chunk) => {
        chunks.push(chunk);
        
        // Try to parse dimensions as soon as we have enough data
        const buffer = Buffer.concat(chunks);
        
        // PNG signature check
        if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) {
          // PNG - dimensions are at bytes 16-23 (IHDR chunk)
          if (buffer.length >= 24) {
            const width = buffer.readUInt32BE(16);
            const height = buffer.readUInt32BE(20);
            response.destroy(); // Stop downloading
            resolve({ width, height });
          }
        }
        // JPEG signature check
        else if (buffer[0] === 0xFF && buffer[1] === 0xD8) {
          // JPEG - need to parse markers
          // For simplicity, let's download more data
          if (buffer.length > 1000) {
            // Look for SOF0 marker (0xFFC0)
            for (let i = 0; i < buffer.length - 9; i++) {
              if (buffer[i] === 0xFF && buffer[i + 1] === 0xC0) {
                const height = buffer.readUInt16BE(i + 5);
                const width = buffer.readUInt16BE(i + 7);
                response.destroy();
                resolve({ width, height });
                return;
              }
            }
          }
        }
      });
      
      response.on('end', () => {
        reject(new Error('Could not determine image dimensions'));
      });
      
      response.on('error', reject);
    }).on('error', reject);
  });
}

// Function to download image from Firebase Storage and get dimensions
async function getStampImageDimensions(storagePath, imageUrl) {
  try {
    // If we have imageUrl, use it directly (faster than downloading from storage)
    if (imageUrl) {
      console.log(`  📏 Getting dimensions from URL...`);
      const dimensions = await getImageDimensions(imageUrl);
      return dimensions;
    }
    
    // Fallback to storage path
    if (storagePath) {
      const file = bucket.file(storagePath);
      const [url] = await file.getSignedUrl({
        action: 'read',
        expires: Date.now() + 60000 // 1 minute
      });
      
      const dimensions = await getImageDimensions(url);
      return dimensions;
    }
    
    return null;
  } catch (error) {
    console.error(`  ⚠️ Error getting dimensions: ${error.message}`);
    return null;
  }
}

async function calculateAspectRatios() {
  console.log('📊 Calculating aspect ratios for all stamps...\n');
  
  // Read stamps.json
  const stampsPath = path.join(__dirname, 'Stampbook/Data/stamps.json');
  const stampsData = await fs.readFile(stampsPath, 'utf8');
  const stamps = JSON.parse(stampsData);
  
  let processed = 0;
  let updated = 0;
  let skipped = 0;
  
  // Process each stamp
  for (const stamp of stamps) {
    processed++;
    console.log(`[${processed}/${stamps.length}] ${stamp.name} (${stamp.id})`);
    
    // Skip if already has aspect ratio
    if (stamp.aspectRatio) {
      console.log(`  ✓ Already has aspectRatio: ${stamp.aspectRatio}`);
      skipped++;
      continue;
    }
    
    // Get dimensions
    const dimensions = await getStampImageDimensions(stamp.imageStoragePath, stamp.imageUrl);
    
    if (dimensions) {
      const aspectRatio = dimensions.height / dimensions.width;
      stamp.aspectRatio = Math.round(aspectRatio * 100) / 100; // Round to 2 decimals
      
      console.log(`  ✅ ${dimensions.width}×${dimensions.height} → aspectRatio: ${stamp.aspectRatio}`);
      updated++;
    } else {
      console.log(`  ⚠️ Could not determine dimensions, using default 1.0`);
      stamp.aspectRatio = 1.0; // Default to square
      updated++;
    }
    
    // Small delay to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  
  // Write updated stamps.json
  const updatedData = JSON.stringify(stamps, null, 2);
  await fs.writeFile(stampsPath, updatedData, 'utf8');
  
  console.log('\n✨ Done!');
  console.log(`📊 Summary:`);
  console.log(`   Total stamps: ${stamps.length}`);
  console.log(`   Updated: ${updated}`);
  console.log(`   Already had aspectRatio: ${skipped}`);
  console.log(`\n💾 Updated stamps.json saved!`);
}

// Run the script
calculateAspectRatios()
  .then(() => {
    console.log('\n🎉 All aspect ratios calculated successfully!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Error:', error);
    process.exit(1);
  });

