const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
  });
}

const bucket = admin.storage().bucket();

async function replaceAirportImages() {
  console.log('\n🔄 Replacing 3 Airport Images...\n');
  
  const stampIds = [
    'us-fl-orlando-international-airport',
    'us-il-chicago-ohare-airport',
    'us-ny-newyork-jfk-airport'
  ];
  
  const stampsJsonPath = path.join(__dirname, 'Stampbook/Data/stamps.json');
  
  try {
    // Step 1: Delete old images and thumbnails
    console.log('🗑️  Step 1: Deleting old images and thumbnails...');
    for (const stampId of stampIds) {
      const stampPath = `stamps/${stampId}.png`;
      const thumbPath = `stamps/${stampId}_thumb.png`;
      
      try {
        await bucket.file(stampPath).delete();
        console.log(`   ✅ Deleted old image: ${stampId}`);
      } catch (error) {
        console.log(`   ⚠️  Old image not found: ${stampId}`);
      }
      
      try {
        await bucket.file(thumbPath).delete();
        console.log(`   ✅ Deleted old thumbnail: ${stampId}`);
      } catch (error) {
        console.log(`   ⚠️  Old thumbnail not found: ${stampId}`);
      }
    }
    console.log('');
    
    // Step 2: Upload new images
    console.log('⬆️  Step 2: Uploading new images...');
    const uploadedUrls = {};
    
    for (const stampId of stampIds) {
      const filePath = `/Users/haoyama/Downloads/${stampId}.png`;
      const destination = `stamps/${stampId}.png`;
      
      console.log(`   📤 Uploading ${stampId}...`);
      
      await bucket.upload(filePath, {
        destination: destination,
        metadata: {
          contentType: 'image/png',
          metadata: {
            firebaseStorageDownloadTokens: require('crypto').randomUUID()
          }
        }
      });
      
      // Get download URL
      const file = bucket.file(destination);
      const [metadata] = await file.getMetadata();
      const token = metadata.metadata.firebaseStorageDownloadTokens;
      const downloadUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(destination)}?alt=media&token=${token}`;
      
      uploadedUrls[stampId] = downloadUrl;
      console.log(`   ✅ Uploaded`);
    }
    console.log('');
    
    // Step 3: Calculate new aspect ratios
    console.log('📐 Step 3: Calculating aspect ratios...');
    const aspectRatios = {};
    
    for (const stampId of stampIds) {
      const filePath = `/Users/haoyama/Downloads/${stampId}.png`;
      const output = execSync(`sips -g pixelWidth -g pixelHeight "${filePath}"`).toString();
      const width = parseInt(output.match(/pixelWidth: (\d+)/)[1]);
      const height = parseInt(output.match(/pixelHeight: (\d+)/)[1]);
      const aspectRatio = parseFloat((height / width).toFixed(2));
      
      aspectRatios[stampId] = aspectRatio;
      console.log(`   ${stampId}: ${width}x${height} = ${aspectRatio}`);
    }
    console.log('');
    
    // Step 4: Update stamps.json
    console.log('📝 Step 4: Updating stamps.json...');
    const stampsData = JSON.parse(fs.readFileSync(stampsJsonPath, 'utf8'));
    
    let updatedCount = 0;
    for (const stamp of stampsData) {
      if (stampIds.includes(stamp.id)) {
        stamp.imageUrl = uploadedUrls[stamp.id];
        stamp.aspectRatio = aspectRatios[stamp.id];
        updatedCount++;
      }
    }
    
    fs.writeFileSync(stampsJsonPath, JSON.stringify(stampsData, null, 2));
    console.log(`✅ Updated ${updatedCount} stamps in stamps.json\n`);
    
    // Step 5: Generate new thumbnails
    console.log('🖼️  Step 5: Generating new thumbnails...');
    execSync('node generate_missing_thumbnails.js', { stdio: 'inherit' });
    console.log('');
    
    // Step 6: Sync to Firestore
    console.log('☁️  Step 6: Syncing to Firestore...');
    execSync('node upload_stamps_to_firestore.js', { stdio: 'inherit' });
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ REPLACEMENT COMPLETE!');
    console.log('='.repeat(60));
    console.log('✅ 3 airport images replaced:');
    console.log('   - Orlando (MCO)');
    console.log('   - Chicago (ORD)');
    console.log('   - New York (JFK)');
    console.log('✅ Old images deleted');
    console.log('✅ New images uploaded');
    console.log('✅ New thumbnails generated');
    console.log('✅ stamps.json updated');
    console.log('✅ Firestore synced');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

replaceAirportImages();

