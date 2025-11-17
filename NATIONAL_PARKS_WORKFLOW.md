# National Parks Stamp Creation Workflow

## Goal
Add all 63 U.S. National Parks with 4-7 stamps each = ~250-400 stamps total

## Field Requirements

**Each stamp needs:**
```json
{
  "id": "us-state-parkname-locationname",
  "name": "Location Name",
  "latitude": 00.00000000,
  "longitude": -000.00000000,
  "geohash": "generated",
  "address": "Street Address\nCity, State ZIP",
  "collectionIds": ["parkname-must-visits"],
  "about": "130-155 char sentence with interesting fact/history. Ends with period.",
  "thingsToDoFromEditors": [
    "Practical action item with logistics info",
    "Another specific thing visitors can do",
    "Optional third activity"
  ],
  "imageUrl": "firebase_storage_url",
  "aspectRatio": 0.6,
  "collectionRadius": "regular" or "regularplus"
}
```

**About Section Style:**
- 130-155 characters (strict)
- Complete sentence with period at end
- Interesting historical fact, date, number, designer, unique detail
- Natural conversational tone
- Focus on WHAT it is and WHEN/history

**Things To Do Style:**
- 2-3 items (user picks from 3-5 options provided)
- 80-100 characters each
- Short sentences with logistics
- NO periods at end
- Practical, specific actions

**Collection Radius:**
- `regular` (150m) - Pin is exactly where people stand/walk (parking lots, visitor centers, paved viewpoints, accessible trails, hikable summits where trail reaches the pin)
- `regularplus` (larger radius) - Pin is at the subject being viewed, not where people stand. Need to calculate:
  - If pin is in middle of lake, distant peak, valley floor far from road, etc.
  - Check if nearest viewpoint/trail/access point is within 150m of pin
  - If viewpoint is >150m away from pin = regularplus
  - If viewpoint is ≤150m from pin = regular
  
**Examples:**
- Viewpoint at canyon rim where people stand = `regular`
- Valley floor pin where people view from rim 500m away = `regularplus`
- Waterfall with trail leading to base = `regular`
- Lake in middle where people view from shore 200m away = `regularplus`
- Summit with trail reaching the exact peak = `regular`

---

## Step-by-Step Process

### STEP 1: User Names Park
Example: "Arches National Park"

### STEP 2: Agent Proposes 8 Stamp Candidates
For each candidate:
- Name
- One sentence description
- Why it deserves a stamp

### STEP 3: User Picks 4-7 Favorites
User tells agent which ones to proceed with

### STEP 4: Agent Provides ALL ChatGPT Image Prompts First

Agent provides all ChatGPT image prompts at once so user can start generating images.

At the bottom, include a **Figma Layer Names** section with all stamp IDs listed:
```
**Figma Layer Names:**
- us-state-parkname-location1
- us-state-parkname-location2
- us-state-parkname-location3
```

User can copy-paste these to create Figma layers and export with correct naming.

Then asks: "Ready to move on?"

### STEP 5: Agent Goes Through Each Stamp One-by-One

For each stamp:

#### A) Show stamp name

#### B) Show About (with char count)

#### C) Show Things To Do (2-3 items, agent picks the best ones)

#### D) Show Collection Radius (with explanation)
- `regular` (150m) = Pin is exactly where people stand/walk
- `regularplus` = Pin is at subject being viewed from distance >150m away

#### E) Provide Google Maps link for location

#### F) Show Draft Address

#### G) Ask: "Is this draft address correct?"

#### H) Ask: "Give me the GPS coordinates"

#### I) Move to next stamp

### ORIGINAL STEP 4 (for reference):

For each chosen stamp, agent provides:

#### A) ChatGPT Image Prompt
```
Create a Japanese-style eki stamp of [NAME] in a [SHAPE] format.

Use English letters only and feature [NAME] prominently.

Include:
- [Visual element 1]
- [Visual element 2]
- [Visual element 3]
- [Visual element 4]
- [Visual element 5]

Style: crisp, simple, authentic ink-stamp look.

Preferred color: [color options based on subject].

IMPORTANT:
- PNG with transparent background outside the border only.
- Interior must be solid white or cream like a real stamp impression.
```

**Shape Selection Guide:**
- **Wide horizontal rectangle** - valleys, panoramic views, historic districts, wide landscapes
- **Tall vertical rectangle/arch** - viewpoints, waterfalls, tall formations, trails with elevation
- **Square/rounded square** - general subjects, flexible format
- **Circle** - focal points, single monuments, central subjects

