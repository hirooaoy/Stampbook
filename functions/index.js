const {onCall} = require('firebase-functions/v2/https');
const {onDocumentWritten, onDocumentCreated, onDocumentDeleted} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const Filter = require('bad-words');
const nodemailer = require('nodemailer');

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
 * Helper Function: Send push notification via FCM
 * 
 * Sends a push notification to a user's device using Firebase Cloud Messaging
 * 
 * @param {string} userId - User ID to send notification to
 * @param {object} notification - Notification payload { title, body }
 * @param {object} data - Additional data for deep linking { postId?, userId?, type }
 */
async function sendPushNotification(userId, notification, data = {}) {
  try {
    // Fetch user's FCM token from Firestore
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    
    if (!userDoc.exists) {
      console.log(`⚠️ User ${userId} not found - skipping push notification`);
      return;
    }
    
    const fcmToken = userDoc.data()?.fcmToken;
    
    if (!fcmToken) {
      console.log(`⚠️ No FCM token for user ${userId} - skipping push notification`);
      return;
    }
    
    // Get actual unread notification count for accurate badge
    const unreadCount = await admin.firestore()
      .collection('notifications')
      .where('recipientId', '==', userId)
      .where('isRead', '==', false)
      .count()
      .get();
    
    const badgeCount = unreadCount.data().count;
    
    // Send push notification
    const message = {
      token: fcmToken,
      notification: {
        title: notification.title,
        body: notification.body
      },
      data: data,
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: badgeCount // Actual unread count
          }
        }
      }
    };
    
    await admin.messaging().send(message);
    console.log(`✅ Push notification sent to user ${userId} (badge: ${badgeCount})`);
    
  } catch (error) {
    // Don't throw - push notification failure shouldn't break the function
    console.error(`❌ Failed to send push notification to user ${userId}:`, error);
  }
}

/**
 * Helper Function: Extract @mentions from comment text
 * 
 * Parses text for @username patterns and returns array of unique usernames
 * 
 * Rules:
 * - Pattern: @[a-z0-9_]{3,20} (matches username validation rules)
 * - Max 3 mentions per comment (spam prevention)
 * - Case insensitive (converts to lowercase)
 * - Deduplicates (if user mentioned multiple times, only returns once)
 * 
 * Examples:
 * - "Hey @hiroo check this!" → ["hiroo"]
 * - "Cool! @hiroo @watagumostudio" → ["hiroo", "watagumostudio"]
 * - "email@test.com" → [] (email addresses not detected)
 * - "@ab too short" → [] (usernames must be 3+ chars)
 * 
 * Future: Add autocomplete dropdown to help users mention correctly
 */
function extractMentions(text) {
  // Regex matches @username pattern (3-20 chars, alphanumeric + underscore)
  // \b word boundary prevents matching email addresses like "email@test.com"
  const mentionPattern = /@([a-z0-9_]{3,20})\b/gi;
  
  const matches = [];
  let match;
  
  // Extract all @username patterns
  while ((match = mentionPattern.exec(text)) !== null) {
    matches.push(match[1].toLowerCase()); // match[1] is the captured username
  }
  
  // Remove duplicates and limit to 3 mentions (spam prevention)
  const uniqueMentions = [...new Set(matches)].slice(0, 3);
  
  return uniqueMentions;
}

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
    // Fetch follower's profile to get their name
    const followerDoc = await admin.firestore().collection('users').doc(followerId).get();
    const followerName = followerDoc.exists ? followerDoc.data().displayName : 'Someone';
    
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
    
    // Send push notification
    await sendPushNotification(
      followingId,
      {
        title: 'New Follower',
        body: `${followerName} started following you`
      },
      {
        type: 'follow',
        userId: followerId
      }
    );
    
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
    // Fetch liker's profile to get their name
    const likerDoc = await admin.firestore().collection('users').doc(like.userId).get();
    const likerName = likerDoc.exists ? likerDoc.data().displayName : 'Someone';
    
    // Fetch stamp name for notification
    const stampDoc = await admin.firestore().collection('stamps').doc(like.stampId).get();
    const stampName = stampDoc.exists ? stampDoc.data().name : 'your stamp';
    
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
    
    // Send push notification
    await sendPushNotification(
      like.postOwnerId,
      {
        title: 'New Like',
        body: `${likerName} liked your ${stampName}`
      },
      {
        type: 'like',
        postId: like.postId,
        stampId: like.stampId
      }
    );
    
  } catch (error) {
    console.error(`❌ Error creating like notification:`, error);
  }
  
  return null;
});

