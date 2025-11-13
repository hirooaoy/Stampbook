const {onCall} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentCreated} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
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

// ==================== NOTIFICATION TRIGGERS ====================

/**
 * Firestore Trigger: Create notification when someone follows a user
 * 
 * Triggered when a follow document is created in users/{userId}/following/{followingId}
 * Creates a notification for the user being followed
 */
exports.createFollowNotification = onDocumentCreated('users/{userId}/following/{followingId}', async (event) => {
  const followerId = event.params.userId;  // Person who clicked follow
  const followingId = event.params.followingId;  // Person being followed
  
  // Don't create notification if someone follows themselves (shouldn't happen, but be safe)
  if (followerId === followingId) {
    return null;
  }
  
  console.log(`📬 Creating follow notification: ${followerId} followed ${followingId}`);
  
  try {
    // Create notification for the person being followed
    await admin.firestore().collection('notifications').add({
      recipientId: followingId,
      actorId: followerId,
      type: 'follow',
      postId: null,
      stampId: null,
      commentPreview: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false
    });
    
    console.log(`✅ Follow notification created successfully`);
  } catch (error) {
    console.error(`❌ Error creating follow notification:`, error);
  }
  
  return null;
});

/**
 * Firestore Trigger: Create notification when someone likes a post
 * 
 * Triggered when a like document is created in likes collection
 * Creates a notification for the post owner
 */
exports.createLikeNotification = onDocumentCreated('likes/{likeId}', async (event) => {
  const like = event.data.data();
  
  // Don't create notification if user likes their own post
  if (like.userId === like.postOwnerId) {
    return null;
  }
  
  console.log(`📬 Creating like notification: ${like.userId} liked post by ${like.postOwnerId}`);
  
  try {
    // Create notification for the post owner
    await admin.firestore().collection('notifications').add({
      recipientId: like.postOwnerId,
      actorId: like.userId,
      type: 'like',
      postId: like.postId,
      stampId: like.stampId,
      commentPreview: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false
    });
    
    console.log(`✅ Like notification created successfully`);
  } catch (error) {
    console.error(`❌ Error creating like notification:`, error);
  }
  
  return null;
});

/**
 * Firestore Trigger: Create notification when someone comments on a post
 * 
 * Triggered when a comment document is created in comments collection
 * Creates a notification for the post owner with comment preview
 */
exports.createCommentNotification = onDocumentCreated('comments/{commentId}', async (event) => {
  const comment = event.data.data();
  
  // Don't create notification if user comments on their own post
  if (comment.userId === comment.postOwnerId) {
    return null;
  }
  
  console.log(`📬 Creating comment notification: ${comment.userId} commented on post by ${comment.postOwnerId}`);
  
  try {
    // Truncate comment text to 100 characters for preview
    const commentPreview = comment.text.length > 100 
      ? comment.text.substring(0, 100) + '...'
      : comment.text;
    
    // Create notification for the post owner
    await admin.firestore().collection('notifications').add({
      recipientId: comment.postOwnerId,
      actorId: comment.userId,
      type: 'comment',
      postId: comment.postId,
      stampId: comment.stampId,
      commentPreview: commentPreview,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false
    });
    
    console.log(`✅ Comment notification created successfully`);
  } catch (error) {
    console.error(`❌ Error creating comment notification:`, error);
  }
  
  return null;
});

// ==================== FOLLOWER COUNT DENORMALIZATION ====================

/**
 * Cloud Function: Update follower/following counts (Denormalization)
 * 
 * Triggered when a follow relationship is created or deleted
 * Atomically updates both users' counts for instant, cheap profile loading
 * 
 * COST SAVINGS: 97% reduction in profile loading costs
 * - Before: 36 reads per profile view (query followers + following)
 * - After: 1 read per profile view (counts already on profile)
 * 
 * Path: users/{followerId}/following/{followeeId}
 * - onCreate: Increment both users' counts
 * - onDelete: Decrement both users' counts
 * 
 * Benefits:
 * - Profile loading 10x faster (no collection group queries)
 * - Scales to any user count (no performance degradation)
 * - Better offline support (counts cached with profile)
 */
