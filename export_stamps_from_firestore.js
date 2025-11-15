const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function exportStampsToJSON() {
  try {
    console.log('📥 Exporting stamps from Firestore...');
    
    const stampsSnapshot = await db.collection('stamps').get();
    
    if (stampsSnapshot.empty) {
      console.log('❌ No stamps found in Firestore');
      return;
    }

    const firebaseStamps = [];
    stampsSnapshot.forEach(doc => {
      firebaseStamps.push(doc.data());
    });
    
    console.log(`✅ Found ${firebaseStamps.length} stamps in Firebase\n`);

    // ==================== SMART SYNC CHECK ====================
    console.log('🔍 Checking differences between JSON and Firebase...');
    
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    let localStamps = [];
    
    // Check if local JSON exists
    if (fs.existsSync(stampsPath)) {
      localStamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    }
    
    const firebaseIds = new Set(firebaseStamps.map(s => s.id));
    const localIds = new Set(localStamps.map(s => s.id));
    
    const onlyInFirebase = [...firebaseIds].filter(id => !localIds.has(id));
    const onlyInLocal = [...localIds].filter(id => !firebaseIds.has(id));
    
    console.log(`📊 Firebase: ${firebaseIds.size} stamps`);
    console.log(`📊 Local JSON: ${localIds.size} stamps`);
    console.log(`📊 Only in Firebase: ${onlyInFirebase.length} stamps`);
    console.log(`📊 Only in Local: ${onlyInLocal.length} stamps\n`);
    
    // Check for --force flag
    const forceOverwrite = process.argv.includes('--force');
    
    // If local has stamps that Firebase doesn't, warn and require confirmation
    if (onlyInLocal.length > 0 && !forceOverwrite) {
      console.log('⚠️  WARNING: Your local JSON has stamps that are NOT in Firebase!');
      console.log('⚠️  Running this script will DELETE these stamps from your local JSON:\n');
      
      const localStampsMap = {};
      localStamps.forEach(s => localStampsMap[s.id] = s);
      
      for (const id of onlyInLocal) {
        const stamp = localStampsMap[id];
        console.log(`   🗑️  ${stamp.name} (${id})`);
      }
      
      console.log('\n❌ EXPORT ABORTED FOR SAFETY!\n');
      console.log('💡 What you probably want to do:');
      console.log('   1. Run: node upload_stamps_to_firestore.js');
      console.log('   2. This will push your local stamps to Firebase');
      console.log('   3. THEN run this script again\n');
      console.log('🚨 If you really want to OVERWRITE local JSON with Firebase data:');
      console.log('   Run: node export_stamps_from_firestore.js --force\n');
      process.exit(1);
    }
    
    // If Firebase has more stamps and local is a subset, safe to proceed
    if (onlyInFirebase.length > 0 && onlyInLocal.length === 0) {
      console.log('✅ Safe to export: Firebase has new stamps, local JSON will be updated\n');
    } else if (onlyInFirebase.length === 0 && onlyInLocal.length === 0) {
      console.log('✅ Safe to export: Firebase and local JSON have the same stamps\n');
    } else if (forceOverwrite && onlyInLocal.length > 0) {
      console.log(`⚠️  FORCE OVERWRITE: ${onlyInLocal.length} local stamps will be removed\n`);
    }
    // ========================================================

    // Sort by ID for consistency
    firebaseStamps.sort((a, b) => a.id.localeCompare(b.id));

    // Write to stamps.json
    fs.writeFileSync(stampsPath, JSON.stringify(firebaseStamps, null, 2));

    console.log(`✅ Successfully exported ${firebaseStamps.length} stamps to stamps.json`);
    console.log(`📍 Location: ${stampsPath}`);

  } catch (error) {
    console.error('❌ Error exporting stamps:', error);
  } finally {
    process.exit();
  }
}

exportStampsToJSON();

