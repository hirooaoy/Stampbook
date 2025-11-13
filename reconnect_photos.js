#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function reconnectPhotos() {
    console.log('🔧 Reconnecting photos and fixing dates...\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const updates = [
        {
            stampId: 'us-ca-sf-ballast-coffee',
            collectedDate: new Date('2025-11-12T18:00:00'),
            userImageNames: ['us-ca-sf-ballast_1762641998_17CD1473.jpg', 'us-ca-sf-ballast_1762641998_80C80E39.jpg'],
            userImagePaths: [
                'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-ca-sf-ballast-coffee/us-ca-sf-ballast_1762641998_17CD1473.jpg',
                'users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-ca-sf-ballast-coffee/us-ca-sf-ballast_1762641998_80C80E39.jpg'
            ]
        },
        {
            stampId: 'us-me-bar-harbor-beals',
            collectedDate: new Date('2025-10-31T19:51:00'),
            userImageNames: ['us-me-acadia-beals-lobster-pier_1761977466_D46C5400.jpg'],
            userImagePaths: ['users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-me-bar-harbor-beals/us-me-acadia-beals-lobster-pier_1761977466_D46C5400.jpg']
        },
        {
            stampId: 'us-me-bar-harbor-mckays-public-house',
            collectedDate: new Date('2025-11-05T19:31:00'),
            userImageNames: ['us-me-bar-harbor-mckays-public-house_1762466664_87FAA137.jpg'],
            userImagePaths: ['users/mpd4k2n13adMFMY52nksmaQTbMQ2/stamps/us-me-bar-harbor-mckays-public-house/us-me-bar-harbor-mckays-public-house_1762466664_87FAA137.jpg']
        }
    ];
    
    for (const update of updates) {
        const ref = db.collection('users').doc(userId).collection('collectedStamps').doc(update.stampId);
        
        await ref.update({
            collectedDate: update.collectedDate,
            userImageNames: update.userImageNames,
            userImagePaths: update.userImagePaths
        });
        
        console.log(`✅ ${update.stampId}`);
        console.log(`   Date: ${update.collectedDate.toDateString()}`);
        console.log(`   Photos: ${update.userImageNames.length}\n`);
    }
    
    console.log('✅ Done! Photos reconnected and dates fixed.\n');
    
    process.exit(0);
}

reconnectPhotos().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

