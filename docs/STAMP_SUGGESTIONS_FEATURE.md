# Stamp & Collection Suggestions Feature

## Overview
Users can now suggest new stamps and collections directly from the app. Suggestions are stored in Firestore for admin review.

---

## Files Created

### 1. **Models/StampSuggestion.swift**
Data model for stamp suggestions with validation.

### 2. **Views/Shared/StampSuggestionFormField.swift**
Reusable form component for entering stamp details (name, address, notes).

### 3. **Views/Settings/SuggestStampView.swift**
View for suggesting a single new stamp.

### 4. **Views/Settings/SuggestCollectionView.swift**
View for suggesting a collection with 3+ stamps (no maximum limit).

---

## Files Modified

### 1. **Services/FirebaseService.swift**
- Added `submitStampSuggestion()` method
- Writes to `stamp_suggestions` Firestore collection

### 2. **Views/Feed/FeedView.swift**
- Added menu items: "Suggest new stamp" and "Suggest new collection"
- Added sheet bindings for both views

### 3. **Views/Profile/StampsView.swift**
- Added same menu items for consistency
- Added sheet bindings for both views

---

## User Flow

### Suggest Single Stamp:
1. User taps menu → "Suggest new stamp"
2. Form appears:
   - Stamp Name (text field)
   - Full Address (text editor with hint to copy from Maps)
   - Additional notes (text editor - "What should the stamp include?")
3. "Send" button disabled until all fields filled
4. User taps Send → Success alert → Sheet dismisses

### Suggest Collection:
1. User taps menu → "Suggest new collection"
2. Form appears:
   - Collection Name (text field)
   - Stamp 1, 2, 3 (each with name, address, notes)
   - "➕ Add another stamp" button (no limit)
3. "Send" button disabled until:
   - Collection name filled
   - At least 3 stamps completely filled
4. User taps Send → Success alert → Sheet dismisses

---

## Firestore Structure

### Collection: `stamp_suggestions`

```json
{
  "id": "auto-generated",
  "userId": "user123",
  "userName": "hiroo",
  "userDisplayName": "Hiroo",
  "type": "single_stamp" | "collection",
  
  // Single stamp fields (always present)
  "stampName": "Golden Gate Bridge",
  "fullAddress": "Golden Gate Bridge\nSan Francisco, CA 94129, USA",
  "additionalNotes": "Walk across bridge, photo at Battery Spencer",
  
  // Collection fields (only if type = "collection")
  "collectionName": "SF Landmarks",
  "additionalStamps": [
    {
      "name": "Alcatraz Island",
      "fullAddress": "...",
      "additionalNotes": "..."
    }
  ],
  
  "createdAt": Timestamp
}
```

---

## Admin Review Workflow

### Step 1: View Suggestions
Go to Firebase Console → Firestore → `stamp_suggestions` collection

### Step 2: For Single Stamp
1. Copy suggestion data
2. Drop GPS pin in Google Maps at exact location
3. Add to `stamps.json`:
   ```json
   {
     "id": "unique_id",
     "name": "from suggestion",
     "address": "from suggestion",
     "latitude": 0.0,  // from Google Maps
     "longitude": 0.0,  // from Google Maps
     "about": "from additionalNotes",
     "collectionIds": ["relevant_collection"],
     "imageName": "",
     "imageUrl": "",
     "notesFromOthers": [],
     "thingsToDoFromEditors": []
   }
   ```
4. Find/create image, upload to Firebase Storage
5. Run `node upload_stamps_to_firestore.js`

### Step 3: For Collection
1. Add collection to `collections.json`
2. Add all stamps (repeat above for each)
3. Run upload script

### Step 4: Cleanup (Optional)
- Delete reviewed suggestions from Firestore when done
- Or leave them for record-keeping

---

## Validation Rules

✅ All text fields must be non-empty (trimmed)
✅ Collections require minimum 3 complete stamps
✅ "Send" button disabled until valid
✅ User must be signed in (shows alert if not)

---

## Design Notes

- Matches `SimpleFeedbackView` style (Notes-like interface)
- Clean, minimal design with native iOS components
- TextEditor with placeholder text and hints
- Loading spinner during submission
- Success/error alerts
- Works on both Feed and Profile tabs

---

## Menu Structure

```
About Stampbook
───────────────
For local business
───────────────
➕ Suggest new stamp          ← NEW
📚 Suggest new collection      ← NEW
───────────────
Report a problem
Send feedback
───────────────
[User profile options...]
```

---

## Future Enhancements (Optional)

- Auto-geocoding (address → GPS coordinates)
- Image upload with suggestions
- Duplicate detection
- Vote/upvote system
- Rate limiting (max suggestions per day)
- Admin dashboard for easier review
- User rewards for approved suggestions
- Export script to format suggestions as ready-to-paste JSON

---

## Testing Checklist

- [ ] Open Feed → Menu → "Suggest new stamp"
- [ ] Verify form appears with all fields
- [ ] Verify "Send" disabled when fields empty
- [ ] Fill out form, tap Send
- [ ] Verify success alert appears
- [ ] Check Firebase Console for suggestion in `stamp_suggestions`
- [ ] Open Profile → Menu → "Suggest new collection"
- [ ] Add 3 stamps, verify Send enables
- [ ] Add 4th stamp using "+" button
- [ ] Remove stamp using trash icon
- [ ] Submit and verify success
- [ ] Try to submit with only 2 complete stamps (should be disabled)
- [ ] Try when signed out (should show alert)

---

## Complete! 🎉

The feature is fully implemented and ready to use. Users can now contribute stamp and collection suggestions directly from the app!

