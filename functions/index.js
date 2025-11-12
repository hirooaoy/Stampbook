const {onCall} = require('firebase-functions/v2/https');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const Filter = require('bad-words');

admin.initializeApp();

// Initialize profanity filter with custom settings
const filter = new Filter();

// Add custom reserved words (admin terms, brand names)
const reservedWords = [
  'admin', 'administrator', 'support', 'help', 'official', 'verified',
  'stampbook', 'stamp_book', 'stamp', 'moderator', 'mod', 'staff',
  'system', 'root', 'superuser'
];

// Add reserved words to filter
filter.addWords(...reservedWords);

/**
 * Cloud Function: Validate username and display name for profanity/reserved words
 * 
 * Called from iOS app before profile creation/update
 * 
 * Request: { username: string, displayName: string }
 * Response: { 
 *   valid: boolean, 
 *   errors: { username?: string, displayName?: string } 
 * }
 * 
 * Benefits:
 * - Server-side = can't be bypassed by reading source code
 * - Centralized = easy to update word list without app updates
 * - Secure = runs with admin privileges
 */
exports.validateContent = onCall(async (request) => {
  const data = request.data;
  const { username, displayName, type = 'profile' } = data;
  
  const errors = {};
  
  // Validate username (if provided)
  if (username) {
    const cleanUsername = username.toLowerCase().trim();
    
    // Check against profanity filter
    if (filter.isProfane(cleanUsername)) {
      errors.username = 'Username contains inappropriate content';
    }
    
    // Additional check: substring matching for reserved words
    // (bad-words library might miss some variations)
    for (const word of reservedWords) {
      if (cleanUsername.includes(word)) {
        errors.username = 'Username contains reserved words';
        break;
      }
    }
    
    // Check length (3-20 characters)
    if (cleanUsername.length < 3) {
      errors.username = 'Username must be at least 3 characters';
    } else if (cleanUsername.length > 20) {
      errors.username = 'Username must be 20 characters or less';
    }
    
    // Check format (alphanumeric + underscore only)
    if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
      errors.username = 'Username can only contain letters, numbers, and underscores';
    }
  }
  
  // Validate display name (if provided)
  if (displayName) {
    const cleanDisplayName = displayName.trim();
    
    // Check against profanity filter
    if (filter.isProfane(cleanDisplayName)) {
      errors.displayName = 'Display name contains inappropriate content';
    }
    
    // Check length (1-20 characters)
    if (cleanDisplayName.length === 0) {
      errors.displayName = 'Display name cannot be empty';
    } else if (cleanDisplayName.length > 20) {
      errors.displayName = 'Display name must be 20 characters or less';
    }
  }
  
  return {
    valid: Object.keys(errors).length === 0,
    errors: errors
  };
});

/**
 * Cloud Function: Check if username is available
 * 
 * Called before profile updates to ensure uniqueness
 * 
 * Request: { username: string, excludeUserId?: string }
 * Response: { available: boolean, reason?: string }
 */
exports.checkUsernameAvailability = onCall(async (request) => {
  const data = request.data;
  const { username, excludeUserId } = data;
  
  if (!username) {
    return { available: false, reason: 'Username is required' };
  }
  
  const cleanUsername = username.toLowerCase().trim();
  
  // Check format
  if (!/^[a-z0-9_]+$/.test(cleanUsername)) {
    return { available: false, reason: 'Invalid username format' };
  }
  
  // Check length
  if (cleanUsername.length < 3 || cleanUsername.length > 20) {
    return { available: false, reason: 'Username must be 3-20 characters' };
  }
  
  // Check profanity
  if (filter.isProfane(cleanUsername)) {
    return { available: false, reason: 'Username contains inappropriate content' };
  }
  
  // Check reserved words
  for (const word of reservedWords) {
    if (cleanUsername.includes(word)) {
      return { available: false, reason: 'Username contains reserved words' };
    }
  }
  
  // Check if already taken in Firestore
  const usersRef = admin.firestore().collection('users');
  const snapshot = await usersRef.where('username', '==', cleanUsername).get();
  
  if (snapshot.empty) {
    return { available: true };
  }
  
  // If only one result and it's the current user, username is available
  if (snapshot.size === 1 && excludeUserId) {
    const doc = snapshot.docs[0];
    if (doc.id === excludeUserId) {
      return { available: true };
    }
  }
  
  return { available: false, reason: 'Username is already taken' };
});

/**
 * Cloud Function: Moderate comment text
 * 
 * Called before posting comments to filter profanity
 * 
 * Request: { text: string }
 * Response: { clean: boolean, filtered?: string }
 */
exports.moderateComment = onCall(async (request) => {
  const data = request.data;
  const { text } = data;
  
  if (!text || text.trim().length === 0) {
    return { clean: false, error: 'Comment cannot be empty' };
  }
  
  const isProfane = filter.isProfane(text);
  
  if (isProfane) {
    // Option 1: Reject comment entirely
    return { clean: false, error: 'Comment contains inappropriate content' };
    
    // Option 2: Auto-filter profanity (uncomment if you prefer this approach)
    // const filtered = filter.clean(text);
    // return { clean: true, filtered: filtered, wasFiltered: true };
  }
  
  return { clean: true };
});

/**
 * Firestore Trigger: Auto-moderate profile updates
 * 
 * Runs whenever a user profile is created or updated
 * Checks for profanity and flags/removes if found
 * 
 * This is a safety net in case client-side validation is bypassed
 */
exports.moderateProfileOnWrite = onDocumentWritten('users/{userId}', async (event) => {
    const change = event.data;
    const context = event;
    // Skip if document was deleted
    if (!change.after.exists) {
      return null;
    }
    
    const newData = change.after.data();
    const oldData = change.before.exists ? change.before.data() : null;
    
    // Check if username or displayName changed
    const usernameChanged = !oldData || oldData.username !== newData.username;
    const displayNameChanged = !oldData || oldData.displayName !== newData.displayName;
    
    if (!usernameChanged && !displayNameChanged) {
      return null; // No changes to moderate
    }
    
    const issues = [];
    
    // Check username
    if (usernameChanged && newData.username) {
      if (filter.isProfane(newData.username.toLowerCase())) {
        issues.push('username');
      }
    }
    
    // Check display name
    if (displayNameChanged && newData.displayName) {
      if (filter.isProfane(newData.displayName)) {
        issues.push('displayName');
      }
    }
    
    // If issues found, flag for manual review
    if (issues.length > 0) {
      console.error(`⚠️ Profanity detected in user ${context.params.userId}:`, issues);
      
      // Create moderation alert document
      await admin.firestore().collection('moderation_alerts').add({
        userId: context.params.userId,
        type: 'profanity_in_profile',
        fields: issues,
        username: newData.username,
        displayName: newData.displayName,
        detectedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'pending'
      });
      
      // Optional: Auto-revert to safe values (uncomment if desired)
      /*
      const updates = {};
      if (issues.includes('username') && oldData?.username) {
        updates.username = oldData.username;
      }
      if (issues.includes('displayName') && oldData?.displayName) {
        updates.displayName = oldData.displayName;
      }
      
      if (Object.keys(updates).length > 0) {
        await change.after.ref.update(updates);
      }
      */
    }
    
    return null;
  });

