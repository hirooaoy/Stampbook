# ✅ Suggest New Stamp & Collection Feature - COMPLETE

**Implementation Date:** November 7, 2025

## 📦 What Was Built

A clean, simple feature that allows users to suggest new stamps and collections directly from the app.

---

## 🆕 New Files Created

1. **`Stampbook/Models/StampSuggestion.swift`**
   - Data model for stamp/collection suggestions
   - Includes validation for complete stamp data
   
2. **`Stampbook/Views/Shared/StampSuggestionFormField.swift`**
   - Reusable form component for stamp input
   - 3 fields: Name, Full Address, Additional Notes
   - Clean design with placeholders and helper text

3. **`Stampbook/Views/Settings/SuggestStampView.swift`**
   - Single stamp suggestion view
   - Simple, Notes-like interface
   - Validates all fields before submission

4. **`Stampbook/Views/Settings/SuggestCollectionView.swift`**
   - Collection suggestion view
   - Starts with 3 stamps (minimum required)
   - "Add another stamp" button with NO LIMIT
   - Remove button for extra stamps (keeps minimum 3)
   - Validates collection name + at least 3 complete stamps

---

## 🔧 Modified Files

1. **`Stampbook/Services/FirebaseService.swift`**
   - Added `submitStampSuggestion()` method
   - Saves to Firestore `stamp_suggestions` collection

2. **`Stampbook/Views/Feed/FeedView.swift`**
   - Added menu items for both suggestions
   - Added sheet presentations
   - Already wired up! ✅

3. **`Stampbook/Views/Profile/StampsView.swift`**
   - Added menu items for both suggestions
   - Added sheet presentations
   - Already wired up! ✅

---

## 🎨 User Experience

### Where Users Access It
**Feed Menu** (hamburger icon) → "Suggest new stamp" or "Suggest new collection"
**Profile Menu** (hamburger icon) → Same options

### Suggest Single Stamp Flow
1. Tap "Suggest new stamp"
2. Fill in 3 fields:
   - Stamp Name
   - Full Address (with copy hint)
   - Additional notes (what should stamp include?)
3. Tap "Send"
4. Success: "Thank you! We'll review your suggestion."
5. Sheet dismisses

### Suggest Collection Flow
1. Tap "Suggest new collection"
2. Enter collection name
3. Fill in 3 stamps minimum (each with 3 fields)
4. Optionally add more stamps (unlimited)
5. Tap "Send" (disabled until valid)
6. Success: "Thank you! We'll review your collection."
7. Sheet dismisses

---

## 📊 Firestore Structure

**Collection:** `stamp_suggestions`

**Single Stamp Document:**
```json
{
  "userId": "user123",
  "username": "hiroo",
  "userDisplayName": "Hiroo",
  "type": "single_stamp",
  "stampName": "Golden Gate Bridge",
  "fullAddress": "Golden Gate Bridge\nSan Francisco, CA 94129\nUnited States",
  "additionalNotes": "Walk across bridge, photo spots at Battery Spencer",
  "collectionName": null,
  "additionalStamps": null,
  "createdAt": "2025-11-07T12:34:56Z"
}
```

**Collection Document:**
```json
{
  "userId": "user123",
  "username": "hiroo",
  "userDisplayName": "Hiroo",
  "type": "collection",
  "stampName": "Golden Gate Bridge",
  "fullAddress": "...",
  "additionalNotes": "...",
  "collectionName": "SF Landmarks",
  "additionalStamps": [
    {
      "name": "Alcatraz Island",
      "fullAddress": "...",
      "additionalNotes": "..."
    },
    {
      "name": "Painted Ladies",
      "fullAddress": "...",
      "additionalNotes": "..."
    }
  ],
  "createdAt": "2025-11-07T12:34:56Z"
}
```

---

## 🔍 Your Admin Workflow

### Reviewing Suggestions
1. Open Firebase Console → Firestore → `stamp_suggestions` collection
2. Browse submitted suggestions
3. For each good suggestion:
   - Copy the stamp data
   - Drop GPS pin in Google Maps at exact location
   - Add to `Stampbook/Data/stamps.json`:
     ```json
     {
       "id": "suggested_golden_gate",
       "name": "Golden Gate Bridge",
       "latitude": 37.81973360,  // from Google Maps pin
       "longitude": -122.47846360,  // from Google Maps pin
       "address": "Golden Gate Bridge\nSan Francisco, CA 94129\nUnited States",
       "about": "Walk across bridge, photo spots at Battery Spencer",
       "collectionIds": ["san-francisco"],
       "imageName": "",
       "imageUrl": "",
       "notesFromOthers": [],
       "thingsToDoFromEditors": []
     }
     ```
   4. Find/take/create image for the stamp
   5. Upload image to Firebase Storage
   6. Run: `node upload_stamps_to_firestore.js`
   7. Done! (Optional: delete old suggestion from Firestore)

---

## ✨ Features

✅ Clean, minimal UI matching SimpleFeedbackView design
✅ Native SwiftUI components
✅ Field validation (can't submit empty fields)
✅ Disabled submit button until valid
✅ Loading spinner during submission
✅ Success/error alerts
✅ Works for signed-in users only (requires auth)
✅ Unlimited stamps per collection (minimum 3)
✅ Remove button for extra stamps
✅ Helper text and placeholders
✅ Matches existing app design patterns

---

## 🚀 Ready to Test

1. Open Stampbook in Xcode
2. Build and run on simulator/device
3. Sign in with Apple ID
4. Tap hamburger menu (Feed or Profile)
5. Try "Suggest new stamp"
6. Try "Suggest new collection"
7. Check Firebase Console → `stamp_suggestions` collection

---

## 💡 Notes

- Users **cannot** add GPS coordinates (you add them manually from Google Maps)
- Users **cannot** upload images (you handle that separately)
- No approval/rejection system (just review and add good ones)
- Suggestions stay in Firestore forever (or delete them manually when done)
- Requires sign-in (anonymous users will see error alert)

---

## 🎯 Success!

The feature is complete, clean, and simple. Users can now contribute stamp suggestions, and you have a streamlined workflow to review and add them. 🚀

