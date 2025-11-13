#!/usr/bin/env node

/**
 * Find User by Username Script
 * Searches Firestore for a user by their username
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  storageBucket: 'stampbook-app.firebasestorage.app'
});

const db = admin.firestore();

async function findUserByUsername(username) {
  try {
    console.log(`\n🔍 Searching for user: @${username}...\n`);
    
    const usersSnapshot = await db.collection('users').get();
    
    if (usersSnapshot.empty) {
      console.log('❌ No users found in database');
      return;
    }
    
    let found = false;
    usersSnapshot.forEach(doc => {
      const userData = doc.data();
      if (userData.username === username) {
        found = true;
        console.log('✅ User Found!');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`User ID:       ${doc.id}`);
        console.log(`Username:      @${userData.username}`);
        console.log(`Display Name:  ${userData.displayName}`);
        console.log(`Bio:           ${userData.bio || '(empty)'}`);
        console.log(`Total Stamps:  ${userData.totalStamps}`);
        console.log(`Followers:     ${userData.followerCount}`);
        console.log(`Following:     ${userData.followingCount}`);
        console.log(`Created:       ${userData.createdAt?.toDate?.() || 'N/A'}`);
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      }
    });
    
    if (!found) {
      console.log(`❌ User @${username} not found`);
      console.log('\nAvailable users:');
      usersSnapshot.forEach(doc => {
        const userData = doc.data();
        console.log(`  - @${userData.username} (${userData.displayName})`);
      });
      console.log();
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

const username = process.argv[2];

if (!username) {
  console.log('\n❌ Error: No username provided');
  console.log('\nUsage: node find_user_by_username.js <username>');
  console.log('Example: node find_user_by_username.js watagumostudio\n');
  process.exit(1);
}

// Remove @ if user included it
const cleanUsername = username.replace('@', '');

findUserByUsername(cleanUsername)
  .then(() => {
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Unexpected error:', error.message);
    console.error(error);
    process.exit(1);
  });

