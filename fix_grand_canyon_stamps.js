const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// Simple geohash encoder
function encodeGeohash(latitude, longitude, precision = 8) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let latRange = [-90.0, 90.0];
  let lonRange = [-180.0, 180.0];
  let hash = '';
  let bits = 0;
  let bit = 0;
  let even = true;
  
  while (hash.length < precision) {
    if (even) {
      const mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude > mid) {
        bit |= (1 << (4 - bits));
        lonRange[0] = mid;
      } else {
        lonRange[1] = mid;
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (latitude > mid) {
        bit |= (1 << (4 - bits));
        latRange[0] = mid;
      } else {
        latRange[1] = mid;
      }
    }
    
    even = !even;
    bits++;
    
    if (bits === 5) {
      hash += base32[bit];
      bits = 0;
      bit = 0;
    }
  }
  
  return hash;
}

async function fixGrandCanyonStamps() {
  try {
    // 1. Delete the duplicate with webAdminKey
    console.log('1️⃣ Deleting duplicate Desert View Watchtower...');
    await db.collection('stamps').doc('stamp-desert-view-watchtower-1763159893662').delete();
    console.log('✅ Deleted duplicate stamp');
    
    // 2. Get all Grand Canyon stamps and add missing fields
    console.log('\n2️⃣ Fixing all Grand Canyon stamps...');
    const stamps = await db.collection('stamps')
      .where('collectionIds', 'array-contains', 'grand-canyon-must-visits')
      .get();
    
    for (const doc of stamps.docs) {
      const stamp = doc.data();
      const updates = {};
      
      // Add geohash if missing
      if (!stamp.geohash && stamp.latitude && stamp.longitude) {
        updates.geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
      }
      
      // Add notesFromOthers if missing
      if (!stamp.notesFromOthers) {
        updates.notesFromOthers = [];
      }
      
      // Remove webAdminKey if present
      if (stamp.webAdminKey) {
        updates.webAdminKey = admin.firestore.FieldValue.delete();
      }
      
      if (Object.keys(updates).length > 0) {
        await db.collection('stamps').doc(doc.id).update(updates);
        console.log('✅', stamp.name, '-', Object.keys(updates).filter(k => k !== 'webAdminKey').join(', '));
      }
    }
    
    console.log('\n✅ All Grand Canyon stamps fixed!');
    process.exit();
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

fixGrandCanyonStamps();

