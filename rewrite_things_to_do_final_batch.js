const fs = require('fs');
const stamps = JSON.parse(fs.readFileSync('./Stampbook/Data/stamps.json', 'utf8'));

// Final batch of manual rewrites
const rewrites = {
  'us-wa-olympic-national-park-hoh-rain-forest': [
    'Walk Hall of Mosses Trail through moss-draped maples',
    'Hike Spruce Nature Trail loop'
  ],
  'us-wa-olympic-national-park-hurricane-ridge': [
    'Drive scenic Hurricane Ridge Road from Port Angeles to visitor center',
    'Hike Hurricane Hill Trail for mountain views'
  ],
  'us-wa-olympic-national-park-lake-crescent': [
    'Drive Highway 101 along lake for stunning mountain and water views',
    'Stop at Lake Crescent Lodge or pullouts for photos'
  ],
  'us-wa-olympic-national-park-marymere-falls': [
    'Hike 1.8-mile trail from Storm King Station through rainforest',
    'View 90-foot waterfall from bridge'
  ],
  'us-wa-olympic-national-park-ruby-beach': [
    'Walk down trail to explore tide pools and sea stacks at low tide',
    'Watch sunset over sea stacks'
  ],
  'us-wa-olympic-national-park-sol-duc-falls': [
    'Hike easy 1.6-mile trail from Sol Duc trailhead through forest',
    'Cross wooden bridge above falls for canyon view'
  ],
  'us-or-crater-lake-national-park-discovery-point': [
    'Hike 2.2-mile trail from Rim Village',
    'Read signs about Hillman 1853 discovery'
  ],
  'us-or-crater-lake-national-park-phantom-ship': [
    'View from Sun Notch for best ship-like formation perspective',
    'Visit in morning when shadows make rock appear to float'
  ],
  'us-or-crater-lake-national-park-watchman-overlook': [
    'Hike short trail to fire lookout',
    'Arrive hour before sunset for golden light on Wizard Island'
  ],
  'us-or-crater-lake-national-park-wizard-island': [
    'Take boat tour from Cleetwood Cove to island and hike summit',
    'Book boat tours in advance'
  ],
  'us-co-rocky-mountain-national-park-alberta-falls': [
    'Hike easy 1.7-mile trail from Glacier Gorge through pine forest',
    'Visit in spring for peak snowmelt flow'
  ],
  'us-co-rocky-mountain-national-park-dream-lake': [
    'Hike 2.2-mile trail from Bear Lake (425ft gain) to alpine lake',
    'Arrive early for parking'
  ],
  'us-co-rocky-mountain-national-park-longs-peak': [
    'Start challenging 15-mile Keyhole Route from trailhead at 3am',
    'Summit attempt requires early alpine start'
  ],
  'us-co-rocky-mountain-national-park-sprague-lake': [
    'Walk flat accessible trail with Continental Divide reflections',
    'Best photos at sunrise'
  ],
  'us-co-rocky-mountain-national-park-trail-ridge-road': [
    'Stop at Alpine Visitor Center at 11,796ft for exhibits',
    'Drive 48-mile scenic road with views above treeline'
  ],
  'us-ut-zion-national-park-the-narrows': [
    'Hike upstream from Temple of Sinawava',
    'Check daily flow rate - park closes route when water too high'
  ],
  'us-wy-yellowstone-national-park-old-faithful-geyser': [
    'Check eruption prediction times at visitor center before walking',
    'Arrive early for front row viewing'
  ]
};

// Apply rewrites
let updated = 0;
stamps.forEach(stamp => {
  if (rewrites[stamp.id]) {
    stamp.thingsToDoFromEditors = rewrites[stamp.id];
    updated++;
    console.log(`✅ Updated: ${stamp.name}`);
    stamp.thingsToDoFromEditors.forEach((thing, i) => {
      console.log(`   ${i+1}. [${thing.length}] ${thing}`);
    });
    console.log('');
  }
});

// Save
fs.writeFileSync('./Stampbook/Data/stamps.json', JSON.stringify(stamps, null, 2));
console.log(`\n✨ Updated ${updated} stamps - FINAL BATCH`);

// Final verification
const after = JSON.parse(fs.readFileSync('./Stampbook/Data/stamps.json', 'utf8'));
let over80 = 0;
let perfect = 0;
let good = 0;
let under25 = 0;

after.forEach(stamp => {
  if (!stamp.thingsToDoFromEditors) return;
  stamp.thingsToDoFromEditors.forEach(thing => {
    if (thing.length > 80) over80++;
    else if (thing.length >= 25 && thing.length <= 40) perfect++;
    else if (thing.length > 40 && thing.length <= 80) good++;
    else if (thing.length < 25) under25++;
  });
});

console.log(`\n🎉 ALL REWRITES COMPLETE!\n`);
console.log(`📊 FINAL STATISTICS:`);
console.log(`✅ Perfect range (25-40 chars): ${perfect}`);
console.log(`✅ Good for logistics (41-80 chars): ${good}`);
console.log(`✅ Short actions (under 25): ${under25}`);
console.log(`❌ Still over 80 chars: ${over80}`);
console.log(`\n${over80 === 0 ? '🎊 SUCCESS - All items are within guidelines!' : '⚠️  Some items still need attention'}`);

