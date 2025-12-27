# Unified Stamp Creation Workflow

---

## ⚠️ STEP 0: CHECK FOR DUPLICATES (BEFORE STARTING)

**CRITICAL:** Before creating any new stamps, always run:

```bash
node check_for_duplicates.js
```

This checks for:
1. ✅ Exact name duplicates (same stamp name appearing twice)
2. ✅ GPS coordinate duplicates (stamps within 10 meters)
3. ✅ Similar names in same location (potential typos/variants)

**If duplicates found:**
- 🛑 Stop immediately
- Run: `node remove_duplicate_stamp.js <stamp-id>`
- Choose the stamp ID that has NO collectors to delete (check Firebase console)
- Re-run duplicate check to confirm database is clean

**Once database is clean:** Proceed to workflow below

**Why this matters:** If duplicate stamps exist, users can collect both and it creates messy profile data that's hard to clean up. Prevention is critical!

---

## How This Works

This workflow handles **all stamp creation** with three automatic modes based on your request:

**🏞️ MODE 1: NATIONAL PARK**
- **When:** You mention a U.S. National Park (e.g., "Yellowstone", "Grand Canyon")
- **Process:** Agent proposes 8 candidates → You pick 4-7 → Creates collection
- **Result:** Multiple stamps + park collection

**🏙️ MODE 2: CITY/REGION**
- **When:** You mention a city or region (e.g., "San Francisco", "Seattle")
- **Process:** Agent proposes 6-10 candidates → You pick any number → Optional collection
- **Result:** Multiple stamps with or without collection

**📍 MODE 3: SINGLE LOCATION**
- **When:** You mention a specific place (e.g., "Monterey Bay Aquarium", "Space Needle")
- **Process:** Agent creates 1 stamp directly
- **Result:** Single stamp (no collection)

Agent automatically detects which mode to use based on your request.

---

## PART 1: UNIVERSAL REQUIREMENTS

These requirements apply to **all three modes**.

### Field Requirements

**Each stamp needs:**
```json
{
  "id": "country-state-city-place-name",
  "name": "Location Name",
  "latitude": 00.00000000,
  "longitude": -000.00000000,
  "geohash": "generated",
  "address": "Street Address\nCity, State ZIP",
  "collectionIds": [],
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

### About Section Style

- **130-155 characters** (strict)
- **Complete sentence with period at end**
- **DIVERSIFY**: Use interesting fun facts, not just descriptions
  - Historical facts (who built it, when, how long it took)
  - Surprising numbers (depth, height, age, temperature)
  - Designer/architect names for buildings
  - Unique details that make it memorable
  - Origin stories and legends
- **Natural conversational tone**
- **Avoid generic** "offers views" or "is known for" - be specific!

**Good Examples:**
- "Massive 50-ton glacial boulder deposited by retreating glaciers 18,000 years ago, precariously perched on the edge of South Bubble Mountain" (142 chars)
- "Built in 1879, this Victorian greenhouse is Golden Gate Park's oldest building and houses over 2,000 rare tropical plants from around the world" (155 chars)

### Things To Do Style

- **2-3 items** (agent picks best ones or user can request changes)
- **25-50 characters each** (aim for ~40, can go up to 80 for complex logistics)
- **Short, punchy sentences**
- **NO periods at end**
- **Practical, specific actions**
- **IMPORTANT:** Always check if location requires tickets/reservations and include that info in first item if needed

**Good Examples:**
- "Arrive early for sunrise" (25 chars) - short, actionable
- "Bring binoculars to spot bears" (31 chars) - short with tip
- "Order garlic fries and crab sandwich" (36 chars) - specific action
- "Walk both boardwalk loops" (26 chars) - clear and concise
- "Check visitor center for trail maps and times" (46 chars) - logistics, closer to 50 is OK

### Collection Radius

**`regular` (150m)** - Pin is exactly where people stand/walk
- Parking lots, visitor centers, paved viewpoints
- Accessible trails, hikable summits where trail reaches the pin
- Entrances, photo spots
- Any location where visitors can physically be within 150m

**`regularplus` (larger radius)** - Pin is at the subject being viewed from distance >150m away
- Pin in middle of lake where people view from shore 200m away
- Valley floor pin where people view from rim 500m away
- Distant peak not accessible by trail
- Subject in water or inaccessible area

**Decision Process:**
1. Where would someone drop a pin for this location?
2. Can people actually stand/walk at that pin location?
3. If YES and within 150m = `regular`
4. If NO or >150m away from nearest viewpoint = `regularplus`

### ID Naming Convention

**Format:** `country-state-city-place-name`

**Rules:**
- All lowercase
- Use hyphens between ALL words (not smashed together)
- Remove special characters (', &, etc.)
- Country: us, japan, uk, france, etc.
- State/region: For US states, use 2-letter postal codes (ca, ny, nd, tx, etc.)
- City: sanfrancisco, tokyo, paris (no hyphen for two-word cities)
- Place name: descriptive, hyphenated between words, no "the" prefix

**National Park Naming:**
- Include "national-park" in the ID: `us-state-parkname-national-park-location`
- Examples:
  - `us-wy-yellowstone-national-park-old-faithful-geyser`
  - `us-ca-sequoia-national-park-general-sherman-tree`
  - `us-fl-everglades-national-park-anhinga-trail`
- Exception: Grand Canyon uses `us-az-grand-canyon-location` (no "national-park")

**Examples:**
- `us-ca-sanfrancisco-golden-gate-bridge`
- `us-wy-yellowstone-national-park-old-faithful-geyser`
- `japan-tokyo-tokyo-senso-ji-temple`
- `us-ca-monterey-monterey-bay-aquarium`
- `us-ca-alameda-alameda-point-antiques-faire`
- `us-ca-pescadero-araceli-farms`

### ChatGPT Image Prompt Format

```
Generate a Japanese-style eki stamp of [NAME] in a [SHAPE] format. Use English letters only and feature [NAME] prominently. 

