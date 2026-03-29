# MiddleOut

**[简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md)**

**A lightweight macOS utility that converts and compresses images & PDFs to JPG instantly — triggered by a single global hotkey.**

No window to open. No drag-and-drop. Just select files in Finder, press a hotkey, and done.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://github.com/IAmKongHai/MiddleOut/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## The Problem

You AirDrop a photo from iPhone to Mac — it's a 5MB HEIC file. You need to upload it to a website, but:

- The site doesn't support HEIC format
- The file is too large to upload
- You have to open an app, import, convert, export, then find the file...

**Every. Single. Time.**

macOS has built-in Quick Actions and Shortcuts that can do this, but they're buried in menus and require manual configuration. What if you could just press one key?

## The Solution

MiddleOut runs silently in the background. When you need to convert files:

1. Select files in Finder
2. Press `Ctrl + Option + J`
3. That's it. Converted files appear right next to the originals.

A floating progress panel shows real-time status — then disappears automatically.

## Features

- **Global Hotkey** — Works from anywhere, no need to switch apps. Default: `Ctrl + Option + J` (customizable)
- **Image Conversion** — HEIC, PNG, TIFF, WebP to compressed JPG
- **PDF to JPG** — Extracts every page as a separate JPG image
- **Batch Processing** — Select 1 or 1000 files, press the hotkey
- **Adjustable Quality** — Slider from 0% to 100% JPEG quality
- **Non-destructive** — Original files are never modified. Output files are named `filename_opt.jpg`
- **Zero UI Friction** — No Dock icon, no menu bar clutter. Just a hotkey and a progress panel.

## Supported Formats

| Input Format | Output | Notes |
|---|---|---|
| HEIC / HEIF | JPG | iPhone photos, Apple Live Photos stills |
| PNG | JPG | Screenshots, web graphics |
| TIFF | JPG | Scanned documents, print graphics |
| WebP | JPG | Web images |
| JPG / JPEG | JPG | Re-compressed at your chosen quality |
| PDF | JPG (per page) | Each page exported as a separate image |

## Roadmap

Planned formats for future versions:

| Format | Status |
|---|---|
| Word (.docx) | Planned |
| Excel (.xlsx) | Planned |
| PowerPoint (.pptx) | Planned |
| Markdown (.md) | Planned |

## Installation

### Download (Recommended)

Download the latest `.dmg` from [Releases](https://github.com/IAmKongHai/MiddleOut/releases), open it, and drag MiddleOut to your Applications folder.

The app is signed with a Developer ID certificate and notarized by Apple — no Gatekeeper warnings.

### Build from Source

```bash
git clone https://github.com/IAmKongHai/MiddleOut.git
cd MiddleOut
open MiddleOut.xcodeproj
```

Build and run in Xcode. Requires macOS 13.0+ and Xcode 15+.

## Usage

### First Launch

1. Open MiddleOut — the Settings window appears
2. Grant **Accessibility** permission when prompted (required for global hotkey)
3. Grant **Automation > Finder** permission when prompted (required to read file selection)
4. Customize the hotkey and JPEG quality if you want
5. Close the Settings window — MiddleOut keeps running in the background

### Daily Use

1. Select one or more files in Finder
2. Press `Ctrl + Option + J` (or your custom hotkey)
3. A floating progress panel appears at the top of your screen
4. Converted files appear in the same directory as the originals
5. The panel auto-dismisses after 3 seconds

### Output Naming

| Input | Output |
|---|---|
| `photo.heic` | `photo_opt.jpg` |
| `screenshot.png` | `screenshot_opt.jpg` |
| `document.pdf` (3 pages) | `document_pages/document_page_1.jpg`, `document_page_2.jpg`, `document_page_3.jpg` |

If `photo_opt.jpg` already exists, MiddleOut creates `photo_opt_2.jpg`, `photo_opt_3.jpg`, etc.

### Settings

To reopen the Settings window, launch MiddleOut again (double-click in Applications or Spotlight).

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** AppKit (app shell & progress panel) + SwiftUI (settings window)
- **Image Processing:** ImageIO framework (native, no third-party dependencies)
- **PDF Processing:** PDFKit framework
- **Hotkey:** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- **Target:** macOS 13.0 Ventura and later

## Architecture

```
Hotkey Press
    |
    v
AppDelegate ──> ProgressPanel.show()
    |
    v (background queue)
FinderBridge ──> AppleScript ──> Finder selection [URL]
    |
    v
FileRouter ──> classify by extension
    |
    v
ImageProcessor / PDFProcessor ──> output _opt.jpg
    |
    v (main thread)
ProgressPanel ──> update / complete / auto-dismiss
```

All processing runs on a background queue. The main thread stays free for smooth UI updates.

## Contributing

Contributions are welcome! Whether it's bug fixes, new format support, or UI improvements.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/word-support`)
3. Commit your changes
4. Open a Pull Request

See [DEVELOPMENT_GUIDE.md](docs/dev/DEVELOPMENT_GUIDE.md) for architecture details, pitfall notes, and how to add new format support.

## Why "MiddleOut"?

The name is a nod to the fictional **Middle-Out compression algorithm** from HBO's *Silicon Valley* — the algorithm that achieved a Weissman Score so high it changed the world. While this app won't reach those mythical compression ratios, it does make your files smaller with a single keystroke.

## License

MIT License. See [LICENSE](LICENSE) for details.

---

**MiddleOut** — Convert and compress images on macOS with a single hotkey. HEIC to JPG, PNG to JPG, PDF to JPG. Fast, lightweight, open source.
