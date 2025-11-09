#!/usr/bin/env node

/**
 * Update Code Limit
 * 
 * Increase or decrease the max uses for an existing code
 * 
 * Usage:
 *   node update_code_limit.js STAMPBOOKBETA 30    (increase from 15 to 30)
 *   node update_code_limit.js TESTCODE unlimited  (make unlimited)
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

async function updateCodeLimit(codeName, newMaxUses) {
  const codeString = codeName.toUpperCase();
  
  // Check if code exists
  const docRef = db.collection('invite_codes').doc(codeString);
  const doc = await docRef.get();
  
  if (!doc.exists) {
    console.error(`❌ Error: Code "${codeString}" not found`);
    console.log('\nCreate it with: node create_custom_code.js ' + codeString);
    process.exit(1);
  }
  
  const data = doc.data();
  const oldMaxUses = data.maxUses;
  const usedCount = data.usedCount;
  
  const newMaxUsesNum = newMaxUses === 'unlimited' ? 999999 : parseInt(newMaxUses);
  
  if (isNaN(newMaxUsesNum) || newMaxUsesNum < 1) {
    console.error('❌ Error: New max uses must be a positive number or "unlimited"');
    process.exit(1);
  }
  
  // Validate: new limit must be >= current used count
  if (newMaxUsesNum < usedCount) {
    console.error(`❌ Error: New limit (${newMaxUsesNum}) cannot be less than current uses (${usedCount})`);
    console.log(`\nCode "${codeString}" has already been used ${usedCount} times.`);
    console.log(`Minimum new limit: ${usedCount}`);
    process.exit(1);
  }
  
  // Update the limit
  const newStatus = (usedCount >= newMaxUsesNum) ? 'used' : 'active';
  
  await docRef.update({
    maxUses: newMaxUsesNum,
    status: newStatus
  });
  
  console.log('\n✅ Code limit updated successfully!\n');
  console.log('━'.repeat(50));
  console.log(`Code: ${codeString}`);
  console.log(`Old Limit: ${oldMaxUses === 999999 ? 'unlimited' : oldMaxUses}`);
  console.log(`New Limit: ${newMaxUsesNum === 999999 ? 'unlimited' : newMaxUsesNum}`);
  console.log(`Used: ${usedCount}`);
  console.log(`Remaining: ${newMaxUsesNum === 999999 ? 'unlimited' : newMaxUsesNum - usedCount}`);
  console.log(`Status: ${newStatus}`);
  console.log('━'.repeat(50));
  console.log();
}

// Parse arguments
const codeName = process.argv[2];
const newMaxUses = process.argv[3];

if (!codeName || !newMaxUses) {
  console.log('Usage: node update_code_limit.js <CODE_NAME> <new_max_uses>');
  console.log('');
  console.log('Examples:');
  console.log('  node update_code_limit.js STAMPBOOKBETA 30       (increase to 30 uses)');
  console.log('  node update_code_limit.js STAMPBOOKBETA unlimited (make unlimited)');
  console.log('  node update_code_limit.js LAUNCH100 200          (double the limit)');
  process.exit(1);
}

updateCodeLimit(codeName, newMaxUses)
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  });

