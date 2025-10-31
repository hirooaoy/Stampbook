# Profile Editing Feature - Complete Documentation

## 📝 Overview

The Profile Editing feature allows users to customize their profile information including display name, username, bio, and profile picture. All changes are synced to Firebase in real-time.

---

## 🎯 Key Features

### 1. **Username Validation**
- **Format:** Lowercase, alphanumeric + underscore only
- **Length:** 3-20 characters
- **Uniqueness:** Validated against Firestore before saving
- **Real-time Sanitization:** Invalid characters are automatically removed as user types

### 2. **Profile Photo Management**
- **Upload:** New photos uploaded to Firebase Storage
- **Auto-Cleanup:** Old photos automatically deleted to save storage costs
- **Compression:** JPEG format at 80% quality
- **Path Structure:** `users/{userId}/profile_photo/{uuid}.jpg`

### 3. **Input Validation**
- **Display Name:** 20 character limit, cannot be empty
- **Username:** 3-20 characters, unique across all users
- **Bio:** 70 character limit, optional field
- **Live Feedback:** Character counts and error messages shown in real-time

### 4. **User Experience**
- **Loading Overlay:** Full-screen indicator during save
- **Disabled Save:** Button disabled until all validations pass
- **Error Handling:** Clear error messages for all failure cases
- **Optimistic Updates:** Local state updates before Firebase confirmation

---

## 🏗️ Architecture

### File Structure

```
Stampbook/
├── Views/
│   └── Profile/
│       ├── ProfileEditView.swift         # Main edit screen UI
│       └── StampsView.swift              # Profile view with edit button
├── Services/
│   └── FirebaseService.swift            # Firebase operations
├── Managers/
│   └── ProfileManager.swift             # Profile state management
└── Models/
    └── UserProfile.swift                # User data model
```

---

## 🔄 Profile Editing Flow

### Step-by-Step Process

```
1. User taps pencil icon in profile
   ↓
2. StampsView opens ProfileEditView sheet
   ↓
3. User modifies fields (real-time validation)
   ↓
4. User taps "Save"
   ↓
5. Validate all inputs
   ↓
6. Check username uniqueness (if changed)
   ↓
7. Upload new photo (if selected)
   ↓
8. Delete old photo (if exists)
   ↓
9. Update Firestore user document
   ↓
10. Fetch updated profile
   ↓
11. Call onSave callback
   ↓
12. Dismiss sheet
```

### Code Flow Diagram

```swift
// StampsView.swift (lines 48-56)
Button(action: { showEditProfile = true })
    ↓
// Sheet presentation (lines 363-374)
ProfileEditView(profile: profile) { updatedProfile in
    profileManager.updateProfile(updatedProfile)
}
    ↓
// ProfileEditView.swift (lines 250-353)
saveProfile() 
    ↓
// FirebaseService.swift
isUsernameAvailable()      // Line 267
uploadProfilePhoto()       // Line 305
updateUserProfile()        // Line 244
fetchUserProfile()         // Line 195
```

---

## 📋 Key Functions Explained

### ProfileEditView.swift

#### `saveProfile()` (lines 250-353)
**Purpose:** Main save function that orchestrates the entire update process

**Steps:**
1. **Authentication Check** - Verify user is signed in
2. **Input Validation** - Check display name and username requirements
3. **Username Uniqueness** - Query Firestore if username changed
4. **Photo Upload** - Upload new image and delete old one if needed
5. **Firestore Update** - Save changes to user document
6. **Profile Fetch** - Get updated profile from Firestore
7. **UI Update** - Update local state and dismiss sheet

**Error Handling:**
- Authentication errors → Show alert
- Validation errors → Show inline error messages
- Network errors → Show alert with error description

---

### FirebaseService.swift

#### `updateUserProfile()` (lines 244-262)
**Purpose:** Update specific fields in user's Firestore document

**Parameters:**
- `userId`: User's Firebase Auth ID
- `displayName`: New display name (optional)
- `bio`: New bio text (optional)
- `avatarUrl`: New photo URL (optional)
- `username`: New username (optional)

**Behavior:**
- Only updates fields that are provided (non-nil)
- Always updates `lastActiveAt` timestamp
- Uses `updateData()` to only modify specific fields

---

#### `isUsernameAvailable()` (lines 267-286)
**Purpose:** Check if a username is already taken by another user

**Logic:**
1. Query Firestore for documents with matching username
2. If no results → Username is available
3. If 1 result and it's the current user → Available (keeping own username)
4. Otherwise → Username is taken

**Returns:** `Bool` - true if available, false if taken

---

#### `uploadProfilePhoto()` (lines 305-331)
**Purpose:** Upload new profile photo and delete old one

**Process:**
1. **Delete old photo** - If `oldAvatarUrl` provided, delete it first
2. **Generate unique filename** - Use UUID for uniqueness
3. **Set metadata** - Mark as JPEG content type
4. **Upload to Storage** - Store in `users/{userId}/profile_photo/` path
5. **Get download URL** - Return URL for Firestore storage

**Storage Structure:**
```
Firebase Storage
└── users/
    └── {userId}/
        └── profile_photo/
            └── {uuid}.jpg
```

---

## 🔒 Security

### Firestore Rules (firestore.rules)

