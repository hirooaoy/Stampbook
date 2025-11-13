#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function fixDates() {
    console.log('🔧 Converting timestamps to proper dates...\n');
    
    // Extract timestamps from filenames
    const timestamps = {
        'us-me-bar-harbor-beals': 1761977466,  // From filename
        'us-me-bar-harbor-mckays-public-house': 1762466664,
        'us-ca-sf-ballast-coffee': 1762641998
    };
    
    console.log('Converting Unix timestamps:\n');
    
    const updates = [];
    for (const [stampId, timestamp] of Object.entries(timestamps)) {
        const date = new Date(timestamp * 1000); // Convert seconds to milliseconds
        console.log(`${stampId}:`);
        console.log(`   Timestamp: ${timestamp}`);
        console.log(`   Date: ${date.toLocaleString()}\n`);
        
        updates.push({ stampId, date });
    }
    
    // Sort by date to verify order
    updates.sort((a, b) => a.date - b.date);
    console.log('Chronological order (oldest to newest):');
    updates.forEach((u, i) => {
        console.log(`   ${i + 1}. ${u.stampId} - ${u.date.toLocaleString()}`);
    });
    
    console.log('\n📝 Updating Firestore...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    for (const update of updates) {
        const ref = db.collection('users').doc(userId).collection('collectedStamps').doc(update.stampId);
        await ref.update({ collectedDate: update.date });
        console.log(`✅ Updated ${update.stampId}`);
    }
    
    console.log('\n✅ Dates fixed with actual timestamps!\n');
    
    process.exit(0);
}

fixDates().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