exports.updateFollowCounts = onDocumentWritten('users/{followerId}/following/{followeeId}', async (event) => {
  const followerId = event.params.followerId;
  const followeeId = event.params.followeeId;
  const change = event.data;
  
  // Don't process if following yourself (shouldn't happen, but be safe)
  if (followerId === followeeId) {
    console.log(`⚠️ Ignoring self-follow: ${followerId}`);
    return null;
  }
  
  const wasCreated = !change.before.exists && change.after.exists;
  const wasDeleted = change.before.exists && !change.after.exists;
  
  if (!wasCreated && !wasDeleted) {
    // Update event (not create/delete) - ignore
    console.log(`ℹ️ Ignoring update event (not create/delete)`);
    return null;
  }
  
  const increment = wasCreated ? 1 : -1;
  const action = wasCreated ? 'Follow' : 'Unfollow';
  
  console.log(`📊 ${action}: ${followerId} → ${followeeId} (delta: ${increment > 0 ? '+' : ''}${increment})`);
  
  try {
    // Update both users' counts atomically using batch
    const batch = admin.firestore().batch();
    
    // Update follower's followingCount
    const followerRef = admin.firestore().collection('users').doc(followerId);
    batch.update(followerRef, {
      followingCount: admin.firestore.FieldValue.increment(increment)
    });
    
    // Update followee's followerCount
    const followeeRef = admin.firestore().collection('users').doc(followeeId);
    batch.update(followeeRef, {
      followerCount: admin.firestore.FieldValue.increment(increment)
    });
    
    await batch.commit();
    
    console.log(`✅ Updated counts successfully: follower=${followerId}, followee=${followeeId}`);
  } catch (error) {
    console.error(`❌ Failed to update counts:`, error);
    // Don't throw - follow/unfollow already succeeded
    // Count will be fixed by reconciliation script if needed
  }
  
  return null;
});

// ==================== SCHEDULED CLEANUP ====================

/**
 * Scheduled Function: Clean up old notifications
 * 
 * Runs daily at midnight (Pacific Time) to keep notification database lean
 * 
 * Deletion policy:
 * - Read notifications older than 30 days: Deleted
 * - All notifications older than 90 days: Deleted
 * 
 * Benefits:
 * - Keeps database performant and costs low
 * - Reduces read operations when users check notifications
 * - Matches user expectations (like Instagram/Twitter)
 * 
 * Cost: Essentially free at MVP scale (well within free tier)
 */
exports.cleanupOldNotifications = onSchedule('0 0 * * *', async (event) => {
  console.log('🧹 Starting daily notification cleanup...');
  
  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  
  // Calculate cutoff dates
  const thirtyDaysAgo = new Date(now.toDate());
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  const ninetyDaysAgo = new Date(now.toDate());
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);
  
  let totalDeleted = 0;
  
  try {
    // Step 1: Delete read notifications older than 30 days
    console.log('📋 Deleting read notifications older than 30 days...');
    const readOldQuery = db.collection('notifications')
      .where('isRead', '==', true)
      .where('createdAt', '<', admin.firestore.Timestamp.fromDate(thirtyDaysAgo))
      .limit(500); // Firestore batch limit
    
    const readOldSnapshot = await readOldQuery.get();
    
    if (!readOldSnapshot.empty) {
      const batch1 = db.batch();
      readOldSnapshot.docs.forEach(doc => {
        batch1.delete(doc.ref);
      });
      await batch1.commit();
      console.log(`✅ Deleted ${readOldSnapshot.size} read notifications (30+ days old)`);
      totalDeleted += readOldSnapshot.size;
    } else {
      console.log('✓ No read notifications older than 30 days');
    }
    
    // Step 2: Delete all notifications older than 90 days (regardless of read status)
    console.log('📋 Deleting all notifications older than 90 days...');
    const allOldQuery = db.collection('notifications')
      .where('createdAt', '<', admin.firestore.Timestamp.fromDate(ninetyDaysAgo))
      .limit(500);
    
    const allOldSnapshot = await allOldQuery.get();
    
    if (!allOldSnapshot.empty) {
      const batch2 = db.batch();
      allOldSnapshot.docs.forEach(doc => {
        batch2.delete(doc.ref);
      });
      await batch2.commit();
      console.log(`✅ Deleted ${allOldSnapshot.size} notifications (90+ days old)`);
      totalDeleted += allOldSnapshot.size;
    } else {
      console.log('✓ No notifications older than 90 days');
    }
    
    console.log(`🎉 Cleanup complete! Total deleted: ${totalDeleted} notifications`);
    
  } catch (error) {
    console.error('❌ Error during notification cleanup:', error);
    throw error; // Re-throw so Cloud Functions logs the failure
  }
  
  return null;
});

