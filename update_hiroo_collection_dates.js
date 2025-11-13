#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function updateHirooCollectionDates() {
    console.log('📅 Updating hiroo\'s stamp collection dates...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2'; // hiroo's user ID
    
    const correctDates = {
        'your-first-stamp': new Date('2025-10-23T12:00:00'),
        'us-ca-sf-ballast-coffee': new Date('2025-11-08T12:00:00'),
        'us-ca-sf-powell-hyde-cable-car': new Date('2025-10-25T12:00:00'),
        'us-ca-sf-dolores-park': new Date('2025-11-07T12:00:00'),
        'us-me-bar-harbor-beals': new Date('2025-10-28T12:00:00'),
        'us-me-bar-harbor-mckays-public-house': new Date('2025-10-27T12:00:00')
    };
    
    console.log('Updating to:\n');
    
    // Sort by date to show chronological order
    const sorted = Object.entries(correctDates).sort((a, b) => a[1] - b[1]);
    
    for (const [stampId, date] of sorted) {
        const ref = db.collection('users').doc(userId).collection('collectedStamps').doc(stampId);
        
        // Check if the document exists first
        const doc = await ref.get();
        if (!doc.exists) {
            console.log(`⚠️  ${stampId} - NOT COLLECTED YET, SKIPPING`);
            continue;
        }
        
        await ref.update({ collectedDate: date });
        
        console.log(`✅ ${stampId}`);
        console.log(`   ${date.toLocaleDateString('en-US', { 
            weekday: 'short',
            month: 'short', 
            day: 'numeric',
            year: 'numeric'
        })}\n`);
    }
    
    console.log('============================================');
    console.log('✅ All dates updated successfully!\n');
    console.log('Feed will now show in chronological order:\n');
    sorted.forEach((entry, i) => {
        const stampName = {
            'your-first-stamp': 'Welcome Stamp',
            'us-ca-sf-ballast-coffee': 'Ballast Coffee',
            'us-ca-sf-powell-hyde-cable-car': 'Powell-Hyde Cable Car',
            'us-ca-sf-dolores-park': 'Dolores Park',
            'us-me-bar-harbor-beals': 'Beal\'s Lobster Pier',
            'us-me-bar-harbor-mckays-public-house': 'McKay\'s Public House'
        }[entry[0]];
        
        console.log(`   ${i + 1}. ${entry[1].toLocaleDateString('en-US', { 
            month: 'short', 
            day: 'numeric',
            year: 'numeric'
        })} - ${stampName}`);
    });
    console.log('============================================\n');
    
    process.exit(0);
}

updateHirooCollectionDates().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

