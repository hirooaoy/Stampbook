#!/usr/bin/env node

/**
 * Update stamp IDs in stamps.json to match Firebase Storage filenames
 * Only updates matches with confidence >= 70%
 * 
 * Usage: node update_stamp_ids.js
 */

const fs = require('fs');
const path = require('path');

const MIN_CONFIDENCE = 70; // Only auto-update matches with 70%+ confidence

async function updateStampIds() {
    console.log('🔄 Updating stamp IDs to match Firebase Storage filenames...\n');
    
    // Load matches
    const matchesPath = path.join(__dirname, 'stamp_matches.json');
    if (!fs.existsSync(matchesPath)) {
        console.log('❌ No matches found. Run: node match_stamp_images.js first');
        process.exit(1);
    }
    
    const matches = JSON.parse(fs.readFileSync(matchesPath, 'utf8'));
    
    // Load stamps.json
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    console.log('📋 Updates to be made (>= 70% confidence):\n');
    
    let updateCount = 0;
    let skippedCount = 0;
    
    for (const match of matches) {
        const confidence = parseFloat(match.confidence);
        
        if (confidence >= MIN_CONFIDENCE) {
            // Find the stamp
            const stamp = stamps.find(s => s.id === match.stampId);
            
            if (stamp) {
                const oldId = stamp.id;
                const newId = match.matchedFile;
                
                console.log(`✅ ${confidence}% - "${stamp.name}"`);
                console.log(`   ${oldId} → ${newId}\n`);
                
                // Update the ID
                stamp.id = newId;
                updateCount++;
            }
        } else {
            console.log(`⏭️  Skipped ${confidence}% - "${match.stampName}" (below ${MIN_CONFIDENCE}% threshold)`);
            skippedCount++;
        }
    }
    
    if (updateCount === 0) {
        console.log('\n❌ No updates to make.');
        process.exit(0);
    }
    
    // Save updated stamps.json
    console.log(`\n💾 Saving stamps.json with ${updateCount} updated IDs...`);
    fs.writeFileSync(stampsPath, JSON.stringify(stamps, null, 2), 'utf8');
    
    console.log('\n============================================');
    console.log(`✅ Updated ${updateCount} stamp IDs`);
    if (skippedCount > 0) {
        console.log(`⏭️  Skipped ${skippedCount} low-confidence matches`);
        console.log(`\n   Review stamp_matches.json and manually fix if needed`);
    }
    console.log('============================================\n');
    
    console.log('Next steps:');
    console.log('1. Run: node update_stamp_urls_from_storage.js');
    console.log('2. Run: node upload_stamps_to_firestore.js');
    console.log('');
    
    process.exit(0);
}

updateStampIds().catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
});

