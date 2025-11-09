#!/usr/bin/env node

/**
 * Generate Invite Codes for Stampbook
 * 
 * Usage:
 *   node generate_invite_codes.js 50          (50 multi-use codes)
 *   node generate_invite_codes.js 10 --single (10 single-use codes)
 * 
 * Multi-use codes: Unlimited people can use them (for Twitter drops, etc)
 * Single-use codes: One person only (for exclusive invites)
 */

const admin = require('firebase-admin');
const crypto = require('crypto');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

/**
 * Generate random code without confusing characters
 * Format: 8 uppercase characters (letters + numbers)
 * Excludes: 0, O, 1, I, L (easy to confuse)
 */
function generateCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  let code = '';
  const bytes = crypto.randomBytes(8);
  
  for (let i = 0; i < 8; i++) {
    code += chars[bytes[i] % chars.length];
  }
  
  return code;
}

/**
 * Create a single invite code in Firestore
 * Recursively retries if collision detected
 */
async function createInviteCode(maxUses = 999999, type = 'admin') {
  const code = generateCode();
  
  // Check for collision (very unlikely but possible)
  const docRef = db.collection('invite_codes').doc(code);
  const existing = await docRef.get();
  
  if (existing.exists) {
    console.log(`⚠️  Collision detected: ${code}, regenerating...`);
    return createInviteCode(maxUses, type);
  }
  
  // Create the code document
  await docRef.set({
    code: code,
    type: type,
    createdBy: 'admin',
    maxUses: maxUses,
    usedCount: 0,
    usedBy: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: null,
    status: 'active'
  });
  
  return code;
}

/**
 * Generate multiple codes
 */
async function generateCodes(count, singleUse = false) {
  const maxUses = singleUse ? 1 : 999999;
  const type = singleUse ? 'single-use' : 'multi-use';
  
  console.log(`\n🎫 Generating ${count} ${type} invite codes...\n`);
  
  const codes = [];
  
  for (let i = 0; i < count; i++) {
    try {
      const code = await createInviteCode(maxUses);
      codes.push(code);
      console.log(`✓ ${i + 1}/${count}: ${code}`);
    } catch (error) {
      console.error(`✗ Error generating code ${i + 1}:`, error.message);
    }
  }
  
  console.log(`\n✅ Successfully generated ${codes.length} codes!\n`);
  console.log('━'.repeat(40));
  console.log('COPY THESE CODES:');
  console.log('━'.repeat(40));
  codes.forEach(code => console.log(code));
  console.log('━'.repeat(40));
  console.log(`\nType: ${type}`);
  console.log(`Max uses per code: ${singleUse ? '1 person' : 'unlimited'}`);
  console.log(`\nShare these codes to control app growth! 🚀\n`);
}

// Parse command line arguments
const args = process.argv.slice(2);
const count = parseInt(args[0]) || 10;
const singleUse = args.includes('--single');

if (isNaN(count) || count < 1 || count > 1000) {
  console.error('❌ Error: Count must be between 1 and 1000');
  console.log('\nUsage:');
  console.log('  node generate_invite_codes.js 50          (50 multi-use codes)');
  console.log('  node generate_invite_codes.js 10 --single (10 single-use codes)');
  process.exit(1);
}

// Run the generator
generateCodes(count, singleUse)
  .then(() => process.exit(0))
  .catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  });

