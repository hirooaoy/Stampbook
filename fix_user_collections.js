#!/usr/bin/env node

/**
 * Fix user collections after stamp ID changes
 * Updates collectedStamps to reference new stamp IDs
 * 
 * Usage: node fix_user_collections.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixUserCollections() {
    console.log('🔧 Fixing user collections after stamp ID changes...\n');
    
    // Load the ID mapping from stamp_matches.json
    const matchesPath = path.join(__dirname, 'stamp_matches.json');
    if (!fs.existsSync(matchesPath)) {
        console.log('❌ No matches found. This should have been created earlier.');
        process.exit(1);
    }
    
    const matches = JSON.parse(fs.readFileSync(matchesPath, 'utf8'));
    
    // Create a map: oldId -> newId
    const idMapping = {};
    for (const match of matches) {
        idMapping[match.stampId] = match.matchedFile;
    }
    
    console.log(`📋 Found ${Object.keys(idMapping).length} stamp ID changes:\n`);
    for (const [oldId, newId] of Object.entries(idMapping)) {
        console.log(`   ${oldId} → ${newId}`);
    }
    console.log('');
    
    // Get all users
    const usersSnapshot = await db.collection('users').get();
    console.log(`👥 Found ${usersSnapshot.size} users\n`);
    
    let totalUpdates = 0;
    
    for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        
        // Get user's collected stamps subcollection
        const collectedStampsSnapshot = await db
            .collection('users')
            .doc(userId)
            .collection('collectedStamps')
            .get();
        
        if (collectedStampsSnapshot.empty) {
            continue;
        }
        
        console.log(`🔍 Checking ${userData.username || userId} (${collectedStampsSnapshot.size} stamps)...`);
        
        const batch = db.batch();
        let userUpdateCount = 0;
        
        for (const stampDoc of collectedStampsSnapshot.docs) {
            const stampId = stampDoc.id;
            
            // Check if this stamp ID was changed
            if (idMapping[stampId]) {
                const newStampId = idMapping[stampId];
                const stampData = stampDoc.data();
                
                console.log(`   ✓ Migrating: ${stampId} → ${newStampId}`);
                
                // Create new document with new ID
                const newRef = db
                    .collection('users')
                    .doc(userId)
                    .collection('collectedStamps')
                    .doc(newStampId);
                
                batch.set(newRef, {
                    ...stampData,
                    stampId: newStampId // Update stampId field too
                });
                
                // Delete old document
                batch.delete(stampDoc.ref);
                
                userUpdateCount++;
                totalUpdates++;
            }
        }
        
        if (userUpdateCount > 0) {
            await batch.commit();
            console.log(`   ✅ Updated ${userUpdateCount} stamps for ${userData.username || userId}\n`);
        } else {
            console.log(`   ⏭️  No changes needed\n`);
        }
    }
    
    console.log('============================================');
    if (totalUpdates > 0) {
        console.log(`✅ Fixed ${totalUpdates} collected stamps across all users`);
    } else {
        console.log('✅ No collected stamps needed fixing');
    }
    console.log('============================================\n');
    
    process.exit(0);
}

fixUserCollections().catch(error => {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
});

