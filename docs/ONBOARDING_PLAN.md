# Onboarding Plan

## Overview
This document outlines the user onboarding flow for the Stampbook iOS app, designed to guide new users to claim their first stamp through a notification-based system.

## Onboarding Flow

### 1. App Download
User downloads the Stampbook app from the App Store.

### 2. Pre-Authentication Experience
- User sees the sign-in screen
- User can interact with the app to some degree (view limited content)
- **No changes needed to this existing behavior**

### 3. Post-Authentication Experience

After the user successfully signs in, the following onboarding mechanism activates:

#### Notification Bell System

**Location:**
- Top right corner of:
  - Feed View
  - Stamp View (map/list view)
- **NOT on** Stamp Detail View

**Functionality:**
- Notification bell icon appears
- Clicking the bell opens a Notification List View (new feature to be built)

#### Welcome Notification

**Content:**
- Sender: "Admin" or "Stampbook Team"
- Message: "Welcome! Claim your first stamp"
- Action: Links to the Welcome Stamp

#### Welcome Stamp

**Special Properties:**
- **No location requirement** - can be claimed from anywhere
- Acts as a regular stamp in all other respects (appears in profile, has image, etc.)
- Purpose: Ensures every new user has at least one stamp and understands the claiming mechanism
- Encourages immediate engagement and collection start

## Future Notification System

The notification bell will serve as the foundation for a full notification system:

### Planned Notification Types:
- **Social notifications:**
  - Someone liked your stamp collection post
  - Someone commented on your stamp
  - Someone followed you
  - Someone mentioned you
  
- **System notifications:**
  - New stamps available in your area
  - Achievement unlocked
  - Collection milestones

### Current Scope (MVP):
- Notification bell UI component
- Notification List View
- Welcome notification only
- Basic notification data model in Firestore

## Technical Implementation Notes

### Components to Build:
1. **Notification Bell Icon**
   - SwiftUI View component
   - Badge indicator for unread count
   - Positioned in navigation bar of Feed and Stamp views

2. **Notification List View**
   - New SwiftUI View
   - Displays list of notifications
   - Mark as read functionality
   - Pull to refresh

3. **Notification Manager**
   - Handles fetching notifications from Firestore
   - Real-time updates via listeners
   - Mark notifications as read/unread
   - Badge count management

4. **Notification Model**
   - `Notification.swift` model
   - Fields: id, userId, type, message, createdAt, isRead, relatedStampId (optional)

5. **Firestore Schema**
   - Collection: `notifications`
   - Subcollection under user: `users/{userId}/notifications`
   - Indexed on: userId, createdAt, isRead

6. **Welcome Stamp Creation**
   - Add Welcome stamp to `stamps.json`
   - No latitude/longitude coordinates
   - Special flag: `isWelcomeStamp: true` or `requiresLocation: false`
   - Modify claiming logic to allow location-free claiming for this stamp

### Modified Components:
- **StampsManager.swift** - Add logic to handle welcome stamp claiming without location check
- **FeedView.swift** - Add notification bell to navigation bar
- **MapView.swift** (or main stamp view) - Add notification bell to navigation bar

## Design Considerations

### UX Principles:
- **Non-intrusive**: Notification bell approach is less pushy than forced onboarding modal
- **User control**: User can claim welcome stamp when ready
- **Discoverability**: Bell icon is standard pattern users understand
- **Scalability**: Foundation for full notification system later

### Edge Cases:
- What if user dismisses welcome notification without claiming?
  - Notification stays in list until claimed
  - Could add auto-claim after X days if needed
- What if user claims welcome stamp before seeing notification?
  - Mark notification as read automatically
- Multiple devices?
  - Firestore sync handles this automatically

## Success Metrics

For MVP phase (100 users target):
- % of new users who claim welcome stamp within 24 hours
- % of new users who claim welcome stamp within 7 days
- Time from sign-up to first stamp claim
- Notification bell interaction rate

## Status

**Current Status:** Planning
**Target Completion:** TBD
**Priority:** Medium (improves new user experience, but app functional without it)

## Related Documentation
- See `ADDING_STAMPS.md` for how to add stamps to the system
- See `CODE_STRUCTURE.md` for overall app architecture
- See `FIREBASE_SETUP.md` for Firestore schema and setup