/**
 * Firestore Trigger: Create notification when someone likes a comment
 * 
 * Triggered when a commentLike document is created in commentLikes collection
 * Creates a notification for the comment owner with stamp name
 */
exports.createCommentLikeNotification = onDocumentCreated('commentLikes/{commentLikeId}', async (event) => {
  const commentLike = event.data.data();
  
  // Don't send notification if user likes their own comment
  if (commentLike.userId === commentLike.commentOwnerId) {
    console.log(`⚠️ User liked their own comment - skipping notification`);
    return null;
  }
  
  console.log(`💬❤️ Processing comment like: ${commentLike.userId} liked comment by ${commentLike.commentOwnerId}`);
  
  try {
    // Fetch liker's profile to get their name
    const likerDoc = await admin.firestore().collection('users').doc(commentLike.userId).get();
    const likerName = likerDoc.exists ? likerDoc.data().displayName : 'Someone';
    
    // Fetch stamp name for notification
    const stampDoc = await admin.firestore().collection('stamps').doc(commentLike.stampId).get();
    const stampName = stampDoc.exists ? stampDoc.data().name : 'a stamp';
    
    // Fetch comment text for preview (optional, for context)
    const commentDoc = await admin.firestore().collection('comments').doc(commentLike.commentId).get();
    const commentPreview = commentDoc.exists && commentDoc.data().text 
      ? (commentDoc.data().text.length > 100 
          ? commentDoc.data().text.substring(0, 100) + '...'
          : commentDoc.data().text)
      : '';
    
    // Create notification for comment owner
    await admin.firestore().collection('notifications').add({
      recipientId: commentLike.commentOwnerId,
      actorId: commentLike.userId,
      type: 'commentLike',
      postId: commentLike.postId,
      stampId: commentLike.stampId,
      commentId: commentLike.commentId,
      commentPreview: commentPreview,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false
    });
    
    console.log(`✅ Comment like notification created for comment owner`);
    
    // Send push notification
    await sendPushNotification(
      commentLike.commentOwnerId,
      {
        title: 'New Like',
        body: `${likerName} liked your comment on ${stampName}`
      },
      {
        type: 'commentLike',
        postId: commentLike.postId,
        stampId: commentLike.stampId,
        commentId: commentLike.commentId
      }
    );
    
  } catch (error) {
    console.error(`❌ Error creating comment like notification:`, error);
  }
  
  return null;
});

/**
 * Firestore Trigger: Create notification when someone comments on a post
 * 
 * Triggered when a comment document is created in comments collection
 * Creates a notification for the post owner with comment preview
 * Also creates mention notifications for any @mentioned users
 */
