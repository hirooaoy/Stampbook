#!/usr/bin/env node

/**
 * Create a Custom Invite Code
 * 
 * Usage:
 *   node create_custom_code.js STAMPBOOKBETA 15
 *   node create_custom_code.js LAUNCH100 100
 *   node create_custom_code.js TESTCODE unlimited
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

async function createCustomCode(codeName, maxUses) {
  const codeString = codeName.toUpperCase();
  
  // Validate code format (letters and numbers only, 4-20 chars)
  if (!/^[A-Z0-9]{4,20}$/.test(codeString)) {
    console.error('❌ Error: Code must be 4-20 characters (letters and numbers only)');
    process.exit(1);
  }
  
  // Check if code already exists
  const existing = await db.collection('invite_codes').doc(codeString).get();
  if (existing.exists) {
    console.error(`❌ Error: Code "${codeString}" already exists`);
    console.log('\nCurrent stats:');
    const data = existing.data();
    console.log(`  Used: ${data.usedCount}/${data.maxUses === 999999 ? 'unlimited' : data.maxUses}`);
    console.log(`  Status: ${data.status}`);
    console.log('\nUse update_code_limit.js to modify existing codes.');
    process.exit(1);
  }
  
  const maxUsesNum = maxUses === 'unlimited' ? 999999 : parseInt(maxUses);
  
  if (isNaN(maxUsesNum) || maxUsesNum < 1) {
    console.error('❌ Error: Max uses must be a positive number or "unlimited"');
    process.exit(1);
  }
  
  // Create the code
  await db.collection('invite_codes').doc(codeString).set({
    code: codeString,
    type: 'admin',
    createdBy: 'admin',
    maxUses: maxUsesNum,
    usedCount: 0,
    usedBy: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: null,
    status: 'active'
  });
  
  console.log('\n✅ Code created successfully!\n');
  console.log('━'.repeat(50));
  console.log(`Code: ${codeString}`);
  console.log(`Max Uses: ${maxUsesNum === 999999 ? 'unlimited' : maxUsesNum}`);
  console.log(`Status: active`);
  console.log('━'.repeat(50));
  console.log(`\nShare this code: ${codeString}`);
  console.log(`Track usage: node check_invite_codes.js ${codeString}`);
  console.log(`Update limit: node update_code_limit.js ${codeString} <new_limit>\n`);
}

// Parse arguments
const codeName = process.argv[2];
const maxUses = process.argv[3] || 'unlimited';

if (!codeName) {
  console.log('Usage: node create_custom_code.js <CODE_NAME> <max_uses>');
  console.log('');
  console.log('Examples:');
  console.log('  node create_custom_code.js STAMPBOOKBETA 15');
  console.log('  node create_custom_code.js LAUNCH100 100');
  console.log('  node create_custom_code.js TESTCODE unlimited');
  console.log('');
  console.log('Code requirements:');
  console.log('  - 4-20 characters');
  console.log('  - Letters and numbers only');
  console.log('  - Will be converted to uppercase');
  process.exit(1);
}

createCustomCode(codeName, maxUses)
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  });

