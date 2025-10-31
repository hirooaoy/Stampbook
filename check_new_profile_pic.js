const admin = require('firebase-admin');

// Initialize Firebase Admin (reuse existing app if already initialized)
if (!admin.apps.length) {
  const serviceAccount = require('./serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
  });
}

const bucket = admin.storage().bucket();

async function checkBothProfilePictures() {
  try {
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const oldPhotoId = '85E3E63F-B9D3-4E30-B3C2-288ACAFDAB51';
    const newPhotoId = 'C1FED17E-C74E-43E2-BCD3-0478F17367ED';
    
    console.log('\n📊 PROFILE PICTURE COMPARISON\n');
    console.log('═'.repeat(60));
    
    // Check OLD photo
    const oldPath = `users/${userId}/profile_photo/${oldPhotoId}.jpg`;
    const oldFile = bucket.file(oldPath);
    const [oldExists] = await oldFile.exists();
    
    if (oldExists) {
      const [oldMetadata] = await oldFile.getMetadata();
      const oldSizeKB = parseInt(oldMetadata.size) / 1024;
      console.log(`\n❌ OLD PHOTO (should be deleted):`);
      console.log(`   File: ${oldPhotoId}.jpg`);
      console.log(`   Size: ${oldSizeKB.toFixed(1)} KB`);
      console.log(`   Status: ⚠️  Still exists (not deleted)`);
    } else {
      console.log(`\n✅ OLD PHOTO:`);
      console.log(`   Status: Deleted successfully`);
    }
    
    // Check NEW photo
    const newPath = `users/${userId}/profile_photo/${newPhotoId}.jpg`;
    const newFile = bucket.file(newPath);
    const [newExists] = await newFile.exists();
    
    if (!newExists) {
      console.log('\n❌ NEW PHOTO: Not found!');
      return;
    }
    
    const [newMetadata] = await newFile.getMetadata();
    const newSizeBytes = parseInt(newMetadata.size);
    const newSizeKB = newSizeBytes / 1024;
    const newSizeMB = newSizeKB / 1024;
    
    console.log(`\n✅ NEW PHOTO:`);
    console.log(`   File: ${newPhotoId}.jpg`);
    console.log(`   Size: ${newSizeKB.toFixed(1)} KB (${newSizeMB.toFixed(2)} MB)`);
    console.log(`   Type: ${newMetadata.contentType}`);
    console.log(`   Cache Control: ${newMetadata.cacheControl || 'not set'}`);
    console.log(`   Created: ${new Date(newMetadata.timeCreated).toLocaleString()}`);
    
    // Download time estimates
    console.log(`\n⏱️  Estimated Download Times:`);
    console.log(`   Fast 4G (10 Mbps):  ${((newSizeBytes * 8) / (10 * 1000000)).toFixed(2)}s`);
    console.log(`   Slow 4G (2 Mbps):   ${((newSizeBytes * 8) / (2 * 1000000)).toFixed(2)}s`);
    console.log(`   3G (1 Mbps):        ${((newSizeBytes * 8) / (1 * 1000000)).toFixed(2)}s`);
    
    // Verdict
    console.log(`\n💡 Analysis:`);
    if (newSizeKB > 500) {
      console.log(`   ⚠️  Photo is ${(newSizeKB / 500).toFixed(1)}x larger than target (500KB)`);
      console.log(`   ⚠️  Compression may not be working properly!`);
      console.log(`   🔧 Expected: ~200-500KB for 400x400px @ 0.5MB max`);
      console.log(`   🔧 Actual: ${newSizeKB.toFixed(0)}KB`);
    } else if (newSizeKB > 200) {
      console.log(`   ✅ Size is acceptable but could be smaller`);
      console.log(`   💡 Consider reducing to 200x200px for feed = ~${(newSizeKB / 2).toFixed(0)}KB`);
    } else {
      console.log(`   ✅ Perfect size for feed!`);
      console.log(`   ✅ Compression working as expected`);
    }
    
    console.log('\n' + '═'.repeat(60) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
  
  process.exit(0);
}

checkBothProfilePictures();

