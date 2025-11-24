const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function checkForDuplicates() {
  console.log('🔍 Checking for duplicate stamps...\n');
  
  const stampsRef = db.collection('stamps');
  const snapshot = await stampsRef.get();
  
  const stamps = [];
  snapshot.forEach(doc => {
    const data = doc.data();
    stamps.push({
      id: doc.id,
      name: data.name,
      latitude: data.latitude,
      longitude: data.longitude,
      city: data.city,
      state: data.state,
      country: data.country
    });
  });
  
  console.log(`📊 Total stamps in Firebase: ${stamps.length}\n`);
  
  // Check 1: Exact name duplicates
  console.log('=== CHECK 1: EXACT NAME DUPLICATES ===');
  const nameMap = {};
  let exactNameDupes = 0;
  
  stamps.forEach(stamp => {
    if (!nameMap[stamp.name]) {
      nameMap[stamp.name] = [];
    }
    nameMap[stamp.name].push(stamp);
  });
  
  Object.entries(nameMap).forEach(([name, stampList]) => {
    if (stampList.length > 1) {
      exactNameDupes++;
      console.log(`\n⚠️  DUPLICATE NAME: "${name}" (${stampList.length} stamps)`);
      stampList.forEach(s => {
        console.log(`   - ID: ${s.id}`);
        console.log(`     Location: ${s.city}, ${s.state}, ${s.country}`);
        console.log(`     GPS: ${s.latitude}, ${s.longitude}`);
      });
    }
  });
  
  if (exactNameDupes === 0) {
    console.log('✅ No exact name duplicates found');
  } else {
    console.log(`\n🔴 Found ${exactNameDupes} duplicate name(s)`);
  }
  
  // Check 2: GPS coordinate duplicates (within 10 meters)
  console.log('\n\n=== CHECK 2: GPS COORDINATE DUPLICATES ===');
  console.log('(Stamps within 10 meters of each other)');
  let gpsDupes = 0;
  
  for (let i = 0; i < stamps.length; i++) {
    for (let j = i + 1; j < stamps.length; j++) {
      const distance = getDistanceInMeters(
        stamps[i].latitude, stamps[i].longitude,
        stamps[j].latitude, stamps[j].longitude
      );
      
      if (distance < 10) {
        gpsDupes++;
        console.log(`\n⚠️  GPS DUPLICATE: ${distance.toFixed(1)}m apart`);
        console.log(`   Stamp 1: "${stamps[i].name}" (${stamps[i].id})`);
        console.log(`   Stamp 2: "${stamps[j].name}" (${stamps[j].id})`);
        console.log(`   Location: ${stamps[i].city}, ${stamps[i].state}`);
      }
    }
  }
  
  if (gpsDupes === 0) {
    console.log('✅ No GPS coordinate duplicates found');
  } else {
    console.log(`\n🔴 Found ${gpsDupes} GPS duplicate(s)`);
  }
  
  // Check 3: Similar names (potential typos or variants)
  console.log('\n\n=== CHECK 3: SIMILAR NAMES (POTENTIAL DUPLICATES) ===');
  console.log('(Same location, very similar names - likely typos)');
  let similarNames = 0;
  
  for (let i = 0; i < stamps.length; i++) {
    for (let j = i + 1; j < stamps.length; j++) {
      // Same city/state (skip if city/state are undefined)
      if (stamps[i].city && stamps[j].city &&
          stamps[i].city === stamps[j].city && 
          stamps[i].state === stamps[j].state &&
          stamps[i].country === stamps[j].country) {
        
        // Similar names (within 2 edits only - stricter for fewer false positives)
        const similarity = levenshteinDistance(
          stamps[i].name.toLowerCase(), 
          stamps[j].name.toLowerCase()
        );
        
        if (similarity <= 2 && stamps[i].name !== stamps[j].name) {
          similarNames++;
          console.log(`\n⚠️  SIMILAR NAMES in same location:`);
          console.log(`   "${stamps[i].name}" (${stamps[i].id})`);
          console.log(`   "${stamps[j].name}" (${stamps[j].id})`);
          console.log(`   Location: ${stamps[i].city}, ${stamps[i].state}`);
          console.log(`   Edit distance: ${similarity}`);
        }
      }
    }
  }
  
  if (similarNames === 0) {
    console.log('✅ No similar name duplicates found');
  } else {
    console.log(`\n🟡 Found ${similarNames} similar name(s) - review manually`);
  }
  
  // Summary
  console.log('\n\n=== SUMMARY ===');
  if (exactNameDupes === 0 && gpsDupes === 0 && similarNames === 0) {
    console.log('✅ NO DUPLICATES FOUND! Database is clean.');
  } else {
    console.log(`Found ${exactNameDupes + gpsDupes + similarNames} potential issues:`);
    console.log(`  - ${exactNameDupes} exact name duplicates`);
    console.log(`  - ${gpsDupes} GPS coordinate duplicates`);
    console.log(`  - ${similarNames} similar names to review`);
    console.log('\n⚠️  ACTION NEEDED: Review and remove duplicates');
  }
  
  process.exit(0);
}

// Calculate distance between two GPS coordinates in meters
function getDistanceInMeters(lat1, lon1, lat2, lon2) {
  const R = 6371000; // Earth's radius in meters
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRadians(degrees) {
  return degrees * (Math.PI / 180);
}

// Calculate Levenshtein distance (edit distance) between two strings
function levenshteinDistance(str1, str2) {
  const matrix = [];
  
  for (let i = 0; i <= str2.length; i++) {
    matrix[i] = [i];
  }
  
  for (let j = 0; j <= str1.length; j++) {
    matrix[0][j] = j;
  }
  
  for (let i = 1; i <= str2.length; i++) {
    for (let j = 1; j <= str1.length; j++) {
      if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }
  
  return matrix[str2.length][str1.length];
}

checkForDuplicates().catch(console.error);

