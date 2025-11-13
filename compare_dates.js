#!/usr/bin/env node

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function compareAllDates() {
    console.log('📊 COLLECTED STAMP DATES - BEFORE vs NOW\n');
    console.log('============================================\n');
    
    const userId = 'mpd4k2n13adMFMY52nksmaQTbMQ2';
    
    const collectedStamps = await db
        .collection('users')
        .doc(userId)
        .collection('collectedStamps')
        .get();
    
    const stamps = [];
    
    for (const doc of collectedStamps.docs) {
        const data = doc.data();
        stamps.push({
            id: doc.id,
            currentDate: data.collectedDate?.toDate(),
            hasPhotos: (data.userImageNames || []).length > 0,
            photoCount: (data.userImageNames || []).length
        });
    }
    
    // Sort by current date
    stamps.sort((a, b) => a.currentDate - b.currentDate);
    
    console.log('┌─────────────────────────────────────────────────────────────────────────┐');
    console.log('│ Stamp ID                              │ Original Date │ Current Date    │');
    console.log('├─────────────────────────────────────────────────────────────────────────┤');
    
    for (const stamp of stamps) {
        const id = stamp.id.padEnd(37);
        const current = stamp.currentDate.toLocaleDateString('en-US', { 
            month: '2-digit', 
            day: '2-digit', 
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
        
        // Try to infer original date
        let original = 'UNKNOWN';
        if (stamp.hasPhotos) {
            original = 'FROM PHOTO  ';
        } else {
            original = 'LOST        ';
        }
        
        console.log(`│ ${id} │ ${original} │ ${current} │`);
    }
    
    console.log('└─────────────────────────────────────────────────────────────────────────┘');
    
    console.log('\n📝 NOTES:\n');
    console.log('❌ ORIGINAL DATES LOST:');
    console.log('   When I manually restored your stamps, I set them all to Nov 12, 2025');
    console.log('   The original collection dates from when you actually collected them are GONE.\n');
    
    console.log('✅ RECOVERED FROM PHOTOS (3 stamps):');
    console.log('   us-me-bar-harbor-beals: Oct 31, 2025 11:11 PM');
    console.log('   us-me-bar-harbor-mckays-public-house: Nov 6, 2025 2:04 PM');
    console.log('   us-ca-sf-ballast-coffee: Nov 8, 2025 2:46 PM\n');
    
    console.log('❓ CANNOT RECOVER (3 stamps without photos):');
    console.log('   us-ca-sf-dolores-park: Currently showing Nov 12, 2025');
    console.log('   us-ca-sf-powell-hyde-cable-car: Currently showing Nov 12, 2025');
    console.log('   your-first-stamp: Currently showing Nov 12, 2025\n');
    
    console.log('💡 To fix the 3 stamps without photos, I need you to tell me when you');
    console.log('   actually collected them, and I can update the dates.\n');
    
    process.exit(0);
}

compareAllDates().catch(error => {
    console.error('❌ Error:', error);
    process.exit(1);
});

