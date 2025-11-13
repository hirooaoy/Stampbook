#!/usr/bin/env node

/**
 * Smart matcher for stamp IDs to Firebase Storage filenames
 * Uses fuzzy matching to find the best filename for each stamp
 * 
 * Usage: node match_stamp_images.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: 'stampbook-app.firebasestorage.app'
});

const bucket = admin.storage().bucket();

// Calculate similarity between two strings (Levenshtein-based)
function similarity(s1, s2) {
    const longer = s1.length > s2.length ? s1 : s2;
    const shorter = s1.length > s2.length ? s2 : s1;
    
    if (longer.length === 0) return 1.0;
    
    const editDistance = levenshteinDistance(longer, shorter);
    return (longer.length - editDistance) / longer.length;
}

function levenshteinDistance(s1, s2) {
    const costs = [];
    for (let i = 0; i <= s1.length; i++) {
        let lastValue = i;
        for (let j = 0; j <= s2.length; j++) {
            if (i === 0) {
                costs[j] = j;
            } else if (j > 0) {
                let newValue = costs[j - 1];
                if (s1.charAt(i - 1) !== s2.charAt(j - 1)) {
                    newValue = Math.min(Math.min(newValue, lastValue), costs[j]) + 1;
                }
                costs[j - 1] = lastValue;
                lastValue = newValue;
            }
        }
        if (i > 0) costs[s2.length] = lastValue;
    }
    return costs[s2.length];
}

async function matchStampImages() {
    console.log('🔍 Analyzing stamp IDs and Firebase Storage files...\n');
    
    // Get all files from Firebase Storage
    const [files] = await bucket.getFiles({ prefix: 'stamps/' });
    const storageFilenames = files.map(file => {
        const basename = path.basename(file.name);
        return basename.replace(/\.(jpg|jpeg|png)$/i, '');
    });
    
    console.log(`✅ Found ${storageFilenames.length} images in Firebase Storage`);
    
    // Read stamps.json
    const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');
    const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));
    
    console.log(`✅ Found ${stamps.length} stamps in stamps.json\n`);
    
    // Find stamps without matching images
    const unmatchedStamps = [];
    const unmatchedFiles = new Set(storageFilenames);
    
    for (const stamp of stamps) {
        if (unmatchedFiles.has(stamp.id)) {
            // Perfect match - remove from unmatched
            unmatchedFiles.delete(stamp.id);
        } else {
            // No exact match
            unmatchedStamps.push(stamp);
        }
    }
    
    console.log(`🔍 Found ${unmatchedStamps.length} stamps without images`);
    console.log(`🔍 Found ${unmatchedFiles.size} unused image files\n`);
    
    if (unmatchedStamps.length === 0) {
        console.log('✅ All stamps have matching images!');
        process.exit(0);
    }
    
    // Smart matching
    console.log('🤖 Using AI fuzzy matching...\n');
    const matches = [];
    
    for (const stamp of unmatchedStamps) {
        let bestMatch = null;
        let bestScore = 0;
        
        for (const filename of unmatchedFiles) {
            const score = similarity(stamp.id, filename);
            
            if (score > bestScore) {
                bestScore = score;
                bestMatch = filename;
            }
        }
        
        matches.push({
            stampId: stamp.id,
            stampName: stamp.name,
            matchedFile: bestMatch,
            confidence: (bestScore * 100).toFixed(1)
        });
    }
    
    // Sort by confidence (highest first)
    matches.sort((a, b) => parseFloat(b.confidence) - parseFloat(a.confidence));
    
    // Display results
    console.log('📊 SUGGESTED MATCHES (sorted by confidence):\n');
    console.log('┌─────────────────────────────────────────────────────────────────────┐');
    
    for (const match of matches) {
        const confidence = parseFloat(match.confidence);
        const emoji = confidence >= 90 ? '✅' : confidence >= 70 ? '⚠️' : '❌';
        
        console.log(`${emoji} ${match.confidence}% confidence`);
        console.log(`   Stamp: "${match.stampName}"`);
        console.log(`   ID:    ${match.stampId}`);
        console.log(`   File:  ${match.matchedFile}`);
        console.log('');
    }
    
    console.log('┌─────────────────────────────────────────────────────────────────────┐');
    console.log('│ NEXT STEPS:                                                         │');
    console.log('│ Review the matches above. If they look good, you have two options:  │');
    console.log('│                                                                     │');
    console.log('│ OPTION 1: Rename Firebase Storage files to match stamp IDs         │');
    console.log('│   Run: node rename_storage_files.js                                │');
    console.log('│                                                                     │');
    console.log('│ OPTION 2: Update stamp IDs in stamps.json to match filenames       │');
    console.log('│   Run: node update_stamp_ids.js                                    │');
    console.log('└─────────────────────────────────────────────────────────────────────┘');
    
    // Save matches to JSON for other scripts to use
    fs.writeFileSync(
        path.join(__dirname, 'stamp_matches.json'),
        JSON.stringify(matches, null, 2)
    );
    console.log('\n💾 Matches saved to stamp_matches.json');
    
    process.exit(0);
}

matchStampImages().catch(error => {
    console.error('❌ Error:', error.message);
    process.exit(1);
});