**Color Selection Guide:**
- Sunset/canyon colors: sunset gold, canyon orange, desert brown
- Mountain colors: mountain green, sunrise orange, ridge brown
- Valley colors: valley green, warm earth brown, river blue
- Historic colors: barn brown, rustic red, prairie gold
- Forest colors: forest green, pine green, sierra brown
- Water colors: ocean blue, waterfall blue, lake teal

#### B) Pre-Written "About" Section
130-155 chars with period, interesting fact/history

#### C) 3-5 "Things To Do" Options
User will pick 2-3 of them

#### D) Draft Address
Agent researches and provides draft address for user to confirm

#### E) Collection Info
- Collection ID: `parkname-must-visits`
- Collection name
- Emoji suggestion
- Description

### STEP 6: Agent Adds to JSON

Agent adds all stamps to:
- `Stampbook/Data/stamps.json` - with placeholder imageUrl
- `Stampbook/Data/collections.json` - create/update park collection

### STEP 7: User Unzips Images

1. User unzips the Stampbook download folder in `/Users/haoyama/Downloads/`
2. User tells agent the exact folder name

### STEP 8: Agent Handles Everything

Agent does the following automatically:

1. **Verify file names** - Check all PNG files are named correctly matching stamp IDs
2. **Upload all images** - Upload to Firebase Storage with correct paths
3. **Link images to stamps** - Update imageUrl fields in stamps.json by matching file names to stamp IDs
4. **Extract aspect ratios** - Get actual image dimensions and calculate aspectRatio for each stamp
5. **Verify each new stamp** - Go through one-by-one checking:
   - Address format and accuracy
   - About section (130-155 chars, period at end)
   - Things to do (80-100 chars each, no periods)
   - Naming conventions (stamp ID format)
   - Collection IDs and labels
   - Missing fields
   - Collection radius logic
   - Any other issues
6. **Upload to Firebase** - Run `node upload_stamps_to_firestore.js` to sync
7. **Verify sync** - Confirm JSON and Firebase match

This is the ONLY workflow to follow from now on.

### NOTES

- For each new park, agent creates a new collection following existing naming conventions:
  - Collection ID: `parkname-must-visits` (lowercase, hyphenated)
  - Collection name: "Park Name National Park"
  - Emoji: Choose appropriate emoji for the park
  - Description: One sentence about what makes the park special
  - Region: state name (lowercase)
  - totalStamps: Accurate count of stamps in collection

### OLD STEP 7: User Uploads Images

1. Generate images in ChatGPT using provided prompts
2. Images download to `/Users/haoyama/Downloads/` in folders named "Stampbook_ Collect the World (##)"
3. Rename files to match stamp IDs: `us-state-parkname-locationname.png`
4. Upload via Firebase admin page: https://stampbook-app.web.app/admin-upload-stamp.html
5. User provides image URLs when done

### STEP 8: Agent Finalizes

1. Update imageUrl fields in `stamps.json` with URLs provided by user
2. Run `node upload_stamps_to_firestore.js` to sync to Firebase
3. Verify all stamps are live

---

## Parks Already Completed

- ✅ Grand Canyon (5 stamps)
- ✅ Yellowstone (7 stamps)
- ✅ Yosemite (6 stamps)
- ✅ Zion (5 stamps)
- ✅ Acadia (5 stamps)
- ✅ Sequoia (5 stamps)

---

## Example Reference: Yellowstone Stamps

**Good About Examples:**
- "Hayden Valley sits near the center of Yellowstone and offers one of the park's best places to see large bison herds roaming freely across open grasslands." (155 chars)
- "The vivid rainbow colors come from heat-loving bacteria that thrive in mineral-rich water. It is the largest hot spring in the United States (3rd in the world)." (160 chars - slightly over but good style)

**Good Things To Do Examples:**
- "Drive through the valley early or late in the day for the best wildlife activity"
- "Bring binoculars if you want a better chance of spotting bears or distant bison"
- "Walk both the Porcelain Basin and Back Basin boardwalk loops from the main parking area"
- "Check the posted eruption prediction times at the visitor center before you walk to the viewing area"

---

## Quick Commands

**Check new stamps in Firebase:**
```bash
node check_new_stamps.js
```

**Upload stamps to Firestore:**
```bash
node upload_stamps_to_firestore.js
```

**Admin upload page:**
https://stampbook-app.web.app/admin-upload-stamp.html

---

## Notes

- Agent warns if user tries to add a park that's already done
- User can do parks in any order (random is fine)
- Agent keeps track of which stamps belong to which park
- Image generation happens in batches while agent prepares next park's data
- Speed goal: 30-45 minutes per park

