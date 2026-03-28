# MiddleOut V1.0 Design Spec

## Overview

MiddleOut is a lightweight macOS background utility that converts and compresses images/PDFs to JPG via a single global hotkey. Named after the fictional compression algorithm from HBO's *Silicon Valley*.

**Target:** macOS 13.0+
**Tech Stack:** Swift 5.9+, AppKit (lifecycle) + SwiftUI (settings UI), MVVM
**Distribution:** Open source (GitHub) + paid on Mac App Store

## Product Requirements

### Core Interaction Model

- App runs as an invisible background agent — no Dock icon, no Menu Bar icon
- User selects files in Finder, presses `Ctrl + Option + J` (customizable)
- MiddleOut processes all supported files, shows a floating progress panel, plays a completion sound
- Relaunching the app (e.g. from Launchpad) opens the settings window; closing the window hides it without quitting

### Supported Formats

| Input | Output |
|-------|--------|
| .heic, .png, .tiff, .webp, .jpg | Single `originalName_opt.jpg` in same directory |
| .pdf | Folder `originalName_pages/` containing `page_1.jpg`, `page_2.jpg`... |
| Anything else | Skipped with reason shown in progress panel |

### File Type Validation

Extension is used for initial routing, but the real type is verified by attempting to open the file with `CGImageSource` (images) or `PDFDocument` (PDFs). If the content doesn't match, the file is skipped with "corrupted or mismatched format". The app never crashes on bad input.

### Output Naming

- Images: `originalName_opt.jpg` in the same directory as the source
- PDFs: `originalName_pages/page_1.jpg`, `page_2.jpg`... in the same directory as the source
- If `_opt.jpg` already exists: increment to `_opt_2.jpg`, `_opt_3.jpg`...
- Original files are never modified or deleted

### JPEG Quality

- Default: 80% (High)
- Configurable via slider (0-100%) with three preset buttons:
  - Low: 40%
  - Medium: 60%
  - High: 80% (default, highlighted)
- Clicking a preset moves the slider; dragging the slider deselects presets if value doesn't match a preset

### Batch & Mixed Selection

- Multiple files processed sequentially in a single batch
- Mixed selection (images + PDFs + unsupported) is handled: supported files are processed, unsupported files are skipped
- JPG files are also processed (re-compressed at the current quality setting)

## Architecture

### Approach: AppKit-driven lifecycle + SwiftUI settings

AppDelegate owns the app lifecycle for full control over agent mode, window management, and relaunch detection. SwiftUI is used only for rendering the settings view inside an AppKit-managed NSWindow.

### Modules

| Module | Framework | Responsibility |
|--------|-----------|----------------|
| **AppDelegate** | AppKit | App lifecycle, agent mode (LSUIElement), relaunch detection, window show/hide |
| **HotkeyManager** | KeyboardShortcuts (SPM) | Register and listen for the global hotkey, fire processing callback |
| **FinderBridge** | NSAppleScript | Execute AppleScript to get currently selected file URLs from Finder |
| **FileRouter** | Foundation | Classify files by extension, dispatch to ImageProcessor or PDFProcessor, collect skip list |
| **ImageProcessor** | ImageIO, UniformTypeIdentifiers | Validate image via CGImageSource, convert to JPG with quality parameter via CGImageDestination |
| **PDFProcessor** | PDFKit, ImageIO | Validate via PDFDocument, render each page to CGImage, export as JPG via CGImageDestination |
| **ProgressPanel** | AppKit (NSPanel) | Floating progress window: current file, progress bar, space saved, skip details, auto-dismiss |
| **SoundPlayer** | NSSound | Play completion chime (bundled custom sound, not configurable) |
| **SettingsWindowController** | AppKit (NSWindowController) | Manage the settings NSWindow lifecycle: create, show, hide on close |
| **SettingsView** | SwiftUI | Settings UI: hotkey binding, quality slider + presets, launch at login toggle, about tab |
| **SettingsStore** | @AppStorage / UserDefaults | Persist: JPEG quality (Double), launch-at-login state |

### Data Flow

