#!/usr/bin/env node

/**
 * Check Invite Code Usage
 * 
 * Usage:
 *   node check_invite_codes.js              (list all codes)
 *   node check_invite_codes.js SUMMIT24     (check specific code)
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function listAllCodes() {
  console.log('\n📋 All Invite Codes:\n');
  
  const snapshot = await db.collection('invite_codes').get();
  
  if (snapshot.empty) {
    console.log('No invite codes found.');
    return;
  }
  
  const codes = [];
  snapshot.forEach(doc => {
    const data = doc.data();
    codes.push({
      code: data.code,
      type: data.type,
      usedCount: data.usedCount,
      maxUses: data.maxUses,
      status: data.status,
      createdAt: data.createdAt?.toDate()
    });
  });
  
  // Sort by creation date (newest first)
  codes.sort((a, b) => b.createdAt - a.createdAt);
  
  console.log('━'.repeat(80));
  console.log(`${'CODE'.padEnd(12)} ${'TYPE'.padEnd(12)} ${'USES'.padEnd(15)} ${'STATUS'.padEnd(10)} CREATED`);
  console.log('━'.repeat(80));
  
  codes.forEach(code => {
    const uses = code.maxUses > 999999 
      ? `${code.usedCount}/unlimited`
      : `${code.usedCount}/${code.maxUses}`;
    
    const statusIcon = code.status === 'active' ? '✓' : '✗';
    const created = code.createdAt.toISOString().split('T')[0];
    
    console.log(
      `${code.code.padEnd(12)} ${code.type.padEnd(12)} ${uses.padEnd(15)} ${statusIcon} ${code.status.padEnd(8)} ${created}`
    );
  });
  
  console.log('━'.repeat(80));
  console.log(`\nTotal: ${codes.length} codes`);
  console.log(`Active: ${codes.filter(c => c.status === 'active').length}`);
  console.log(`Total uses: ${codes.reduce((sum, c) => sum + c.usedCount, 0)}\n`);
}

async function checkSpecificCode(code) {
  const codeString = code.toUpperCase();
  console.log(`\n🔍 Checking code: ${codeString}\n`);
  
  const doc = await db.collection('invite_codes').doc(codeString).get();
  
  if (!doc.exists) {
    console.log('❌ Code not found');
    return;
  }
  
  const data = doc.data();
  
  console.log('━'.repeat(60));
  console.log(`Code: ${data.code}`);
  console.log(`Type: ${data.type}`);
  console.log(`Status: ${data.status}`);
  console.log(`Max Uses: ${data.maxUses > 999999 ? 'unlimited' : data.maxUses}`);
  console.log(`Used Count: ${data.usedCount}`);
  console.log(`Created By: ${data.createdBy}`);
  console.log(`Created At: ${data.createdAt?.toDate().toISOString()}`);
  
  if (data.usedBy && data.usedBy.length > 0) {
    console.log(`\nUsed by ${data.usedBy.length} user(s):`);
    data.usedBy.forEach((userId, index) => {
      console.log(`  ${index + 1}. ${userId}`);
    });
  } else {
    console.log('\nNot yet used');
  }
  
  console.log('━'.repeat(60));
  console.log();
}

// Main
const arg = process.argv[2];

if (arg) {
  checkSpecificCode(arg)
    .then(() => process.exit(0))
    .catch(error => {
      console.error('❌ Error:', error);
      process.exit(1);
    });
} else {
  listAllCodes()
    .then(() => process.exit(0))
    .catch(error => {
      console.error('❌ Error:', error);
      process.exit(1);
    });
}

