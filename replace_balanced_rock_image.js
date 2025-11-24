const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();
const db = admin.firestore();

const DOWNLOADS_FOLDER = '/Users/haoyama/Downloads';
const STAMPS_JSON_PATH = '/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Data/stamps.json';

async function replaceStampImage(stampId) {
  try {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`Processing: ${stampId}`);
    console.log('='.repeat(60));

    // Check if image exists in Downloads folder
    const newImagePath = path.join(DOWNLOADS_FOLDER, `${stampId}.png`);
    if (!fs.existsSync(newImagePath)) {
      throw new Error(`Image file not found: ${newImagePath}`);
    }

    const oldFileName = `stamps/${stampId}.png`;

    // Step 1: Delete old image from Firebase Storage
    console.log('\nStep 1: Deleting old image from Firebase Storage...');
    try {
      await bucket.file(oldFileName).delete();
      console.log('✓ Old image deleted successfully');
    } catch (error) {
      console.log('Note: Could not delete old image (it might not exist or already deleted)');
    }

    // Step 2: Calculate aspect ratio of new image
    console.log('\nStep 2: Calculating aspect ratio of new image...');
    const metadata = await sharp(newImagePath).metadata();
    const aspectRatio = parseFloat((metadata.width / metadata.height).toFixed(2));
    console.log(`✓ New image dimensions: ${metadata.width}x${metadata.height}`);
    console.log(`✓ New aspect ratio: ${aspectRatio}`);

    // Step 3: Upload new image to Firebase Storage
    console.log('\nStep 3: Uploading new image to Firebase Storage...');
    const destination = `stamps/${stampId}.png`;
    await bucket.upload(newImagePath, {
      destination: destination,
      metadata: {
        contentType: 'image/png',
      },
    });

    // Make the file publicly accessible
    await bucket.file(destination).makePublic();

    // Get the new public URL
    const newImageUrl = `https://firebasestorage.googleapis.com/v0/b/stampbook-app.firebasestorage.app/o/${encodeURIComponent(destination)}?alt=media`;
    console.log(`✓ New image uploaded successfully`);
    console.log(`✓ New URL: ${newImageUrl}`);

    // Step 4: Update stamps.json
    console.log('\nStep 4: Updating stamps.json...');
    const stampsData = JSON.parse(fs.readFileSync(STAMPS_JSON_PATH, 'utf8'));
    
    const stampIndex = stampsData.findIndex(s => s.id === stampId);
    if (stampIndex === -1) {
      throw new Error(`Stamp with ID "${stampId}" not found in stamps.json`);
    }

    const oldUrl = stampsData[stampIndex].imageUrl;
    const oldAspectRatio = stampsData[stampIndex].aspectRatio;
    
    stampsData[stampIndex].imageUrl = newImageUrl;
    stampsData[stampIndex].aspectRatio = aspectRatio;

    fs.writeFileSync(STAMPS_JSON_PATH, JSON.stringify(stampsData, null, 2));
    console.log('✓ stamps.json updated successfully');
    console.log(`  - Old aspect ratio: ${oldAspectRatio} → New: ${aspectRatio}`);

    // Step 5: Update Firestore
    console.log('\nStep 5: Updating Firestore...');
    await db.collection('stamps').doc(stampId).update({
      imageUrl: newImageUrl,
      aspectRatio: aspectRatio
    });
    console.log('✓ Firestore updated successfully');

    console.log(`\n✅ Successfully replaced image for: ${stampId}`);
    return true;

  } catch (error) {
    console.error(`\n❌ Error replacing image for ${stampId}:`, error.message);
    return false;
  }
}

async function main() {
  const stampIds = process.argv.slice(2);

  if (stampIds.length === 0) {
    console.log('Usage: node replace_stamp_image.js <stamp-id-1> [stamp-id-2] ...');
    console.log('\nExample:');
    console.log('  node replace_stamp_image.js us-tx-big-bend-national-park-balanced-rock');
    console.log('  node replace_stamp_image.js stamp-id-1 stamp-id-2');
    console.log('\nNote: Images must be named exactly as the stamp ID and placed in Downloads folder');
    process.exit(1);
  }

  console.log(`Starting image replacement for ${stampIds.length} stamp(s)...\n`);

  let successCount = 0;
  let failCount = 0;

  for (const stampId of stampIds) {
    const success = await replaceStampImage(stampId);
    if (success) {
      successCount++;
    } else {
      failCount++;
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));
  console.log(`Total stamps processed: ${stampIds.length}`);
  console.log(`✅ Successful: ${successCount}`);
  if (failCount > 0) {
    console.log(`❌ Failed: ${failCount}`);
  }
  console.log('='.repeat(60));

  process.exit(failCount > 0 ? 1 : 0);
}

main();

