#!/usr/bin/env node

/**
 * Script to fix uniqueCountriesVisited count for users
 * 
 * This script:
 * 1. Fetches all users
 * 2. For each user, fetches their collected stamps
 * 3. Fetches stamp data to get addresses
 * 4. Calculates unique countries
 * 5. Updates user profile with correct count
 */

const admin = require('firebase-admin');
const fs = require('fs');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Parse country from stamp address
 * @param {string} address - Stamp address in format "Street\nCity, State, Country PostalCode"
 * @returns {string|null} - Country code or null
 */
function parseCountryFromAddress(address) {
  const lines = address.split('\n');
  if (lines.length < 2) {
    console.warn(`⚠️  Invalid address format: ${address}`);
    return null;
  }
  
  const secondLine = lines[1];
  const parts = secondLine.split(',').map(p => p.trim());
  
  if (parts.length >= 3) {
    // Format: "City, State, Country PostalCode"
    const countryPart = parts[2].split(' ')[0];
    return countryPart || null;
  } else if (parts.length === 2) {
    // Format: "City, Country"
    const countryPart = parts[1].split(' ')[0];
    return countryPart || null;
  }
  
  console.warn(`⚠️  Unexpected address format: ${address}`);
  return null;
}

/**
 * Calculate unique countries for a user
 * @param {string} userId - User ID
 * @returns {Promise<{totalStamps: number, uniqueCountries: number}>}
 */
async function calculateUserStats(userId) {
  // Fetch user's collected stamps
  const collectedStampsSnapshot = await db
    .collection('users')
    .doc(userId)
    .collection('collected_stamps')
    .get();
  
  const totalStamps = collectedStampsSnapshot.size;
  const stampIds = collectedStampsSnapshot.docs.map(doc => doc.id);
  
  if (stampIds.length === 0) {
    return { totalStamps: 0, uniqueCountries: 0 };
  }
  
  // Fetch stamp data in batches (Firestore 'in' operator limit is 10)
  const stamps = [];
  for (let i = 0; i < stampIds.length; i += 10) {
    const batch = stampIds.slice(i, i + 10);
    const stampsSnapshot = await db
      .collection('stamps')
      .where(admin.firestore.FieldPath.documentId(), 'in', batch)
      .get();
    
    stampsSnapshot.docs.forEach(doc => {
      stamps.push({ id: doc.id, ...doc.data() });
    });
  }
  
  // Extract unique countries
  const countries = new Set();
  stamps.forEach(stamp => {
    const country = parseCountryFromAddress(stamp.address);
    if (country) {
      countries.add(country);
    }
  });
  
  return {
    totalStamps,
    uniqueCountries: countries.size
  };
}

/**
 * Fix country counts for all users
 */
async function fixCountryCounts() {
  console.log('🔄 Starting country count reconciliation...\n');
  
  // Fetch all users
  const usersSnapshot = await db.collection('users').get();
  console.log(`📊 Found ${usersSnapshot.size} users\n`);
  
  let updatedCount = 0;
  let alreadyCorrectCount = 0;
  
  for (const userDoc of usersSnapshot.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data();
    
    console.log(`\n🔍 Checking user: ${userData.displayName} (${userId})`);
    
    // Calculate actual stats
    const { totalStamps, uniqueCountries } = await calculateUserStats(userId);
    
    console.log(`   Current: ${userData.totalStamps || 0} stamps, ${userData.uniqueCountriesVisited || 0} countries`);
    console.log(`   Actual:  ${totalStamps} stamps, ${uniqueCountries} countries`);
    
    // Check if update needed
    if (userData.totalStamps !== totalStamps || userData.uniqueCountriesVisited !== uniqueCountries) {
      await db.collection('users').doc(userId).update({
        totalStamps,
        uniqueCountriesVisited: uniqueCountries,
        lastActiveAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      console.log(`   ✅ Updated!`);
      updatedCount++;
    } else {
      console.log(`   ✓ Already correct`);
      alreadyCorrectCount++;
    }
  }
  
  console.log(`\n✅ Reconciliation complete!`);
  console.log(`   Updated: ${updatedCount} users`);
  console.log(`   Already correct: ${alreadyCorrectCount} users`);
  console.log(`   Total: ${usersSnapshot.size} users`);
}

// Run the script
fixCountryCounts()
  .then(() => {
    console.log('\n✅ Done!');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Error:', error);
    process.exit(1);
  });

