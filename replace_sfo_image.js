const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
  });
}

const bucket = admin.storage().bucket();
const db = admin.firestore();

async function replaceSFOImage() {
  console.log('\n🔄 Replacing SFO Airport Image...\n');
  
  const stampId = 'us-ca-sf-san-francisco-airport';
  const imagePath = '/Users/haoyama/Downloads/us-ca-sf-san-francisco-airport.png';
  const newAspectRatio = 0.98;
  
  try {
    // 1. Delete old stamp image from Firebase Storage
    console.log('🗑️  Step 1: Deleting old stamp image...');
    const oldStampPath = `stamps/${stampId}.png`;
    try {
      await bucket.file(oldStampPath).delete();
      console.log('   ✅ Old stamp image deleted');
    } catch (error) {
      console.log('   ⚠️  Old stamp image not found (will create new)');
    }
    
    // 2. Delete old thumbnail from Firebase Storage
    console.log('\n🗑️  Step 2: Deleting old thumbnail...');
    const oldThumbPath = `stamps/${stampId}_thumb.png`;
    try {
      await bucket.file(oldThumbPath).delete();
      console.log('   ✅ Old thumbnail deleted');
    } catch (error) {
      console.log('   ⚠️  Old thumbnail not found (will create new)');
    }
    
    // 3. Upload new stamp image
    console.log('\n⬆️  Step 3: Uploading new stamp image...');
    await bucket.upload(imagePath, {
      destination: oldStampPath,
      metadata: {
        contentType: 'image/png',
        metadata: {
          firebaseStorageDownloadTokens: require('crypto').randomUUID()
        }
      }
    });
    console.log('   ✅ New stamp image uploaded');
    
    // 4. Get new image URL
    const file = bucket.file(oldStampPath);
    const [metadata] = await file.getMetadata();
    const token = metadata.metadata.firebaseStorageDownloadTokens;
    const newImageUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(oldStampPath)}?alt=media&token=${token}`;
    console.log('   📎 New URL:', newImageUrl);
    
    // 5. Update stamps.json
    console.log('\n📝 Step 4: Updating stamps.json...');
    const stampsPath = path.join(__dirname, 'Stampbook/Data/stamps.json');
    const stampsData = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    const stampIndex = stampsData.findIndex(s => s.id === stampId);
    if (stampIndex !== -1) {
      stampsData[stampIndex].imageUrl = newImageUrl;
      stampsData[stampIndex].aspectRatio = newAspectRatio;
      fs.writeFileSync(stampsPath, JSON.stringify(stampsData, null, 2));
      console.log('   ✅ stamps.json updated');
      console.log('   📊 New aspect ratio:', newAspectRatio);
    } else {
      console.log('   ❌ Stamp not found in stamps.json');
      process.exit(1);
    }
    
    // 6. Generate thumbnail using existing script
    console.log('\n🖼️  Step 5: Generating new thumbnail...');
    const { execSync } = require('child_process');
    execSync(`node generate_missing_thumbnails.js`, { stdio: 'inherit' });
    
    // 7. Update Firestore
    console.log('\n☁️  Step 6: Updating Firestore...');
    execSync(`node upload_stamps_to_firestore.js`, { stdio: 'inherit' });
    
    console.log('\n✅ SFO image replacement complete!');
    console.log('📊 Summary:');
    console.log('   - Old image deleted');
    console.log('   - Old thumbnail deleted');
    console.log('   - New image uploaded');
    console.log('   - New thumbnail generated');
    console.log('   - stamps.json updated with new URL and aspect ratio');
    console.log('   - Firestore synced');
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    throw error;
  }
  
  process.exit(0);
}

replaceSFOImage();

