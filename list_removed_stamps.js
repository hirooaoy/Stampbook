#!/usr/bin/env node

/**
 * List all removed/hidden stamps (audit tool)
 * 
 * Shows all stamps that are not active with reasons and dates.
 * 
 * Usage: node list_removed_stamps.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function listRemovedStamps() {
  console.log('🔍 Checking stamp status...\n');
  
  try {
    const snapshot = await db.collection('stamps').get();
    
    const removed = [];
    const hidden = [];
    let activeCount = 0;
    
    snapshot.docs.forEach(doc => {
      const data = doc.data();
      const status = data.status || 'active';
      
      if (status === 'removed') {
        removed.push({ id: doc.id, ...data });
      } else if (status === 'hidden') {
        hidden.push({ id: doc.id, ...data });
      } else {
        activeCount++;
      }
    });
    
    console.log(`📊 Stamp Status Summary:`);
    console.log(`   Active: ${activeCount}`);
    console.log(`   Removed: ${removed.length}`);
    console.log(`   Hidden: ${hidden.length}`);
    console.log(`   Total: ${snapshot.size}\n`);
    
    if (removed.length > 0) {
      console.log('❌ REMOVED STAMPS:\n');
      removed.forEach(stamp => {
        console.log(`   ${stamp.id}`);
        console.log(`   Name: ${stamp.name}`);
        console.log(`   Reason: ${stamp.removalReason || 'No reason provided'}`);
        if (stamp.removedAt) {
          console.log(`   Removed: ${stamp.removedAt.toDate().toISOString()}`);
        }
        console.log('');
      });
    }
    
    if (hidden.length > 0) {
      console.log('🙈 HIDDEN STAMPS:\n');
      hidden.forEach(stamp => {
        console.log(`   ${stamp.id}`);
        console.log(`   Name: ${stamp.name}`);
        console.log(`   Reason: ${stamp.removalReason || 'Under review'}`);
        console.log('');
      });
    }
    
    if (removed.length === 0 && hidden.length === 0) {
      console.log('✅ No removed or hidden stamps\n');
    }
    
  } catch (error) {
    console.error('❌ Error listing stamps:', error.message);
    process.exit(1);
  }
  
  process.exit(0);
}

listRemovedStamps();

