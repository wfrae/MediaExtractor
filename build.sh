#!/bin/bash
set -euo pipefail

APP="Media Extractor"
BINARY="MediaExtractor"
BUILD="build"
BUNDLE="$BUILD/$APP.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "Compiling…"
swiftc -parse-as-library \
    -O \
    -framework SwiftUI \
    -framework AppKit \
    -framework UniformTypeIdentifiers \
    -framework WebKit \
    -framework Security \
    -o "$BUNDLE/Contents/MacOS/$BINARY" \
    MediaExtractor.swift

cp Info.plist "$BUNDLE/Contents/"
cp AppIcon.icns "$BUNDLE/Contents/Resources/"

codesign --force --sign - "$BUNDLE"

echo "✅  Built: $BUNDLE"
echo "   Run:  open \"$BUNDLE\""