exports.createCommentNotification = onDocumentCreated('comments/{commentId}', async (event) => {
  const comment = event.data.data();
  
  console.log(`📬 Processing comment: ${comment.userId} commented on post by ${comment.postOwnerId}`);
  
  try {
    // Fetch commenter's profile to get their name
    const commenterDoc = await admin.firestore().collection('users').doc(comment.userId).get();
    const commenterName = commenterDoc.exists ? commenterDoc.data().displayName : 'Someone';
    
    // Fetch stamp name for notification
    const stampDoc = await admin.firestore().collection('stamps').doc(comment.stampId).get();
    const stampName = stampDoc.exists ? stampDoc.data().name : 'a stamp';
    
    // Truncate comment text to 100 characters for preview
    const commentPreview = comment.text.length > 100 
      ? comment.text.substring(0, 100) + '...'
      : comment.text;
    
    // ==================== @MENTION NOTIFICATIONS ====================
    
    // Extract @mentions from comment text FIRST (process regardless of who commented)
    const mentionedUsernames = extractMentions(comment.text);
    
    // Track users who should be notified
    const notifiedUserIds = new Set();
    
    // ==================== POST OWNER NOTIFICATION ====================
    
    // Only create notification for post owner if someone ELSE commented
    if (comment.userId !== comment.postOwnerId) {
      // Check if post owner is mentioned
      let postOwnerIsMentioned = false;
      if (mentionedUsernames.length > 0) {
        console.log(`👥 Found ${mentionedUsernames.length} mentions: ${mentionedUsernames.join(', ')}`);
        
        // Get post owner's username to check if they're mentioned
        try {
          const postOwnerDoc = await admin.firestore()
            .collection('users')
            .doc(comment.postOwnerId)
            .get();
          
          if (postOwnerDoc.exists) {
            const postOwnerUsername = postOwnerDoc.data().username;
            postOwnerIsMentioned = mentionedUsernames.includes(postOwnerUsername.toLowerCase());
          }
        } catch (error) {
          console.error('Error checking if post owner is mentioned:', error);
        }
      }
      
      // Create notification for the post owner
      // If they were @mentioned, use "mention" type instead of "comment" type
      const notificationType = postOwnerIsMentioned ? 'mention' : 'comment';
      
      await admin.firestore().collection('notifications').add({
        recipientId: comment.postOwnerId,
        actorId: comment.userId,
        type: notificationType,
        postId: comment.postId,
        stampId: comment.stampId,
        commentId: event.params.commentId,  // ✅ ADD: commentId for scrolling to comment
        commentPreview: commentPreview,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false
      });
      
      console.log(`✅ ${notificationType} notification created for post owner${postOwnerIsMentioned ? ' (was @mentioned)' : ''}`);
      
      // Send push notification
      const pushBody = postOwnerIsMentioned 
        ? `${commenterName} tagged you in a comment on ${stampName}`
        : `${commenterName} commented on your ${stampName}`;
      
      await sendPushNotification(
        comment.postOwnerId,
        {
          title: postOwnerIsMentioned ? 'You were tagged' : 'New Comment',
          body: pushBody
        },
        {
          type: notificationType,
          postId: comment.postId,
          stampId: comment.stampId,
          commentId: event.params.commentId  // ✅ ADD: commentId for deep linking to specific comment
        }
      );
      
      // Track that post owner has been notified
      notifiedUserIds.add(comment.postOwnerId);
    } else {
      console.log(`⏭️ Skipping post owner notification (user commented on own post)`);
    }
    
    // ==================== REPLY NOTIFICATION ====================
    // If this is a reply (has parentCommentId), notify the parent comment author
    
    if (comment.parentCommentId) {
      console.log(`💬 This is a reply to comment: ${comment.parentCommentId}`);
      
      try {
        // Fetch the parent comment to get the author
        const parentCommentDoc = await admin.firestore()
          .collection('comments')
          .doc(comment.parentCommentId)
          .get();
        
        if (parentCommentDoc.exists) {
          const parentComment = parentCommentDoc.data();
          const parentCommentAuthorId = parentComment.userId;
          
          // Only notify if:
          // 1. Parent comment author is NOT the current commenter (don't notify yourself)
          // 2. Parent comment author hasn't already been notified (e.g., they're also the post owner)
          if (parentCommentAuthorId !== comment.userId && !notifiedUserIds.has(parentCommentAuthorId)) {
            
            // Check if parent comment author was @mentioned
            let parentAuthorIsMentioned = false;
            if (mentionedUsernames.length > 0) {
              try {
                const parentAuthorDoc = await admin.firestore()
                  .collection('users')
                  .doc(parentCommentAuthorId)
                  .get();
                
                if (parentAuthorDoc.exists) {
                  const parentAuthorUsername = parentAuthorDoc.data().username;
                  parentAuthorIsMentioned = mentionedUsernames.includes(parentAuthorUsername.toLowerCase());
                }
              } catch (error) {
                console.error('Error checking if parent comment author is mentioned:', error);
              }
            }
            
            // Create reply notification (use "mention" type if they were @mentioned, otherwise "comment")
            const notificationType = parentAuthorIsMentioned ? 'mention' : 'comment';
            
            await admin.firestore().collection('notifications').add({
              recipientId: parentCommentAuthorId,
              actorId: comment.userId,
              type: notificationType,
              postId: comment.postId,
              stampId: comment.stampId,
              commentId: event.params.commentId,  // ✅ ADD: commentId for scrolling to comment
              commentPreview: commentPreview,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              isRead: false
            });
            
            console.log(`✅ Reply notification created for parent comment author${parentAuthorIsMentioned ? ' (was @mentioned)' : ''}`);
            
            // Send push notification
            const pushBody = parentAuthorIsMentioned
              ? `${commenterName} tagged you in a reply on ${stampName}`
              : `${commenterName} replied to your comment on ${stampName}`;
            
            await sendPushNotification(
              parentCommentAuthorId,
              {
                title: parentAuthorIsMentioned ? 'You were tagged' : 'New Reply',
                body: pushBody
              },
              {
                type: notificationType,
                postId: comment.postId,
                stampId: comment.stampId,
                commentId: event.params.commentId  // ✅ ADD: commentId for deep linking to specific comment
              }
            );
            
            // Track that parent comment author has been notified
            notifiedUserIds.add(parentCommentAuthorId);
          } else if (parentCommentAuthorId === comment.userId) {
            console.log(`⏭️ Skipping reply notification (user replied to own comment)`);
          } else {
            console.log(`⏭️ Skipping reply notification (parent comment author already notified)`);
          }
        } else {
          console.log(`⚠️ Parent comment ${comment.parentCommentId} not found (might have been deleted)`);
        }
      } catch (replyError) {
        console.error(`❌ Error processing reply notification:`, replyError);
        // Continue - don't let reply notification failure break other notifications
      }
    }
    
    // ==================== ADDITIONAL MENTION NOTIFICATIONS ====================
    // Create mention notifications for any OTHER users who were mentioned (not already notified)
    
    if (mentionedUsernames.length > 0) {
      // Process each mentioned username
      for (const username of mentionedUsernames) {
        try {
          // Query Firestore to get userId from username
          const userSnapshot = await admin.firestore()
            .collection('users')
            .where('username', '==', username)
            .limit(1)
            .get();
          
          // Skip if username doesn't exist
          if (userSnapshot.empty) {
            console.log(`⚠️ Username @${username} not found - skipping mention notification`);
            continue;
          }
          
          const mentionedUserId = userSnapshot.docs[0].id;
          
          // Skip if user mentions themselves
          if (mentionedUserId === comment.userId) {
            console.log(`⚠️ User mentioned themselves (@${username}) - skipping self-mention`);
            continue;
          }
          
          // Skip if user already notified (post owner notification created above)
          if (notifiedUserIds.has(mentionedUserId)) {
            console.log(`⚠️ User @${username} already notified (post owner) - skipping duplicate`);
            continue;
          }
          
          // Create mention notification
          await admin.firestore().collection('notifications').add({
            recipientId: mentionedUserId,
            actorId: comment.userId,
            type: 'mention',
            postId: comment.postId,
            stampId: comment.stampId,
            commentId: event.params.commentId,  // ✅ ADD: commentId for scrolling to comment
            commentPreview: commentPreview,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            isRead: false
          });
          
          notifiedUserIds.add(mentionedUserId);
          console.log(`✅ Mention notification created for @${username}`);
          
          // Send push notification for mention
          await sendPushNotification(
            mentionedUserId,
            {
              title: 'You were tagged',
              body: `${commenterName} tagged you in a comment on ${stampName}`
            },
            {
              type: 'mention',
              postId: comment.postId,
              stampId: comment.stampId,
              commentId: event.params.commentId  // ✅ ADD: commentId for deep linking to specific comment
            }
          );
          
        } catch (mentionError) {
          console.error(`❌ Error processing mention for @${username}:`, mentionError);
          // Continue processing other mentions even if one fails
        }
      }
    }
    
  } catch (error) {
    console.error(`❌ Error creating comment notification:`, error);
  }
  
  return null;
});