```
User presses Ctrl+Option+J
    |
    v
HotkeyManager fires callback
    |
    v
FinderBridge.getSelection() -> [URL]
    |
    +--> empty? -> play error sound, done
    |
    v
FileRouter.classify([URL]) -> (images: [URL], pdfs: [URL], skipped: [(URL, reason)])
    |
    +--> all skipped? -> show panel "No supported files", auto-dismiss
    |
    v
ProgressPanel.show(totalCount)
    |
    v
Background queue: for each file sequentially:
    |
    +--> ImageProcessor.process(url, quality) or PDFProcessor.process(url, quality)
    |       |
    |       +--> validate content (magic bytes)
    |       |       +--> invalid? -> skip "corrupted or mismatched format"
    |       |
    |       +--> convert/compress -> write output
    |       |       +--> write failed? -> skip "cannot write output"
    |       |
    |       +--> return (outputURL, bytesSaved)
    |
    +--> Main thread: ProgressPanel.update(current, total, bytesSaved)
    |
    v
ProgressPanel.showCompleted(summary)
SoundPlayer.playCompletionSound()
    |
    v
Auto-dismiss after 2 seconds
```

### External Dependencies

| Dependency | Purpose | Integration |
|------------|---------|-------------|
| [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration and settings UI widget | Swift Package Manager |

All other functionality uses Apple's native frameworks (ImageIO, PDFKit, AppKit, SwiftUI). No other third-party dependencies.

## UI Design

### Settings Window

- **Size:** ~400x350pt, fixed, centered on screen
- **Tabs:** General, About
- **Close behavior:** Hides the window, app continues running in background
- **Only way to quit:** "Quit MiddleOut" button in General tab

#### General Tab

1. **Global Shortcut** — KeyboardShortcuts recorder widget showing current binding (default `^ ⌥ J`), click to rebind
2. **JPEG Quality** — Three preset buttons (Low 40% / Medium 60% / High 80%) + slider (0-100%), linked
3. **Launch at Login** — Toggle switch, backed by SMAppService.mainApp
4. **Quit MiddleOut** — Red-tinted button at the bottom, calls NSApplication.shared.terminate

#### About Tab

- App icon + "MiddleOut" + version number
- One-line description
- Links: GitHub Repository, Report an Issue
- Easter egg: "Inspired by the Middle-Out algorithm from HBO's *Silicon Valley*"

### Progress Panel

- **Type:** NSPanel with .floating level, no title bar buttons, non-resizable
- **Size:** ~360x160pt
- **Position:** Screen top-center
- **No Dock icon** generated by this panel

#### Processing State

- App icon (32px) + "MiddleOut" + "Processing N files..."
- Current file: "Converting: filename.heic -> filename_opt.jpg"
- Progress bar (X of N)
- Running total: "Saved X.X MB"

#### Completed State (auto-dismiss after 2 seconds)

- Green checkmark + "Done!" + "N files processed"
- Full green progress bar
- Summary: "X converted · Y skipped" + "Total saved: X.X MB"
- Skipped files listed in amber/yellow (if any)
- Completion sound plays at this transition

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Finder not frontmost / no file selected | Play a short error sound. No panel appears. |
| All selected files are unsupported formats | Panel shows "No supported files in selection", auto-dismiss. |
| File extension faked (content doesn't match) | CGImageSource/PDFDocument fails to open -> skip with "corrupted or mismatched format" |
| File locked / no read permission | Skip with "cannot read file" |
| Output write fails (sandbox / disk full) | Skip with "cannot write output" |
| Output filename already exists | Append incrementing number: `_opt_2.jpg`, `_opt_3.jpg`... |
| AppleScript permission denied by user | Show one-time alert: "MiddleOut needs Automation permission for Finder" with button to open System Settings > Privacy & Security > Automation |

**Core principle: never crash, never block. Every error is a graceful "skip" with a human-readable reason.**

## App Sandbox & Permissions

For Mac App Store distribution:

- **App Sandbox:** Enabled
- **File Access:** Read/Write for User Selected Files. Output writes to the same directory as the source file (sandbox implicit permission for sibling writes, or Security-Scoped Bookmarks if needed).
- **Apple Events:** `com.apple.security.temporary-exception.apple-events` targeting `com.apple.finder` for AppleScript access to Finder selection.
- **Launch at Login:** SMAppService.mainApp (macOS 13+), no helper app needed.
- **Info.plist:** `LSUIElement = YES` to hide from Dock and application switcher.

## Implementation Phases

1. **Skeleton** — Xcode project, agent mode, AppDelegate, settings window show/hide on relaunch
2. **Hotkey** — Integrate KeyboardShortcuts, wire up to trigger callback, settings UI for rebinding
3. **Finder Bridge** — AppleScript to get Finder selection, permission handling
4. **Processing Core** — ImageProcessor (ImageIO), PDFProcessor (PDFKit), FileRouter
5. **Progress & Sound** — NSPanel progress UI, completion sound, auto-dismiss
6. **Settings UI** — Quality slider + presets, launch at login toggle, about tab
7. **Polish & Sandbox** — Entitlements, sandbox testing, error edge cases, output naming conflicts
