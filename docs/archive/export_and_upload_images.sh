#!/bin/bash

# Export images from Assets.xcassets and upload to Firebase Storage
# This script handles the 6 existing stamp images

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "🖼️  Exporting & Uploading Stamp Images"
echo "======================================"
echo ""

# Create temporary directory for exported images
TEMP_DIR=$(mktemp -d)
echo "📁 Created temp directory: $TEMP_DIR"
echo ""

# Copy and rename images from Assets.xcassets
ASSETS_DIR="/Users/haoyama/Desktop/Developer/Stampbook/Stampbook/Assets.xcassets"

echo "📤 Exporting images from Assets.xcassets..."
echo ""

# Baker Beach
cp "$ASSETS_DIR/us-ca-sf-baker-beach.imageset/baker beach.png" "$TEMP_DIR/us-ca-sf-baker-beach.jpg"
echo "  ✓ Exported: us-ca-sf-baker-beach.jpg"

# Dolores Park
cp "$ASSETS_DIR/us-ca-sf-dolores-park.imageset/Dolores Park.png" "$TEMP_DIR/us-ca-sf-dolores-park.jpg"
echo "  ✓ Exported: us-ca-sf-dolores-park.jpg"

# Equator Coffee
cp "$ASSETS_DIR/us-ca-sf-equator-coffee.imageset/equator coffee.png" "$TEMP_DIR/us-ca-sf-equator-coffee.jpg"
echo "  ✓ Exported: us-ca-sf-equator-coffee.jpg"

# Ferry Building
cp "$ASSETS_DIR/us-ca-sf-ferry-building.imageset/fery.png" "$TEMP_DIR/us-ca-sf-ferry-building.jpg"
echo "  ✓ Exported: us-ca-sf-ferry-building.jpg"

# Four Barrel
cp "$ASSETS_DIR/us-ca-sf-four-barrel.imageset/four barrel.png" "$TEMP_DIR/us-ca-sf-four-barrel.jpg"
echo "  ✓ Exported: us-ca-sf-four-barrel.jpg"

# Pier 39
cp "$ASSETS_DIR/us-ca-sf-pier-39.imageset/iPhone 16 Pro - 33.png" "$TEMP_DIR/us-ca-sf-pier-39.jpg"
echo "  ✓ Exported: us-ca-sf-pier-39.jpg"

echo ""
echo -e "${GREEN}✅ Exported 6 images${NC}"
echo ""

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo -e "${YELLOW}⚠️  Firebase CLI not found!${NC}"
    echo ""
    echo "Install it with:"
    echo "  npm install -g firebase-tools"
    echo ""
    echo "Then run this script again."
    echo ""
    echo "Your exported images are in: $TEMP_DIR"
    exit 1
fi

# Upload to Firebase Storage
echo "📤 Uploading to Firebase Storage..."
echo ""

UPLOADED=0
FAILED=0

for file in "$TEMP_DIR"/*.jpg; do
    FILENAME=$(basename "$file")
    
    if firebase storage:upload "$file" "stamps/$FILENAME" --project stampbook-app 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Uploaded: $FILENAME"
        UPLOADED=$((UPLOADED + 1))
    else
        echo -e "  ${YELLOW}⚠️${NC} Failed: $FILENAME (might need to login - see below)"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "======================================"
echo -e "${GREEN}✅ Export & Upload Complete!${NC}"
echo ""
echo "Uploaded: $UPLOADED images"
if [ $FAILED -gt 0 ]; then
    echo "Failed: $FAILED images"
    echo ""
    echo "If upload failed, run:"
    echo "  firebase login"
    echo "  firebase use stampbook-app"
    echo "Then run this script again."
fi
echo ""

# Clean up
rm -rf "$TEMP_DIR"
echo "🗑️  Cleaned up temp directory"
echo ""

