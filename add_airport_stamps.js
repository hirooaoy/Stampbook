const fs = require('fs');

// Simple geohash encoder (from fix_grand_canyon_stamps.js)
function encodeGeohash(latitude, longitude, precision = 8) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let latRange = [-90.0, 90.0];
  let lonRange = [-180.0, 180.0];
  let geohash = '';
  let isEven = true;
  let bit = 0;
  let ch = 0;

  while (geohash.length < precision) {
    if (isEven) {
      const mid = (lonRange[0] + lonRange[1]) / 2;
      if (longitude > mid) {
        ch |= (1 << (4 - bit));
        lonRange[0] = mid;
      } else {
        lonRange[1] = mid;
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (latitude > mid) {
        ch |= (1 << (4 - bit));
        latRange[0] = mid;
      } else {
        latRange[1] = mid;
      }
    }
    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      geohash += base32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return geohash;
}

const newStamps = [
  {
    id: 'us-ga-atlanta-hartsfield-jackson-airport',
    name: 'Hartsfield-Jackson Atlanta International Airport',
    latitude: 33.64012296901368,
    longitude: -84.42803394918447,
    address: 'Hartsfield-Jackson Atlanta International Airport\nAtlanta, GA USA 30320',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'World\'s busiest airport since 1998, handling over 100 million passengers annually. Named after two former Atlanta mayors who championed aviation.',
    thingsToDoFromEditors: [
      'Try Paschal\'s fried chicken in Concourse A',
      'Grab a Coca-Cola Freestyle at the Coca-Cola store'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-ca-losangeles-lax-airport',
    name: 'Los Angeles International Airport',
    latitude: 33.942647021985145,
    longitude: -118.41070059628139,
    address: 'Los Angeles International Airport\nLos Angeles, CA USA 90045',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Iconic Theme Building designed in 1961 with its futuristic "Jetsons" architecture has become LA\'s aviation symbol and houses a restaurant on top.',
    thingsToDoFromEditors: [
      'Visit the Theme Building\'s observation deck',
      'Try In-N-Out Burger at Terminal 1'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-il-chicago-ohare-airport',
    name: 'Chicago O\'Hare International Airport',
    latitude: 41.98076970279307,
    longitude: -87.90976475579723,
    address: 'Chicago O\'Hare International Airport\nChicago, IL USA 60666',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Named after WWII Medal of Honor recipient Edward "Butch" O\'Hare. The airport\'s iconic neon tunnel connects terminals with changing light displays.',
    thingsToDoFromEditors: [
      'Walk through the psychedelic neon light tunnel',
      'Try Garrett Popcorn or deep-dish pizza at Giordano\'s'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-co-denver-international-airport',
    name: 'Denver International Airport',
    latitude: 39.863767821319726,
    longitude: -104.67813734436864,
    address: 'Denver International Airport\nDenver, CO USA 80249',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Opened in 1995, its white tensile roof mimics the Rocky Mountains. At 53 square miles, it\'s the largest US airport by land area and second-largest globally.',
    thingsToDoFromEditors: [
      'See the infamous Blue Mustang "Blucifer" sculpture',
      'Try Root Down\'s farm-to-table food in Terminal C'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-ny-newyork-jfk-airport',
    name: 'John F. Kennedy International Airport',
    latitude: 40.65004236681849,
    longitude: -73.78843584023926,
    address: 'John F. Kennedy International Airport\nQueens, NY USA 11430',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Named after President Kennedy in 1963, just a month after his assassination. The TWA Flight Center designed by Eero Saarinen is now a hotel and landmark.',
    thingsToDoFromEditors: [
      'Visit the iconic TWA Hotel and Flight Center',
      'Try Shake Shack in Terminal 4'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-nv-lasvegas-harry-reid-airport',
    name: 'Harry Reid International Airport',
    latitude: 36.08477666948465,
    longitude: -115.15103809531695,
    address: 'Harry Reid International Airport\nLas Vegas, NV USA 89119',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Renamed in 2021 after Senator Harry Reid. Famous for slot machines throughout terminals, making it the only major US airport where you can gamble.',
    thingsToDoFromEditors: [
      'Try your luck at the airport slot machines',
      'Grab a burger at Gordon Ramsay BurGR'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-fl-orlando-international-airport',
    name: 'Orlando International Airport',
    latitude: 28.427033721341747,
    longitude: -81.31105845311968,
    address: 'Orlando International Airport\nOrlando, FL USA 32827',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Code "MCO" comes from its former name McCoy Air Force Base. The massive Hyatt Regency inside is the largest airport hotel in America with 445 rooms.',
    thingsToDoFromEditors: [
      'Ride the Hyatt\'s glass elevators through the atrium',
      'Try Cask & Larder\'s Southern food in Terminal A'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  },
  {
    id: 'us-wa-seattle-seatac-airport',
    name: 'Seattle-Tacoma International Airport',
    latitude: 47.45242828930967,
    longitude: -122.31010790239465,
    address: 'Seattle-Tacoma International Airport\nSeaTac, WA USA 98158',
    imageUrl: 'PLACEHOLDER',
    collectionIds: ['airports-of-the-world'],
    about: 'Home to the first Starbucks airport location and a Sub Pop Records store. The airport\'s central marketplace features fresh Pike Place Market vendors.',
    thingsToDoFromEditors: [
      'Visit the Sub Pop Records store (birthplace of grunge)',
      'Try Ivar\'s clam chowder or Beecher\'s mac and cheese'
    ],
    collectionRadius: 'xlarge',
    aspectRatio: 1
  }
];

// Add geohashes
newStamps.forEach(stamp => {
  stamp.geohash = encodeGeohash(stamp.latitude, stamp.longitude, 8);
});

// Read existing stamps
const stampsData = JSON.parse(fs.readFileSync('Stampbook/Data/stamps.json', 'utf8'));

// Add new stamps
stampsData.push(...newStamps);

// Sort alphabetically by id
stampsData.sort((a, b) => a.id.localeCompare(b.id));

// Save
fs.writeFileSync('Stampbook/Data/stamps.json', JSON.stringify(stampsData, null, 2));

console.log('✅ Added 8 new airport stamps to stamps.json');
console.log('📊 Total stamps:', stampsData.length);
console.log('\n📍 New stamps:');
newStamps.forEach(s => console.log(`  - ${s.id} (geohash: ${s.geohash})`));

