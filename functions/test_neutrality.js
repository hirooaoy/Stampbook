#!/usr/bin/env node

/**
 * Content Moderation Neutrality Test
 * 
 * Tests the bad-words library to ensure it doesn't block:
 * - Religious terms
 * - Political terms
 * - Identity terms
 * - Geographic locations
 * 
 * Run this BEFORE deploying to ensure political neutrality
 */

const Filter = require('bad-words');

// Colors for terminal output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m'
};

const filter = new Filter();

// Add your reserved words (matching functions/index.js)
const reservedWords = [
  'admin', 'administrator', 'support', 'help', 'official', 'verified',
  'stampbook', 'stamp_book', 'stamp', 'moderator', 'mod', 'staff',
  'system', 'root', 'superuser'
];

// Test categories
const testCategories = {
  'Religious Terms': [
    'jew', 'jewish', 'judaism',
    'muslim', 'islam', 'islamic',
    'christian', 'christianity', 'christ',
    'hindu', 'hinduism',
    'buddhist', 'buddhism',
    'sikh', 'sikhism',
    'atheist', 'agnostic'
  ],
  
  'Political/Geographic Terms': [
    'palestine', 'palestinian',
    'israel', 'israeli',
    'ukraine', 'ukrainian',
    'russia', 'russian',
    'china', 'chinese',
    'taiwan', 'taiwanese',
    'tibet', 'tibetan',
    'kashmir',
    'middleeast', 'middle_east'
  ],
  
  'Identity Terms': [
    'gay', 'lesbian', 'bisexual', 'transgender', 'trans', 'queer', 'lgbtq',
    'black', 'white', 'asian', 'latino', 'latina', 'hispanic',
    'indigenous', 'native',
    'immigrant', 'refugee'
  ],
  
  'Political Ideologies': [
    'democrat', 'republican', 'liberal', 'conservative',
    'leftist', 'rightist', 'centrist',
    'socialist', 'capitalist', 'communist',
    'feminist', 'activism', 'activist'
  ],
  
  'Usernames with These Terms': [
    'jewish_traveler', 'muslim_explorer', 'gay_backpacker',
    'palestine_lover', 'israel_fan', 'proud_asian',
    'black_nomad', 'latino_adventurer'
  ],
  
  'Reserved Words (Should Block)': reservedWords,
  
  'Actual Profanity (Should Block)': [
    'fuck', 'shit', 'bitch', 'ass', 'damn'
  ]
};

console.log('\n' + colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset);
console.log(colors.blue + '🧪 CONTENT MODERATION NEUTRALITY TEST' + colors.reset);
console.log(colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset + '\n');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;
const failures = [];

// Helper to check if word should be blocked
function shouldBeBlocked(word, category) {
  return category === 'Reserved Words (Should Block)' || 
         category === 'Actual Profanity (Should Block)';
}

// Helper to check reserved words
function containsReservedWord(text) {
  const lowercased = text.toLowerCase();
  for (const word of reservedWords) {
    if (lowercased.includes(word)) {
      return true;
    }
  }
  return false;
}

// Run tests
for (const [category, words] of Object.entries(testCategories)) {
  console.log(colors.magenta + `\n📋 ${category}` + colors.reset);
  console.log('─'.repeat(60));
  
  for (const word of words) {
    totalTests++;
    
    const isProfane = filter.isProfane(word);
    const hasReservedWord = containsReservedWord(word);
    const isBlocked = isProfane || hasReservedWord;
    const shouldBlock = shouldBeBlocked(word, category);
    
    let status, color, symbol;
    
    if (shouldBlock && isBlocked) {
      // Should block and does block - PASS
      status = 'BLOCKED (correct)';
      color = colors.green;
      symbol = '✅';
      passedTests++;
    } else if (!shouldBlock && !isBlocked) {
      // Should allow and does allow - PASS
      status = 'ALLOWED (correct)';
      color = colors.green;
      symbol = '✅';
      passedTests++;
    } else if (shouldBlock && !isBlocked) {
      // Should block but doesn't - FAIL
      status = 'ALLOWED (should block!)';
      color = colors.red;
      symbol = '❌';
      failedTests++;
      failures.push({ word, category, reason: 'Should be blocked but is allowed' });
    } else {
      // Shouldn't block but does - FAIL (FALSE POSITIVE)
      status = 'BLOCKED (FALSE POSITIVE!)';
      color = colors.red;
      symbol = '❌';
      failedTests++;
      failures.push({ word, category, reason: 'Should be allowed but is blocked' });
    }
    
    const reason = isProfane ? ' [profanity]' : hasReservedWord ? ' [reserved]' : '';
    console.log(`  ${symbol} ${color}${word.padEnd(25)}${status}${reason}${colors.reset}`);
  }
}

// Summary
console.log('\n' + colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset);
console.log(colors.blue + '📊 TEST SUMMARY' + colors.reset);
console.log(colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset + '\n');

console.log(`Total tests:   ${totalTests}`);
console.log(`${colors.green}✅ Passed:     ${passedTests}${colors.reset}`);
console.log(`${colors.red}❌ Failed:     ${failedTests}${colors.reset}`);
console.log(`Success rate:  ${((passedTests / totalTests) * 100).toFixed(1)}%\n`);

// Show failures in detail
if (failures.length > 0) {
  console.log(colors.red + '⚠️  FAILED TESTS (NEEDS ATTENTION):' + colors.reset + '\n');
  
  for (const failure of failures) {
    console.log(`${colors.red}❌ "${failure.word}"${colors.reset}`);
    console.log(`   Category: ${failure.category}`);
    console.log(`   Issue: ${failure.reason}`);
    console.log(`   ${colors.yellow}Action needed: ${
      failure.reason.includes('should block') 
        ? 'Add to reserved words list' 
        : 'Remove from filter using filter.removeWords()'
    }${colors.reset}\n`);
  }
} else {
  console.log(colors.green + '🎉 ALL TESTS PASSED!' + colors.reset);
  console.log(colors.green + '✅ Content moderation is politically neutral' + colors.reset);
  console.log(colors.green + '✅ Identity terms are allowed' + colors.reset);
  console.log(colors.green + '✅ Profanity is blocked' + colors.reset);
  console.log(colors.green + '✅ Reserved words are blocked' + colors.reset + '\n');
}

// Library info
console.log(colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset);
console.log(colors.blue + '📚 LIBRARY INFO' + colors.reset);
console.log(colors.blue + '═══════════════════════════════════════════════════════════' + colors.reset + '\n');
console.log(`bad-words library: ${filter.list.length} profane words blocked`);
console.log(`Reserved words: ${reservedWords.length} custom words blocked`);
console.log(`Total unique blocks: ~${filter.list.length + reservedWords.length}\n`);

// Exit with appropriate code
process.exit(failedTests > 0 ? 1 : 0);

