#!/usr/bin/env node

/**
 * Set empty imageUrl for stamps without images
 * This makes them show the placeholder "empty" image
 */

const fs = require('fs');
const path = require('path');

const stampsPath = path.join(__dirname, 'Stampbook', 'Data', 'stamps.json');

console.log('📚 Reading stamps.json...');
const stamps = JSON.parse(fs.readFileSync(stampsPath, 'utf8'));

// Stamps that have images
const stampsWithImages = [
    'us-ca-sf-baker-beach',
    'us-ca-sf-dolores-park',
    'us-ca-sf-equator-coffee',
    'us-ca-sf-ferry-building',
    'us-ca-sf-four-barrel',
    'us-ca-sf-pier-39'
];

let updatedCount = 0;

for (const stamp of stamps) {
    if (!stampsWithImages.includes(stamp.id)) {
        // Set imageUrl to empty string for placeholder
        stamp.imageUrl = '';
        updatedCount++;
    }
}

console.log(`✅ Set ${updatedCount} stamps to use placeholder image`);
console.log('');

// Write back to stamps.json
fs.writeFileSync(stampsPath, JSON.stringify(stamps, null, 2), 'utf8');

console.log('💾 Saved stamps.json');
console.log('');
console.log('Stamps with images (6):');
stampsWithImages.forEach(id => console.log(`  ✓ ${id}`));
console.log('');
console.log(`Stamps with placeholders (${updatedCount}): Will show "empty" image`);

