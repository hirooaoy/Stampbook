#!/bin/bash

# Upload stamp images to Firebase Storage
# Usage: ./upload_stamp_images.sh /path/to/images/folder

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "🖼️  Stamp Image Uploader for Firebase Storage"
echo "=============================================="
echo ""

# Check if firebase-tools is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found!${NC}"
    echo ""
    echo "Install it with:"
    echo "  npm install -g firebase-tools"
    echo ""
    exit 1
fi

# Check if logged in
if ! firebase projects:list &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Firebase${NC}"
    echo "Logging in now..."
    firebase login
fi

# Check if folder path provided
if [ -z "$1" ]; then
    echo -e "${RED}❌ Please provide the path to your images folder${NC}"
    echo ""
    echo "Usage:"
    echo "  ./upload_stamp_images.sh /path/to/images/folder"
    echo ""
    echo "Example:"
    echo "  ./upload_stamp_images.sh ~/Desktop/stamp-images"
    echo ""
    exit 1
fi

IMAGES_FOLDER="$1"

# Check if folder exists
if [ ! -d "$IMAGES_FOLDER" ]; then
    echo -e "${RED}❌ Folder not found: $IMAGES_FOLDER${NC}"
    exit 1
fi

# Count images
IMAGE_COUNT=$(find "$IMAGES_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | wc -l | tr -d ' ')

if [ "$IMAGE_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ No images found in $IMAGES_FOLDER${NC}"
    echo "Looking for: *.jpg, *.jpeg, *.png files"
    exit 1
fi

echo -e "${GREEN}✅ Found $IMAGE_COUNT images${NC}"
echo ""
echo "📤 Uploading to Firebase Storage → stamps/ folder..."
echo ""

UPLOADED=0
FAILED=0

# Upload each image
find "$IMAGES_FOLDER" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | while read IMAGE_PATH; do
    FILENAME=$(basename "$IMAGE_PATH")
    
    # Upload to Firebase Storage
    if firebase storage:upload "$IMAGE_PATH" "stamps/$FILENAME" --project default 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Uploaded: $FILENAME"
        UPLOADED=$((UPLOADED + 1))
    else
        echo -e "  ${RED}✗${NC} Failed: $FILENAME"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "=============================================="
echo -e "${GREEN}✅ Upload complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Go to Firebase Console → Storage → stamps/"
echo "2. Click each image to get its download URL"
echo "3. Add the URL to your stamps.json:"
echo "   \"imageUrl\": \"https://firebasestorage.googleapis.com/.../stamps%2Fyour-image.jpg?alt=media\""
echo "4. Run: node upload_stamps_to_firestore.js"
echo ""
echo "💡 TIP: You can use this URL format:"
echo "   https://firebasestorage.googleapis.com/v0/b/YOUR-PROJECT.appspot.com/o/stamps%2FFILENAME.jpg?alt=media"
echo ""

