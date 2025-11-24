#!/usr/bin/env node

/**
 * Check New Stamps - Verification Script
 * 
 * Run this when user asks "check the new stamps"
 * 
 * This will:
 * 1. Compare Firebase vs Local to find new stamps
 * 2. Verify all required fields are present
 * 3. Check collection counts are correct
 * 4. Pull new stamps to local JSON
 * 5. Show a summary of what's new
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

const STAMPS_PATH = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
const COLLECTIONS_PATH = path.join(__dirname, 'Stampbook', 'Data', 'collections.json');

const REQUIRED_FIELDS = [
  'id', 'name', 'latitude', 'longitude', 'geohash', 'address', 
  'imageUrl', 'collectionIds', 'about', 'thingsToDoFromEditors', 
  'aspectRatio', 'collectionRadius'
];

async function checkNewStamps() {
  console.log('🔍 Checking for new stamps...\n');
  
  try {
    // Read current local data
    const localStamps = JSON.parse(fs.readFileSync(STAMPS_PATH, 'utf8'));
    const localCollections = JSON.parse(fs.readFileSync(COLLECTIONS_PATH, 'utf8'));
    
    // Fetch from Firebase
    const stampsSnapshot = await db.collection('stamps').get();
    const collectionsSnapshot = await db.collection('collections').get();
    
    const firebaseStamps = stampsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    const firebaseCollections = collectionsSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    
    console.log('📊 Firebase: ' + firebaseStamps.length + ' stamps');
    console.log('📊 Local: ' + localStamps.length + ' stamps\n');
    
    // Check for duplicates FIRST (critical check)
    console.log('🔍 Checking for duplicate stamps...\n');
    const duplicates = await checkForDuplicateStamps(firebaseStamps);
    
    if (duplicates.length > 0) {
      console.log('❌ CRITICAL: Found ' + duplicates.length + ' duplicate stamp(s)!\n');
      duplicates.forEach(dupe => {
        console.log('⚠️  "' + dupe.name + '" appears ' + dupe.count + ' times:');
        dupe.stamps.forEach(s => {
          console.log('   - ID: ' + s.id);
          console.log('     GPS: ' + s.latitude + ', ' + s.longitude);
        });
        console.log('');
      });
      console.log('🛑 FIX REQUIRED: Run "node remove_duplicate_stamp.js <stamp-id>" to remove duplicates');
      console.log('   Choose the stamp ID that has NO collectors (check Firebase console)\n');
      process.exit(1);
    } else {
      console.log('✅ No duplicates found\n');
    }
    
    // Find what's new
    const localStampIds = new Set(localStamps.map(s => s.id));
    const newStamps = firebaseStamps.filter(s => !localStampIds.has(s.id));
    
    if (newStamps.length === 0) {
      console.log('✅ No new stamps found. Everything is synced!\n');
      process.exit(0);
    }
    
    console.log('✨ FOUND ' + newStamps.length + ' NEW STAMP' + (newStamps.length > 1 ? 'S' : '') + ':\n');
    
    let allGood = true;
    
    // Check each new stamp
    for (const stamp of newStamps) {
      console.log('📍 ' + stamp.name + ' (' + stamp.id + ')');
      
      // Check required fields
      const missingFields = REQUIRED_FIELDS.filter(field => !stamp[field]);
      if (missingFields.length > 0) {
        console.log('   ❌ Missing fields: ' + missingFields.join(', '));
        allGood = false;
      } else {
        console.log('   ✅ All required fields present');
      }
      
      // Check image URL
      if (stamp.imageUrl) {
        if (!stamp.imageUrl.includes('firebasestorage.googleapis.com')) {
          console.log('   ⚠️  Image URL doesn\'t look like Firebase Storage URL');
          allGood = false;
        }
      }
      
      // Check aspect ratio
      if (stamp.aspectRatio && (stamp.aspectRatio < 0.5 || stamp.aspectRatio > 2.5)) {
        console.log('   ⚠️  Unusual aspect ratio: ' + stamp.aspectRatio);
      }
      
      // Check collection
      if (stamp.collectionIds && stamp.collectionIds.length > 0) {
        const collection = firebaseCollections.find(c => stamp.collectionIds.includes(c.id));
        if (collection) {
          console.log('   📚 Collection: ' + collection.emoji + ' ' + collection.name);
        } else {
          console.log('   ❌ Collection not found: ' + stamp.collectionIds[0]);
          allGood = false;
        }
      } else {
        console.log('   ℹ️  No collection (standalone stamp)');
      }
      
      // Check things to do count
      if (stamp.thingsToDoFromEditors) {
        const count = stamp.thingsToDoFromEditors.length;
        if (count < 2 || count > 3) {
          console.log('   ⚠️  Has ' + count + ' things to do (should be 2-3)');
        }
      }
      
      // Check about length
      if (stamp.about) {
        const length = stamp.about.length;
        if (length < 130 || length > 155) {
          console.log('   ⚠️  About section is ' + length + ' chars (should be 130-155)');
        }
      }
      
      // Check collectionRadius makes sense
      if (stamp.collectionRadius) {
        const name = stamp.name.toLowerCase();
        const about = (stamp.about || '').toLowerCase();
        const thingsToDo = (stamp.thingsToDoFromEditors || []).join(' ').toLowerCase();
        const combined = name + ' ' + about + ' ' + thingsToDo;
        
        // Keywords that suggest regularplus (hard to access locations)
        const regularplusKeywords = [
          'summit', 'peak', 'trail', 'trailhead', 'hike', 'climb', 
          'mountain', 'ridge', 'pass', 'backcountry', 'canyon floor',
          'overlook', 'viewpoint', 'lookout', 'river-walk', 'wade',
          'elevation', 'ascent', 'trek', 'alpine'
        ];
        
        // Keywords that suggest regular (easily accessible)
        const regularKeywords = [
          'museum', 'park entrance', 'visitor center', 'beach', 'plaza',
          'building', 'cafe', 'coffee', 'restaurant', 'shop', 'station', 'airport',
          'library', 'garden', 'fountain', 'monument', 'pier', 'carousel',
          'parking', 'drive to', 'walk from parking'
        ];
        
        const hasRegularplusKeywords = regularplusKeywords.some(keyword => combined.includes(keyword));
        const hasRegularKeywords = regularKeywords.some(keyword => combined.includes(keyword));
        
        if (stamp.collectionRadius === 'regularplus' && hasRegularKeywords && !hasRegularplusKeywords) {
          console.log('   ⚠️  "regularplus" radius may not be needed for accessible location');
        } else if (stamp.collectionRadius === 'regular' && hasRegularplusKeywords && !hasRegularKeywords) {
          console.log('   💡 Consider "regularplus" radius for summit/trail/hike location');
        } else {
          console.log('   ✅ Collection radius (' + stamp.collectionRadius + ') looks appropriate');
        }
      }
      
      console.log('');
    }
    
    // Check collection counts
    console.log('🔍 Checking collection counts...\n');
    
    let collectionIssues = false;
    const collectionStampCounts = {};
    
    firebaseStamps.forEach(stamp => {
      if (stamp.collectionIds) {
        stamp.collectionIds.forEach(collectionId => {
          collectionStampCounts[collectionId] = (collectionStampCounts[collectionId] || 0) + 1;
        });
      }
    });
    
    for (const collection of firebaseCollections) {
      const actualCount = collectionStampCounts[collection.id] || 0;
      const expectedCount = collection.totalStamps || 0;
      
      if (actualCount !== expectedCount) {
        console.log('⚠️  ' + collection.emoji + ' ' + collection.name);
        console.log('   Expected: ' + expectedCount + ', Actual: ' + actualCount);
        collectionIssues = true;
        allGood = false;
      }
    }
    
    if (!collectionIssues) {
      console.log('✅ All collection counts are correct!\n');
    } else {
      console.log('');
    }
    
    // Summary
    if (allGood) {
      console.log('🎉 Everything looks great!\n');
    } else {
      console.log('⚠️  Some issues found above. Review before syncing.\n');
    }
    
    // Ask to sync
    console.log('📥 Syncing to local JSON...\n');
    
    // Sort stamps by ID for consistency
    firebaseStamps.sort((a, b) => a.id.localeCompare(b.id));
    firebaseCollections.sort((a, b) => a.id.localeCompare(b.id));
    
    // Write to local files
    fs.writeFileSync(STAMPS_PATH, JSON.stringify(firebaseStamps, null, 2));
    console.log('✅ Updated ' + STAMPS_PATH);
    
    fs.writeFileSync(COLLECTIONS_PATH, JSON.stringify(firebaseCollections, null, 2));
    console.log('✅ Updated ' + COLLECTIONS_PATH);
    
    console.log('\n🎉 Local files synced with Firebase!\n');
    
    process.exit(0);
    
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

// Helper function to check for duplicate stamps
async function checkForDuplicateStamps(stamps) {
  const nameMap = {};
  const duplicates = [];
  
  stamps.forEach(stamp => {
    if (!nameMap[stamp.name]) {
      nameMap[stamp.name] = [];
    }
    nameMap[stamp.name].push(stamp);
  });
  
  Object.entries(nameMap).forEach(([name, stampList]) => {
    if (stampList.length > 1) {
      duplicates.push({
        name: name,
        count: stampList.length,
        stamps: stampList
      });
    }
  });
  
  return duplicates;
}

checkNewStamps();

