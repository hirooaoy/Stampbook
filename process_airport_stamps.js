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

async function processAirportStamps() {
  console.log('\n🛫 Processing Airport Stamps...\n');
  
  const folderPath = '/Users/haoyama/Downloads/Stampbook_ collect stamps around the world (7)';
  const stampsJsonPath = path.join(__dirname, 'Stampbook/Data/stamps.json');
  
  const stampIds = [
    'us-ga-atlanta-hartsfield-jackson-airport',
    'us-ca-losangeles-lax-airport',
    'us-il-chicago-ohare-airport',
    'us-co-denver-international-airport',
    'us-ny-newyork-jfk-airport',
    'us-nv-lasvegas-harry-reid-airport',
    'us-fl-orlando-international-airport',
    'us-wa-seattle-seatac-airport'
  ];
  
  try {
    // Step 1: Verify all files exist
    console.log('📋 Step 1: Verifying files...');
    for (const stampId of stampIds) {
      const filePath = path.join(folderPath, `${stampId}.png`);
      if (!fs.existsSync(filePath)) {
        console.error(`❌ Missing: ${stampId}.png`);
        process.exit(1);
      }
    }
    console.log('✅ All 8 files verified\n');
    
    // Step 2: Upload images to Firebase Storage
    console.log('☁️  Step 2: Uploading images to Firebase Storage...');
    const uploadedUrls = {};
    
    for (const stampId of stampIds) {
      const filePath = path.join(folderPath, `${stampId}.png`);
      const destination = `stamps/${stampId}.png`;
      
      console.log(`   ⬆️  Uploading ${stampId}...`);
      
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
    console.log('\n✅ All images uploaded to Firebase Storage\n');
    
    // Step 3: Get aspect ratios
    console.log('📐 Step 3: Calculating aspect ratios...');
    const aspectRatios = {};
    
    for (const stampId of stampIds) {
      const filePath = path.join(folderPath, `${stampId}.png`);
      const output = execSync(`sips -g pixelWidth -g pixelHeight "${filePath}"`).toString();
      const width = parseInt(output.match(/pixelWidth: (\d+)/)[1]);
      const height = parseInt(output.match(/pixelHeight: (\d+)/)[1]);
      const aspectRatio = parseFloat((height / width).toFixed(2));
      
      aspectRatios[stampId] = aspectRatio;
      console.log(`   ${stampId}: ${width}x${height} = ${aspectRatio}`);
    }
    console.log('✅ Aspect ratios calculated\n');
    
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
    
    // Step 5: Generate thumbnails
    console.log('🖼️  Step 5: Generating thumbnails...');
    execSync('node generate_missing_thumbnails.js', { stdio: 'inherit' });
    console.log('');
    
    // Step 6: Upload to Firestore
    console.log('☁️  Step 6: Syncing to Firestore...');
    execSync('node upload_stamps_to_firestore.js', { stdio: 'inherit' });
    console.log('');
    
    // Step 7: Upload collections
    console.log('📚 Step 7: Syncing collections to Firestore...');
    execSync('node upload_collections_to_firestore.js', { stdio: 'inherit' });
    
    console.log('\n' + '='.repeat(60));
    console.log('🎉 AIRPORT STAMPS COMPLETE!');
    console.log('='.repeat(60));
    console.log('✅ 8 new airport stamps added');
    console.log('✅ Images uploaded to Firebase Storage');
    console.log('✅ Thumbnails generated');
    console.log('✅ stamps.json updated with URLs and aspect ratios');
    console.log('✅ Firestore synced');
    console.log('✅ Collection updated to 9 total stamps');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

processAirportStamps();