Include:
- [Visual element 1]
- [Visual element 2]
- [Visual element 3]
- [Visual element 4]
- [Visual element 5]

Style: crisp, simple, authentic ink-stamp look.

Preferred color: [single best color based on subject].

IMPORTANT:
- PNG with transparent background outside the border only.
- Interior must be solid white or cream like a real stamp impression.
- Ensure the entire stamp design fits within the border with no cropping at edges.
```

**Example:**
```
Generate a Japanese-style eki stamp of WAILEA BEACH in a wide horizontal rectangle format. Use English letters only and feature WAILEA BEACH prominently.

Include:
- Golden sand beach with calm waters
- Clear turquoise water perfect for swimming
- Luxury resort silhouettes in background
- Snorkelers exploring the water
- Tropical flowers (hibiscus) along the beach

Style: crisp, simple, authentic ink-stamp look.

Preferred color: sunset gold.

IMPORTANT:
- PNG with transparent background outside the border only.
- Interior must be solid white or cream like a real stamp impression.
- Ensure the entire stamp design fits within the border with no cropping at edges.
```

**Note:** 
- Include 3-5 specific visual elements that capture the location's essence
- Choose ONE best color for each stamp that matches the subject
- Do NOT include state/country outlines in prompts - keep stamps clean and focused on the subject

**Shape Selection Guide:**
- **Wide horizontal rectangle** - valleys, panoramic views, waterfront buildings, beaches, wide landscapes, historic districts
- **Tall vertical rectangle/arch** - viewpoints, waterfalls, tall formations, towers, monuments, vertical structures, skyscrapers
- **Square/rounded square** - general subjects, flexible format, works for most landmarks
- **Circle** - focal points, single monuments, central subjects, domes
- **Arched/dome top** - gates, archways, domes, traditional structures, classic aesthetic

**Color Selection Guide (choose ONE best color per stamp):**
- **Sunset/canyon:** sunset gold, canyon orange, or desert brown
- **Mountain:** mountain green, sunrise orange, or ridge brown
- **Valley:** valley green, warm earth brown, or river blue
- **Historic:** barn brown, rustic red, prairie gold, or heritage orange
- **Forest:** forest green, pine green, or sierra brown
- **Water:** ocean blue, waterfall blue, lake teal, or seafoam green
- **Urban/modern:** steel gray, city blue, metropolitan red, or skyline gold
- **Cultural:** temple red, shrine gold, or traditional purple
- **Food/restaurants:** traditional red, warm brown, or subject-appropriate color

### Address Format

**US Addresses:**
```
Street Address or Location Name
City, State USA ZIP
```

**Examples:**
- `886 Cannery Row\nMonterey, CA USA 93940`
- `Desert View Watchtower\nGrand Canyon Village, AZ USA 86023`
- `Rim Trail\nGrand Canyon Village, AZ USA 86023`

---

## PART 2: MODE-SPECIFIC PROCESSES

---

## MODE 1: NATIONAL PARK

**Trigger:** User mentions a U.S. National Park name

**Collection:** Always create `parkname-must-visits` collection

### Step 1: User Names Park
Example: "Arches National Park" or just "Arches"

### Step 2: Agent Proposes 8 Stamp Candidates

For each candidate:
- Name
- One sentence description
- Why it deserves a stamp

**Selection criteria:**
- Iconic features and formations
- Most photographed locations
- Accessible viewpoints
- Visitor center/ranger station (if significant)
- Historic sites within the park
- Popular trails with destinations

**IMPORTANT RULES:**
- **For scenic roads/drives:** Stamp name is "Road Name (Specific Location)"
  - Example: "Trail Ridge Road (Alpine Visitor Center)"
  - ChatGPT prompt uses the ROAD name: "TRAIL RIDGE ROAD"
  - About section: Fun fact about the ROAD itself
  - Things to do: Mention the specific location as a stop on the road
  - GPS: Pin at the specific collection location
- Every stamp needs a specific GPS pin where people can stand/collect

### Step 3: User Picks 4-7 Favorites
User tells agent which ones to proceed with

### Step 4: Agent Provides ALL ChatGPT Image Prompts First

Agent provides all ChatGPT image prompts at once so user can start generating images.

At the bottom, include a **Figma Layer Names** section:
```
**Figma Layer Names:**
- us-state-parkname-location1
- us-state-parkname-location2
- us-state-parkname-location3
```

Then asks: **"Ready to move on?"**

### Step 5: Agent Goes Through Each Stamp One-by-One

For each stamp:

**A) Show stamp name**

**B) Show About (with char count)**

**C) Show Things To Do (2-3 items, agent picks the best ones)**

**D) Show Collection Radius (with explanation)**
- `regular` (150m) = Pin is exactly where people stand/walk
- `regularplus` = Pin is at subject being viewed from distance >150m away

**E) Provide Google Maps link for location**

**F) Show Draft Address**

**G) Ask: "Is this draft address correct?"**

**H) Ask: "Give me the GPS coordinates"**

**I) Move to next stamp**

### Step 6: Agent Adds to JSON

Agent adds all stamps to:
- `Stampbook/Data/stamps.json` - with placeholder imageUrl
- `Stampbook/Data/collections.json` - create/update park collection

**Collection format:**
```json
{
  "id": "parkname-must-visits",
  "name": "Park Name National Park",
  "emoji": "🏞️",
  "description": "One sentence about what makes the park special",
  "region": "statename",
  "totalStamps": 5
}
```

### National Parks Completed

Track which parks are done:
- ✅ Grand Canyon (5 stamps)
- ✅ Yellowstone (7 stamps)
- ✅ Yosemite (6 stamps)
- ✅ Zion (5 stamps)
- ✅ Acadia (5 stamps)
- ✅ Sequoia (5 stamps)
- ✅ Everglades (5 stamps)
- ✅ Theodore Roosevelt (6 stamps)

**Goal:** Add all 63 U.S. National Parks with 4-7 stamps each = ~250-400 stamps total

---

## MODE 2: CITY/REGION

**Trigger:** User mentions a city or region (not a national park, not a single specific place)

**Collection:** Optional - ask user if they want to create one

### Step 1: User Names City/Region
Example: "San Francisco", "Seattle", "Kyoto"

### Step 2: Agent Proposes 6-10 Stamp Candidates

For each candidate:
- Name
- One sentence description  
- Why it deserves a stamp (iconic status, cultural significance, visitor appeal)

**Selection criteria - Mix of:**
- Famous landmarks
- Cultural sites
- Natural attractions
- Unique local spots
- Museums/galleries (if world-class)
- Historic buildings
- Waterfront features
- Parks and viewpoints

### Step 3: User Picks Favorites
User tells agent which ones to proceed with (can pick any number)

### Step 4: Agent Asks About Collection
"Would you like to create a collection for these stamps? If so, what should it be named?"

Options:
- Create a new collection (user provides name, emoji, description)
- Add to existing collection (user specifies which)
- No collection (default to empty array)

### Step 5: Agent Provides ALL ChatGPT Image Prompts First

Agent provides all ChatGPT image prompts at once so user can start generating images.

At the bottom, include a **Figma Layer Names** section:
```
**Figma Layer Names:**
- us-ca-sanfrancisco-goldengatebridge
- us-ca-sanfrancisco-alcatraz
- us-ca-sanfrancisco-paintedladies
```

Then asks: **"Ready to move on?"**

### Step 6: Agent Goes Through Each Stamp One-by-One

For each stamp:

**A) Show stamp name**

**B) Show About (with char count)**

**C) Show Things To Do (2-3 items, agent picks the best ones)**

**D) Show Collection Radius (with explanation)**
- `regular` (150m) = Pin is exactly where people stand/walk
- `regularplus` = Pin is at subject being viewed from distance >150m away

**E) Provide Google Maps link for location**

**F) Show Draft Address**

**G) Ask: "Is this draft address correct?"**

**H) Ask: "Give me the GPS coordinates"**

**I) Move to next stamp**

### Step 7: Agent Adds to JSON

Agent adds all stamps to:
- `Stampbook/Data/stamps.json` - with placeholder imageUrl and appropriate collectionIds
- `Stampbook/Data/collections.json` - create/update collection if requested

---

## MODE 3: SINGLE LOCATION

**Trigger:** User mentions a specific landmark/attraction (not a park, not a city)

**Collection:** Empty array unless user specifies

### Step 1: User Names Specific Location
Example: "Monterey Bay Aquarium", "Space Needle", "Statue of Liberty"

### Step 2: Agent Provides ChatGPT Image Prompt

Provide the ChatGPT image prompt immediately so user can start generating.

Include the **Figma Layer Name** at the bottom:
```
**Figma Layer Name:**
- us-california-monterey-montereybayaquarium
```

Then asks: **"Ready to move on?"**

### Step 3: Agent Provides Stamp Details

**A) Show stamp name**

**B) Show About (with char count)**

**C) Show Things To Do (2-3 items, agent picks the best ones)**

**D) Show Collection Radius (with explanation)**
- `regular` (150m) = Pin is exactly where people stand/walk
- `regularplus` = Pin is at subject being viewed from distance >150m away

**E) Provide Google Maps link for location**

**F) Show Draft Address**

**G) Ask: "Is this draft address correct?"**

**H) Ask: "Give me the GPS coordinates"**

### Step 4: Agent Adds to JSON

Agent adds stamp to `Stampbook/Data/stamps.json` with:
- Placeholder imageUrl
- Empty collectionIds array (unless user specifies a collection)

---

## PART 3: SHARED AUTOMATION

This applies to **all three modes** after stamps are added to JSON.

### Step 7/5/4 (depending on mode): User Unzips Images

1. User generates images in ChatGPT custom GPT using provided prompts
2. Images download to `/Users/haoyama/Downloads/` in folders named "Stampbook_ Collect the World (##)"
3. User unzips the folder
4. User tells agent the exact folder name

**File naming:** Images should be named exactly as stamp IDs: `us-state-city-place-name.png`

### Step 8/6/5 (depending on mode): Agent Handles Everything

Agent automatically performs these tasks:

#### 1. Verify File Names
Check all PNG files are named correctly matching stamp IDs

#### 2. Upload All Images
Upload to Firebase Storage with correct paths

#### 3. Link Images to Stamps
Update imageUrl fields in stamps.json by matching file names to stamp IDs

#### 4. Extract Aspect Ratios
Get actual image dimensions and calculate aspectRatio for each stamp

**IMPORTANT: aspectRatio = height ÷ width**
- Tall/vertical images (height > width): aspectRatio > 1.0 (e.g., 1.73 for 619×1072)
- Wide/horizontal images (width > height): aspectRatio < 1.0 (e.g., 0.58 for 1072×619)
- Square images: aspectRatio = 1.0

The app uses this formula to determine display:
- aspectRatio < 0.85 = WIDE horizontal stamp (full width display)
- aspectRatio ≥ 0.85 = TALL/standard vertical stamp

#### 5. Verify Each New Stamp
Go through one-by-one checking:
- Address format and accuracy (includes USA for US addresses)
- About section (130-155 chars, period at end, interesting content)
- Things to do (25-50 chars each, aim ~40, up to 80 for complex logistics, no periods)
- Naming conventions (stamp ID format: country-state-city-place-name)
- Collection IDs and labels (correct format, collection exists)
- Missing fields
- Collection radius logic (matches accessibility)
- Geohash generated correctly
- Any other issues

#### 6. Generate Thumbnails
Run `node generate_missing_thumbnails.js` to create 512x512 thumbnails for all new stamps

#### 7. Upload to Firebase
Run `node upload_stamps_to_firestore.js` to sync all stamp changes

**If you created or updated a collection:**
Run `node upload_collections_to_firestore.js` to sync collection changes

#### 8. Verify Sync
Confirm JSON and Firebase match perfectly

---

## Quick Commands

**Upload stamps to Firestore:**
```bash
node upload_stamps_to_firestore.js
```

**Upload collections to Firestore:**
```bash
node upload_collections_to_firestore.js
```

**Generate missing thumbnails:**
```bash
node generate_missing_thumbnails.js
```

**Check new stamps in Firebase:**
```bash
node check_new_stamps.js
```

**Admin upload page:**
https://stampbook-app.web.app/admin-upload-stamp.html

---

## Examples

### Example 1: National Park Mode

**User:** "Add Rocky Mountain National Park"

**Agent:** Proposes 8 candidates (Trail Ridge Road, Bear Lake, Dream Lake, Alberta Falls, etc.)

**User:** "Let's do 1, 2, 3, 4, 5"

**Agent:** Provides all 5 ChatGPT prompts + Figma layer names → Goes through each one-by-one for details → Adds to JSON with collection → Automates image upload and verification

---

### Example 2: City Mode

**User:** "Create stamps for Seattle"

**Agent:** Proposes 8 candidates (Space Needle, Pike Place Market, Chihuly Garden, MoPOP, Kerry Park, etc.)

**User:** "Let's do Space Needle, Pike Place, and Kerry Park"

**Agent:** "Would you like to create a collection for these Seattle stamps?"

**User:** "Yes, call it Seattle Favorites"

**Agent:** Provides all 3 ChatGPT prompts + Figma layer names → Goes through each one-by-one → Adds to JSON with new collection → Automates upload

---

### Example 3: Single Location Mode

**User:** "Create a stamp for Monterey Bay Aquarium"

**Agent:** Provides ChatGPT prompt + Figma layer name → Provides stamp details (about, things to do, etc.) → Adds to JSON (no collection) → Automates upload

---

## Notes

- Agent automatically detects which mode based on user's request
- Speed is important - move through stamps efficiently  
- User can always request changes to about/things to do content
- ChatGPT prompts should be specific and detailed for best image results
- Collections are flexible - national parks always get them, others are optional
- Geohash is auto-generated from coordinates
- All verification happens automatically after images are uploaded

---

## Strategy

**For National Parks:**
- Focus on most visited parks first
- 4-7 stamps per park is ideal
- Always include the most iconic features
- Consider accessibility (balance easy and challenging)

**For Cities:**
- Mix famous landmarks with hidden gems
- Consider what travelers actually visit
- Include variety (culture, nature, food, history)

**For Single Locations:**
- Make sure it's truly worth collecting
- Should be a destination, not just a random place
- Consider if it fits a future collection theme

---

This unified workflow scales to any location worldwide and any number of stamps.

