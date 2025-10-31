#!/usr/bin/env node

// Script to fix user totalStamps count based on actual collected stamps
// Run with: node fix_user_total_stamps.js

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixUserTotalStamps() {
  console.log('🔍 Fixing user totalStamps...\n');
  
  // Get all users
  const usersSnapshot = await db.collection('users').get();
  
  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data();
    const userName = userData.displayName || 'Unknown';
    const currentTotalStamps = userData.totalStamps || 0;
    
    console.log(`👤 Checking user: ${userName} (${userId})`);
    console.log(`  Current totalStamps in profile: ${currentTotalStamps}`);
    
    // Get all collected stamps for this user
    const collectedStampsSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('collected_stamps')
      .get();
    
    const actualTotal = collectedStampsSnapshot.docs.length;
    console.log(`  Actual collected stamps: ${actualTotal}`);
    
    // Calculate unique countries
    const stampIds = collectedStampsSnapshot.docs.map(doc => doc.id);
    const uniqueCountries = await calculateUniqueCountries(stampIds);
    
    const currentUniqueCountries = userData.uniqueCountriesVisited || 0;
    console.log(`  Current uniqueCountriesVisited in profile: ${currentUniqueCountries}`);
    console.log(`  Calculated uniqueCountriesVisited: ${uniqueCountries}`);
    
    if (actualTotal !== currentTotalStamps || uniqueCountries !== currentUniqueCountries) {
      console.log(`  ⚠️ MISMATCH! Updating...`);
      console.log(`    totalStamps: ${currentTotalStamps} → ${actualTotal}`);
      console.log(`    uniqueCountries: ${currentUniqueCountries} → ${uniqueCountries}`);
      
      await db.collection('users').doc(userId).update({
        totalStamps: actualTotal,
        uniqueCountriesVisited: uniqueCountries,
        lastActiveAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`  ✅ Updated totalStamps to ${actualTotal}, uniqueCountries to ${uniqueCountries}\n`);
    } else {
      console.log(`  ✅ Already correct\n`);
    }
  }
  
  console.log('✅ All user totalStamps are now correct!\n');
}

async function calculateUniqueCountries(stampIds) {
  if (stampIds.length === 0) return 0;
  
  const uniqueCountries = new Set();
  
  // Fetch stamps in batches (Firestore limit is 10 for 'in' queries)
  const BATCH_SIZE = 10;
  for (let i = 0; i < stampIds.length; i += BATCH_SIZE) {
    const batch = stampIds.slice(i, i + BATCH_SIZE);
    const stampsSnapshot = await db.collection('stamps')
      .where(admin.firestore.FieldPath.documentId(), 'in', batch)
      .get();
    
    stampsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      // Parse country from address (matching Swift logic)
      const lines = data.address.split('\n');
      if (lines.length >= 2) {
        const secondLine = lines[1];
        const parts = secondLine.split(',').map(p => p.trim());
        
        if (parts.length >= 3) {
          // Format: "City, State, Country PostalCode"
          const countryPart = parts[2].split(' ')[0];
          if (countryPart) {
            uniqueCountries.add(countryPart);
          }
        } else if (parts.length === 2) {
          // Format: "City, Country"
          const countryPart = parts[1].split(' ')[0];
          if (countryPart) {
            uniqueCountries.add(countryPart);
          }
        }
      }
    });
  }
  
  return uniqueCountries.size;
}

fixUserTotalStamps()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
  });

