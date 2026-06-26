# Universal Media Extractor

A minimalistic macOS app for downloading media from YouTube, TikTok, Instagram, Twitter, SoundCloud, Spotify, and more — plus batch-extracting media URLs from CSV files.

![macOS](https://img.shields.io/badge/macOS-14.0+-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)

## Features

- **Link Downloader** — Paste any media URL, pick format/quality, download. Supports YouTube, TikTok, Instagram, Twitter, SoundCloud, RedNote, Spotify
- **Ad-Free Preview** — Preview videos inline without ads (uses youtube-nocookie embed for YouTube)
- **CSV Batch Extractor** — Drop CSV files, auto-detect media URLs, download hundreds of files at once with high concurrency
- **Account Connections** — Log into platforms via in-app browser, cookies stored securely in macOS Keychain
- **Authenticated Downloads** — Use saved cookies for downloading private/restricted content
- **AES-256-GCM Encryption** — Optionally encrypt downloaded files with a password
- **ZIP Export** — Package your downloads into a ZIP archive
- **Platform Detection** — Auto-detects platform from URL with visual badge
- **Cancel / Retry** — Cancel in-progress downloads or retry failed ones
- **Download Speed Warnings** — Tells you before starting if a download might take a while
- **Logs** — Full activity log with filtering

## Requirements

- macOS 14.0 (Sonoma) or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for video/audio downloads:
  ```bash
  brew install yt-dlp
  ```

## Quick Start

### Option 1: Download the pre-built app

1. Go to [Releases](../../releases) and download `MediaExtractor.zip`
2. Unzip and drag `Media Extractor.app` to your Applications folder
3. Right-click → Open (first launch only, since it's not notarized)

### Option 2: Build from source

```bash
git clone https://github.com/wfrae/MediaExtractor.git
cd MediaExtractor
chmod +x build.sh
./build.sh
open "build/Media Extractor.app"
```

That's it — no Xcode project needed. The build script compiles the single Swift file and assembles the `.app` bundle.

## Project Structure

```
MediaExtractor/
├── MediaExtractor.swift   # Entire app (single file)
├── build.sh               # Build script (compiles + bundles)
├── Info.plist              # App bundle metadata
├── AppIcon.icns            # App icon
├── icon.svg                # Icon source
└── README.md
```

## How It Works

The app is a single-file SwiftUI application compiled directly with `swiftc` — no Xcode project, no package manager. It uses:

- **SwiftUI** for the interface
- **WebKit** for in-app browser, preview, and cookie capture
- **Security framework** for Keychain cookie storage
- **CryptoKit** for AES-256-GCM file encryption
- **yt-dlp** (external) for video/audio downloading
- **URLSession** for direct HTTP file downloads (CSV extractor)

## Creating a DMG for Distribution

```bash
# After building:
mkdir -p dmg_staging
cp -R "build/Media Extractor.app" dmg_staging/
ln -s /Applications dmg_staging/Applications
hdiutil create -volname "Media Extractor" -srcfolder dmg_staging \
  -ov -format UDZO "MediaExtractor-v2.0.dmg"
rm -rf dmg_staging
```

## Gatekeeper Note

Since the app is ad-hoc signed (not notarized through Apple), macOS will block it on first launch. Users need to:
1. Right-click the app → Open → Click "Open" in the dialog
2. Or: System Settings → Privacy & Security → scroll down → click "Open Anyway"

To properly sign for distribution, you'd need an Apple Developer account ($99/year).

## License

MIT
