#!/bin/bash
set -euo pipefail

APP_NAME="Media Extractor"
DMG_NAME="MediaExtractor-v2.0"
VOL_NAME="Media Extractor"
STAGING="dmg_staging"
BG_IMG=".background/bg.png"

# Ensure app is built
if [ ! -d "build/$APP_NAME.app" ]; then
    echo "Building app first..."
    bash build.sh
fi

# Clean previous
rm -rf "$STAGING" "${DMG_NAME}.dmg" "${DMG_NAME}_rw.dmg"

# Create staging folder
mkdir -p "$STAGING/.background"

# Copy app
cp -R "build/$APP_NAME.app" "$STAGING/"

# Create Applications symlink
ln -s /Applications "$STAGING/Applications"

# Generate background image from SVG
rsvg-convert -w 660 -h 400 dmg_background.svg -o "$STAGING/.background/bg.png"

# Create a read-write DMG first
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" \
    -ov -format UDRW "${DMG_NAME}_rw.dmg"

# Mount it
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${DMG_NAME}_rw.dmg" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$VOL_NAME"

sleep 2

# Use AppleScript to set DMG window appearance
osascript <<EOF
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 760, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:bg.png"
        -- Position the app icon on the left
        set position of item "$APP_NAME.app" of container window to {165, 210}
        -- Position Applications on the right
        set position of item "Applications" of container window to {495, 210}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

# Set custom volume icon
cp AppIcon.icns "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT" 2>/dev/null || true

sync
sleep 2

# Unmount
hdiutil detach "$DEVICE" -force

# Convert to compressed read-only DMG
hdiutil convert "${DMG_NAME}_rw.dmg" -format UDZO -imagekey zlib-level=9 -o "${DMG_NAME}.dmg"

# Clean up
rm -rf "$STAGING" "${DMG_NAME}_rw.dmg"

echo ""
echo "✅  DMG created: ${DMG_NAME}.dmg"
echo "   Size: $(du -h "${DMG_NAME}.dmg" | cut -f1)"