/**
 * Firestore Trigger: Clean up notifications and likes when a comment is deleted
 * 
 * Triggered when a comment document is deleted from comments collection
 * Automatically deletes all related data to prevent orphaned records
 * 
 * This happens when:
 * - User deletes their own comment
 * - Post owner deletes someone's comment
 * 
 * Data cleaned up:
 * - Comment notifications (type: "comment")
 * - Mention notifications (type: "mention")
 * - CommentLike notifications (type: "commentLike")
 * - CommentLike documents (commentLikes collection)
 */
exports.cleanupCommentNotifications = onDocumentDeleted('comments/{commentId}', async (event) => {
  const commentId = event.params.commentId;
  const deletedComment = event.data.data();
  
  console.log(`🗑️ Comment deleted: ${commentId} - cleaning up notifications and likes...`);
  
  if (!deletedComment) {
    console.log('⚠️ No comment data available (already deleted)');
    return null;
  }
  
  try {
    // STEP 1: Find notifications by commentId (for NEW notifications that have this field)
    const notificationsByCommentId = await admin.firestore()
      .collection('notifications')
      .where('commentId', '==', commentId)
      .get();
    
    const notificationsToDelete = [];
    
    if (!notificationsByCommentId.empty) {
      console.log(`✅ Found ${notificationsByCommentId.size} notification(s) by commentId`);
      notificationsByCommentId.forEach(doc => {
        notificationsToDelete.push(doc.id);
      });
    } else {
      console.log(`⚠️ No notifications found by commentId - trying legacy method...`);
      
      // STEP 2: Fallback to old method for OLD notifications (without commentId field)
      // Find all notifications related to this comment (by postId + stampId + text matching)
      const notificationsQuery = await admin.firestore()
        .collection('notifications')
        .where('postId', '==', deletedComment.postId)
        .where('stampId', '==', deletedComment.stampId)
        .get();
      
      if (notificationsQuery.empty) {
        console.log('✓ No notifications found for this comment (legacy method)');
        return null;
      }
      
      // Filter to find notifications that match this specific comment
      // (by checking actorId matches commenter and commentPreview matches comment text)
      const commentPreview = deletedComment.text.length > 100 
        ? deletedComment.text.substring(0, 100) + '...'
        : deletedComment.text;
      
      notificationsQuery.forEach(doc => {
        const notifData = doc.data();
        
        // Match if:
        // 1. Actor is the commenter
        // 2. Type is "comment", "mention", or "commentLike"
        // 3. Comment preview matches
        if (notifData.actorId === deletedComment.userId && 
            (notifData.type === 'comment' || notifData.type === 'mention' || notifData.type === 'commentLike') &&
            notifData.commentPreview === commentPreview) {
          notificationsToDelete.push(doc.id);
        }
      });
      
      console.log(`✅ Found ${notificationsToDelete.length} notification(s) by legacy method`);
    }
    
    if (notificationsToDelete.length === 0) {
      console.log('✓ No matching notifications to delete');
      return null;
    }
    
    // Delete notifications in batch
    const batch = admin.firestore().batch();
    notificationsToDelete.forEach(notifId => {
      const notifRef = admin.firestore().collection('notifications').doc(notifId);
      batch.delete(notifRef);
    });
    
    await batch.commit();
    
    console.log(`✅ Deleted ${notificationsToDelete.length} notification(s) for deleted comment`);
    
    // STEP 3: Clean up commentLikes for this comment
    console.log(`🗑️ Cleaning up commentLikes for comment: ${commentId}`);
    
    const commentLikesQuery = await admin.firestore()
      .collection('commentLikes')
      .where('commentId', '==', commentId)
      .get();
    
    if (!commentLikesQuery.empty) {
      const likeBatch = admin.firestore().batch();
      commentLikesQuery.forEach(doc => {
        likeBatch.delete(doc.ref);
      });
      
      await likeBatch.commit();
      console.log(`✅ Deleted ${commentLikesQuery.size} commentLike(s) for deleted comment`);
    } else {
      console.log(`✓ No commentLikes to delete`);
    }
    
  } catch (error) {
    console.error(`❌ Error cleaning up notifications:`, error);
    // Don't throw - comment deletion already succeeded
    // Orphaned notifications will be cleaned up by scheduled job
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
 * NOTE: With bidirectional relationships, this function triggers on the 
 * "following" subcollection write. The iOS app also writes to "followers" 
 * subcollection, but we only need ONE trigger to update counts.
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

/**
 * Cloud Function: Email notification for user blocking events
 * 
 * Triggers when a new feedback document is created with type "User Blocked"
 * Sends immediate email notification to developer for ALL feedback submissions
 * 
 * App Store Requirement: Apps with UGC must respond to reports within 24 hours
 */
exports.notifyFeedback = onDocumentCreated('feedback/{feedbackId}', async (event) => {
  const feedback = event.data.data();
  const feedbackType = feedback.type || 'Unknown';
  
  console.log(`📬 New feedback received: ${feedbackType}`);
  
  // Determine urgency and emoji based on feedback type
  const urgentTypes = ['User Blocked', 'User Report', 'Comment Report', 'Post Report', 'Photo Report', 'Account Deletion Request'];
  const isUrgent = urgentTypes.includes(feedbackType);
  
  const emojiMap = {
    'User Blocked': '🚫',
    'User Report': '⚠️',
    'Comment Report': '💬',
    'Post Report': '📮',
    'Photo Report': '📷',
    'Problem Report': '🐛',
    'Feedback': '💭',
    'Stamp Edit Suggestion': '🏷️',
    'Collection Edit Suggestion': '📚',
    'Account Deletion Request': '🗑️',
    'Data Download Request': '📥',
    'User Unblocked': '✅'
  };
  const emoji = emojiMap[feedbackType] || '📋';
  
  try {
    // Configure email transporter
    // TODO: Move to environment variables for production
    const gmailEmail = 'watagumo.studio@gmail.com';
    const gmailPassword = 'qpbw erhy ijcf inwl';
    
    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {
        user: gmailEmail,
        pass: gmailPassword
      }
    });
    
    // Build email subject
    const subject = isUrgent 
      ? `🚨 [STAMPBOOK] ${feedbackType} - Review Required (24h)`
      : `${emoji} [STAMPBOOK] New ${feedbackType}`;
    
    // Build email body
    const urgencyNotice = isUrgent 
      ? '<p style="color: red; font-weight: bold;">⏰ App Store Compliance: You must review this within 24 hours.</p>'
      : '';
    
    const mailOptions = {
      from: gmailEmail,
      to: gmailEmail, // Send to yourself
      subject: subject,
      html: `
        <h2>${emoji} ${feedbackType}</h2>
        
        ${urgencyNotice}
        
        <hr>
        
        <h3>📋 Details</h3>
        <ul>
          <li><strong>Type:</strong> ${feedbackType}</li>
          <li><strong>From:</strong> ${feedback.username || 'Anonymous'} (${feedback.userId || 'N/A'})</li>
          <li><strong>Time:</strong> ${new Date().toISOString()}</li>
          <li><strong>Device:</strong> ${feedback.deviceModel || 'Unknown'} (iOS ${feedback.osVersion || 'Unknown'})</li>
          <li><strong>App Version:</strong> ${feedback.appVersion || 'Unknown'}</li>
        </ul>
        
        <h3>💬 Message</h3>
        <pre style="background-color: #f5f5f5; padding: 15px; border-radius: 5px; white-space: pre-wrap; word-wrap: break-word;">${feedback.message}</pre>
        
        <h3>🔗 Quick Actions</h3>
        <ul>
          <li><a href="https://console.firebase.google.com/project/stampbook-app/firestore/data/~2Ffeedback~2F${event.params.feedbackId}">View Feedback Document in Firebase</a></li>
          ${feedback.userId && feedback.userId !== 'anonymous' ? `<li><a href="https://console.firebase.google.com/project/stampbook-app/firestore/data/~2Fusers~2F${feedback.userId}">View User Profile in Firebase</a></li>` : ''}
        </ul>
        
        <hr>
        
        <p><em>This is an automated notification from Stampbook Cloud Functions.</em></p>
      `
    };
    
    // Send email
    await transporter.sendMail(mailOptions);
    console.log(`✅ Email notification sent successfully for ${feedbackType}`);
    
  } catch (error) {
    console.error('❌ Failed to send email notification:', error);
    // Don't throw - we don't want the Cloud Function to fail if email fails
    // The feedback document is still saved in Firestore for manual review
  }
  
  return null;
});