```javascript
// User profile data (lines 25-28)
match /users/{userId} {
  allow read: if isSignedIn();     // Anyone can read profiles
  allow write: if isOwner(userId); // Only owner can update
}
```

**Protection:**
- ✅ Users can only edit their own profile
- ✅ All signed-in users can read profiles (for social features)
- ✅ Username uniqueness enforced by validation function
- ✅ Photo uploads require authentication (Storage rules)

---

## 🎨 UI Components

### Form Sections

#### 1. Profile Photo Section
- **Display:** Shows current photo or placeholder
- **Interaction:** `PhotosPicker` for selecting new photo
- **Preview:** Shows selected photo immediately

#### 2. Username Field
- **Format:** `@username` prefix displayed
- **Validation:** Real-time sanitization and length check
- **Error Display:** Shows "username taken" or character limit warnings

#### 3. Display Name Field
- **Format:** Standard text field
- **Validation:** 20 character limit
- **Error Display:** Character count warning

#### 4. Bio Field
- **Format:** Multi-line `TextEditor`
- **Validation:** 70 character limit
- **Placeholder:** "Tell others about yourself..."

### Toolbar Buttons

- **Cancel:** Dismisses sheet, discards changes
- **Save:** Validates and saves changes
  - Disabled when:
    - Display name is empty
    - Username is empty
    - Username is less than 3 characters
    - Currently loading

---

## 🧪 Testing Checklist

### ✅ Username Validation
- [ ] Accepts valid characters (letters, numbers, underscore)
- [ ] Rejects invalid characters (spaces, special chars)
- [ ] Enforces 3 character minimum
- [ ] Enforces 20 character maximum
- [ ] Shows "username taken" error for duplicates
- [ ] Allows keeping existing username

### ✅ Photo Upload
- [ ] Uploads new photo successfully
- [ ] Deletes old photo before uploading new one
- [ ] Shows preview of selected photo
- [ ] Works with various image sizes

### ✅ Form Validation
- [ ] Save disabled with empty display name
- [ ] Save disabled with short username
- [ ] Character limits enforced on all fields
- [ ] Error messages display correctly

### ✅ Integration
- [ ] Profile updates visible immediately after save
- [ ] Changes persist after app restart
- [ ] Works offline (shows appropriate error)
- [ ] Loading overlay shows during save

---

## 🐛 Common Issues & Solutions

### Issue: Username validation not working
**Cause:** Firestore index might not be created
**Solution:** Deploy Firestore rules and ensure username field is indexed

### Issue: Photo upload fails
**Cause:** Firebase Storage rules not configured
**Solution:** Deploy storage rules with authentication requirement

### Issue: Save button always disabled
**Cause:** Validation logic too strict
**Solution:** Check character trimming and minimum length logic

### Issue: Old photos not deleted
**Cause:** Invalid URL format
**Solution:** Ensure avatar URLs are full Firebase Storage URLs

---

## 📊 Performance Considerations

### Firebase Reads/Writes per Save

| Operation | Type | Count | Cost Impact |
|-----------|------|-------|-------------|
| Username check | Read | 0-1 | Only if username changed |
| Photo upload | Write | 1 | Only if photo selected |
| Photo delete | Write | 0-1 | Only if old photo exists |
| Profile update | Write | 1 | Every save |
| Profile fetch | Read | 1 | Every save |

**Total per save:** ~2-4 operations (very efficient)

### Optimization Strategies

1. **Conditional Username Check** - Only validates if username changed
2. **Photo Cleanup** - Deletes old photos to save storage costs
3. **Partial Updates** - Only updates changed fields
4. **Local State** - Updates UI immediately before Firebase confirmation

---

## 🚀 Future Enhancements

### Potential Improvements

1. **Username Suggestions** - Suggest available usernames
2. **Photo Cropping** - Built-in image cropper
3. **Photo Filters** - Apply filters before upload
4. **Multiple Photos** - Allow photo gallery for profile
5. **Username History** - Track username changes
6. **Profile Verification** - Badge for verified users
7. **Profile Templates** - Pre-designed profile layouts
8. **Social Links** - Add Instagram, Twitter, etc.

---

## 📚 Related Documentation

- **FIREBASE_IMPLEMENTATION_SUMMARY.md** - Overall Firebase architecture
- **FIREBASE_SETUP.md** - Firebase setup instructions
- **firestore.rules** - Security rules documentation
- **storage.rules** - Storage security rules

---

## 🎓 Learning Resources

### Key Concepts Used

1. **SwiftUI State Management** - `@State`, `@Published`
2. **Async/Await** - Modern Swift concurrency
3. **Firebase Auth** - User authentication
4. **Firestore** - NoSQL database operations
5. **Firebase Storage** - File storage and management
6. **PhotosPicker** - Native iOS photo selection
7. **Form Validation** - Real-time input validation

### Recommended Reading

- [Firebase Auth Documentation](https://firebase.google.com/docs/auth)
- [Firestore Data Modeling](https://firebase.google.com/docs/firestore/data-model)
- [Firebase Storage Best Practices](https://firebase.google.com/docs/storage/best-practices)
- [SwiftUI PhotosPicker](https://developer.apple.com/documentation/photokit/photospicker)

---

**Last Updated:** October 31, 2025  
**Version:** 1.0  
**Status:** ✅ Complete and Production Ready

