const fs = require('fs');
const stamps = JSON.parse(fs.readFileSync('./Stampbook/Data/stamps.json', 'utf8'));

// Manual rewrites for items still over 80 chars
const rewrites = {
  'us-ca-sequoia-national-park-general-sherman-tree': [
    'Walk Congress Trail loop to see General Sherman and giant sequoias',
    'Hike Big Trees Trail through Giant Forest grove'
  ],
  'us-ca-sequoia-national-park-tunnel-log': [
    'Drive through tunnel carved into fallen sequoia',
    'Hike to Moro Rock nearby for Sierra views'
  ],
  'us-ca-sf-andytown-coffee-roasters': [
    'Order the Snowy Plover (espresso + brown sugar ice cream)',
    'Take your drink to Ocean Beach'
  ],
  'us-ca-sf-saint-frank-coffee': [
    'Ask baristas about single-origin espresso',
    'Try their signature pour-over'
  ],
  'us-ca-sf-san-francisco-airport': [
    'Explore aviation museum in Terminal 3',
    "Try Tony's Pizza (Terminal 1) or Tartine (Terminal A)"
  ],
  'us-ca-sf-the-coffee-movement': [
    'Try their signature coffee drinks',
    'Check hours before visiting - this location keeps short hours'
  ],
  'us-hi-the-big-island-mauna-kea': [
    'Drive to summit with 4WD for spectacular sunset views',
    'Join free nightly stargazing at Visitor Station'
  ],
  'us-ny-nyc-bow-bridge': [
    'Visit at sunrise for soft light photos',
    'Walk to bridge center for view north'
  ],
  'us-ny-nyc-conservatory-garden': [
    'Visit in spring for tulips and summer for roses',
    'Enter through Vanderbilt Gate at 105th St'
  ],
  'us-ny-nyc-lincoln-center-for-the-performing-arts': [
    'Visit Atrium for free performances and WiFi',
    'Come at night when buildings are lit up'
  ],
  'us-ny-nyc-little-island': [
    'Walk pathways through 350+ plant species',
    'Relax on grassy hills with Hudson views'
  ],
  'us-ny-nyc-statue-of-liberty': [
    'Take ferry from Battery Park and climb 354 steps to crown',
    'Book crown tickets months in advance'
  ],
  'us-ny-nyc-the-ramble': [
    'Bring binoculars for birdwatching',
    'Get lost on winding paths away from city'
  ],
  'us-ny-williamsburg-domino-park': [
    'Walk elevated walkway for Manhattan skyline views',
    'Play at vintage carnival games'
  ],
  'us-tx-big-bend-national-park-balanced-rock': [
    'Hike 2.2-mile trail with short rock scramble at end'
  ],
  'us-tx-big-bend-national-park-chisos-basin': [
    'Drive winding Basin Road to lodge and trailhead',
    'Use as basecamp for Window, Lost Mine, Emory Peak hikes'
  ],
  'us-tx-big-bend-national-park-hot-springs': [
    'Walk short path to bathhouse ruins and soak in spring pool',
    'Explore ruins and learn resort history'
  ],
  'us-tx-big-bend-national-park-lost-mine-trail': [
    'Hike 4.8-mile trail from Basin Road to panoramic overlooks',
    'Start early morning to avoid heat',
    'Bring layers for windy, cool overlook'
  ],
  'us-tx-big-bend-national-park-the-window': [
    'Hike 5.6-mile Window Trail from Chisos Basin to pour-off',
    'Arrive 1-2 hours before sunset for golden light'
  ],
  'us-ut-zion-national-park-angels-landing': [
    'Hike to Scout Lookout without permit (Shuttle drops at Grotto)',
    'Book permit months ahead for final chain section'
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
console.log(`\n✨ Updated ${updated} stamps with manual rewrites`);

// Final verification
const after = JSON.parse(fs.readFileSync('./Stampbook/Data/stamps.json', 'utf8'));
let over80 = 0;
let perfect = 0;
let good = 0;

after.forEach(stamp => {
  if (!stamp.thingsToDoFromEditors) return;
  stamp.thingsToDoFromEditors.forEach(thing => {
    if (thing.length > 80) over80++;
    else if (thing.length >= 25 && thing.length <= 40) perfect++;
    else if (thing.length <= 80) good++;
  });
});

console.log(`\n📊 FINAL STATS:`);
console.log(`✅ Perfect (25-40 chars): ${perfect}`);
console.log(`✅ Good (41-80 chars, logistics): ${good}`);
console.log(`❌ Still over 80 chars: ${over80}`);

