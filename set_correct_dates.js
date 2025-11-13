#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function setCorrectDates() {
    console.log('📅 Setting correct collection dates...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const correctDates = {
        'your-first-stamp': new Date('2025-10-25T12:00:00'),
        'us-me-bar-harbor-mckays-public-house': new Date('2025-10-27T12:00:00'),
        'us-me-bar-harbor-beals': new Date('2025-10-28T12:00:00'),
        'us-ca-sf-dolores-park': new Date('2025-11-01T12:00:00'),
        'us-ca-sf-powell-hyde-cable-car': new Date('2025-11-02T12:00:00'),
        'us-ca-sf-ballast-coffee': new Date('2025-11-09T12:00:00')
    };
    
    console.log('Updating to:\n');
    
    // Sort by date to show chronological order
    const sorted = Object.entries(correctDates).sort((a, b) => a[1] - b[1]);
    
    for (const [stampId, date] of sorted) {
        const ref = db.collection('users').doc(userId).collection('collectedStamps').doc(stampId);
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
    console.log('✅ All dates updated to correct values!\n');
    console.log('Feed will now show in correct order:\n');
    sorted.forEach((entry, i) => {
        console.log(`   ${i + 1}. ${entry[1].toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} - ${entry[0]}`);
    });
    console.log('============================================\n');
    
    process.exit(0);
}

setCorrectDates().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

