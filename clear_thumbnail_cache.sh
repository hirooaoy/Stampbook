#!/bin/bash
# Clear thumbnail cache on iOS Simulator
# Run this after changing thumbnail generation logic

SIMULATOR_DIR=~/Library/Developer/CoreSimulator/Devices
APP_BUNDLE_ID="com.stampbookapp.Stampbook"

echo "🗑️  Clearing thumbnail cache for $APP_BUNDLE_ID..."
echo ""

# Find all simulator devices
for DEVICE in "$SIMULATOR_DIR"/*/; do
    APP_DATA="$DEVICE/data/Containers/Data/Application"
    
    if [ -d "$APP_DATA" ]; then
        # Find the app's data directory
        for APP_DIR in "$APP_DATA"/*/; do
            if [ -f "$APP_DIR/.com.apple.mobile_container_manager.metadata.plist" ]; then
                BUNDLE=$(defaults read "$APP_DIR/.com.apple.mobile_container_manager.metadata.plist" MCMMetadataIdentifier 2>/dev/null)
                
                if [ "$BUNDLE" = "$APP_BUNDLE_ID" ]; then
                    DOC_DIR="$APP_DIR/Documents"
                    
                    if [ -d "$DOC_DIR" ]; then
                        echo "📂 Found app documents: $DOC_DIR"
                        
                        # Count and delete thumbnail files
                        THUMB_COUNT=$(find "$DOC_DIR" -name "*_thumb.*" -type f | wc -l | tr -d ' ')
                        
                        if [ "$THUMB_COUNT" -gt 0 ]; then
                            echo "🗑️  Deleting $THUMB_COUNT thumbnail files..."
                            find "$DOC_DIR" -name "*_thumb.*" -type f -delete
                            echo "✅ Thumbnails cleared!"
                        else
                            echo "ℹ️  No thumbnails found"
                        fi
                        
                        echo ""
                    fi
                fi
            fi
        done
    fi
done

echo "✅ Done! Restart the app to regenerate thumbnails with new logic."
