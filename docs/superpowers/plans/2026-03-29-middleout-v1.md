# MiddleOut V1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS background utility that converts and compresses images/PDFs to JPG via a single global hotkey.

**Architecture:** AppKit-driven lifecycle (AppDelegate) with SwiftUI for the settings view only. The app runs as an invisible agent (LSUIElement), with no Dock or Menu Bar presence. A floating NSPanel serves as the progress indicator during processing.

**Tech Stack:** Swift 5.9+, macOS 13.0+, AppKit, SwiftUI, ImageIO, PDFKit, KeyboardShortcuts (SPM)

**Design Spec:** `docs/superpowers/specs/2026-03-29-middleout-v1-design.md`
**UI Mockups:** `docs/superpowers/specs/mockups/` (open in browser for visual reference)

---

## File Structure

```
MiddleOut/
├── MiddleOut.xcodeproj
├── MiddleOut/
│   ├── App/
│   │   ├── main.swift                    # App entry point (NSApplication bootstrap)
│   │   ├── AppDelegate.swift             # Lifecycle, agent mode, relaunch detection
│   │   └── SettingsWindowController.swift # NSWindowController for settings window
│   ├── Core/
│   │   ├── HotkeyManager.swift           # Global hotkey registration & callback
│   │   ├── FinderBridge.swift            # AppleScript to get Finder selection
│   │   ├── FileRouter.swift              # Classify files, dispatch to processors
│   │   ├── ImageProcessor.swift          # Image -> JPG conversion & compression
│   │   ├── PDFProcessor.swift            # PDF -> JPG pages extraction
│   │   ├── OutputNamer.swift             # Generate unique output file names
│   │   └── ProcessingCoordinator.swift   # Orchestrate the full pipeline
│   ├── UI/
│   │   ├── SettingsView.swift            # SwiftUI settings (General + About tabs)
│   │   ├── GeneralTab.swift              # Hotkey, quality, login toggle, quit
│   │   ├── AboutTab.swift                # Version, links, easter egg
│   │   └── QualityControl.swift          # Slider + preset buttons component
│   ├── Panel/
│   │   ├── ProgressPanel.swift           # NSPanel floating progress window
│   │   └── ProgressViewController.swift  # NSViewController hosting progress UI
│   ├── Utility/
│   │   ├── SoundPlayer.swift             # Completion & error sounds
│   │   └── SettingsStore.swift           # @AppStorage / UserDefaults wrapper
│   ├── Resources/
│   │   ├── Assets.xcassets               # App icon
│   │   └── Sounds/
│   │       ├── complete.aiff             # Completion chime
│   │       └── error.aiff                # Error sound
│   ├── Info.plist
│   └── MiddleOut.entitlements
├── MiddleOutTests/
│   ├── FileRouterTests.swift
│   ├── ImageProcessorTests.swift
│   ├── PDFProcessorTests.swift
│   ├── OutputNamerTests.swift
│   └── TestResources/
│       ├── sample.heic
│       ├── sample.png
│       ├── sample.jpg
│       ├── sample.tiff
│       ├── sample.webp
│       ├── sample.pdf (2-page)
│       └── fake.heic (a .txt renamed to .heic)
└── Package Dependencies (SPM)
    └── sindresorhus/KeyboardShortcuts
```

---

## Task 1: Xcode Project Skeleton & Agent Mode

**Files:**
- Create: `MiddleOut/App/main.swift`
- Create: `MiddleOut/App/AppDelegate.swift`
- Modify: `Info.plist` (add LSUIElement)
- Modify: `MiddleOut.entitlements` (sandbox + Apple Events)

- [ ] **Step 1: Create Xcode project**

Create a new macOS App project in Xcode:
- Product Name: `MiddleOut`
- Team: your Apple Developer account
- Organization Identifier: your reverse-domain (e.g. `com.yourname`)
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: macOS 13.0

Delete the auto-generated `ContentView.swift` and `MiddleOutApp.swift` — we'll replace them with our own entry point.

- [ ] **Step 2: Create main.swift entry point**

Delete `MiddleOutApp.swift` and create `MiddleOut/App/main.swift`:

```swift
// main.swift
// MiddleOut - App entry point
// Uses NSApplication directly for full AppKit lifecycle control.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create AppDelegate with agent mode and relaunch detection**

Create `MiddleOut/App/AppDelegate.swift`:

```swift
// AppDelegate.swift
// Manages app lifecycle: agent mode (no Dock/MenuBar), relaunch detection,
// and settings window show/hide.

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (redundant with Info.plist, but ensures it at runtime)
        NSApp.setActivationPolicy(.accessory)

        // Show settings window on first launch so user can configure hotkey
        showSettingsWindow()
    }

    /// Called when user relaunches the app (e.g. clicks icon in Launchpad)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    /// Prevent app from quitting when last window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 4: Create placeholder SettingsWindowController**

Create `MiddleOut/App/SettingsWindowController.swift`:

```swift
// SettingsWindowController.swift
// Manages the NSWindow that hosts the SwiftUI SettingsView.
// Closing the window hides it instead of destroying it.

import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiddleOut Settings"
        window.center()
        window.isReleasedWhenClosed = false
        // Placeholder: will be replaced with SwiftUI SettingsView in Task 8
        window.contentView = NSHostingView(rootView: Text("Settings placeholder"))

        self.init(window: window)
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // Just hide — app continues running in background
    }
}
```

- [ ] **Step 5: Configure Info.plist for agent mode**

Add to `Info.plist`:

```xml
<key>LSUIElement</key>
<true/>
```

This hides the app from the Dock and the Cmd+Tab application switcher.

- [ ] **Step 6: Configure entitlements for sandbox and Apple Events**

Edit `MiddleOut.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.temporary-exception.apple-events</key>
    <array>
        <string>com.apple.finder</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 7: Build and run to verify**

Run: `Cmd + R` in Xcode

Expected:
- App does NOT appear in Dock
- A window titled "MiddleOut Settings" with placeholder text appears
- Closing the window does NOT quit the app (verify via Activity Monitor)
- Reopening the app from Launchpad shows the settings window again

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: scaffold Xcode project with agent mode and settings window lifecycle"
```

---

## Task 2: Settings Store

**Files:**
- Create: `MiddleOut/Utility/SettingsStore.swift`

- [ ] **Step 1: Create SettingsStore**

Create `MiddleOut/Utility/SettingsStore.swift`:

```swift
// SettingsStore.swift
// Centralized persistence for user preferences using UserDefaults.
// Provides a single source of truth for all configurable settings.

import Foundation
import ServiceManagement

class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    /// JPEG compression quality (0.0 to 1.0). Default: 0.8 (High)
    @Published var jpegQuality: Double {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: "jpegQuality") }
    }

    /// Whether the app should launch at login
    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = !launchAtLogin
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard

        // Load persisted quality or use default 0.8
        if defaults.object(forKey: "jpegQuality") != nil {
            self.jpegQuality = defaults.double(forKey: "jpegQuality")
        } else {
            self.jpegQuality = 0.8
        }

        // Read current launch-at-login state from system
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run: `Cmd + B` in Xcode
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add MiddleOut/Utility/SettingsStore.swift
git commit -m "feat: add SettingsStore with JPEG quality and launch-at-login persistence"
```

---

## Task 3: KeyboardShortcuts Integration & HotkeyManager

**Files:**
- Create: `MiddleOut/Core/HotkeyManager.swift`
- Modify: `MiddleOut/App/AppDelegate.swift`

- [ ] **Step 1: Add KeyboardShortcuts via SPM**

In Xcode: File → Add Package Dependencies...
- URL: `https://github.com/sindresorhus/KeyboardShortcuts`
- Dependency Rule: Up to Next Major Version
- Add to target: MiddleOut

- [ ] **Step 2: Create HotkeyManager**

Create `MiddleOut/Core/HotkeyManager.swift`:

```swift
// HotkeyManager.swift
// Registers a global keyboard shortcut and fires a callback when pressed.
// Uses KeyboardShortcuts library for Mac App Store-compatible hotkey handling.

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let processFiles = Self("processFiles")
}

class HotkeyManager {

    static let shared = HotkeyManager()
    var onHotkeyPressed: (() -> Void)?

    private init() {}

    /// Start listening for the global hotkey
    func start() {
        KeyboardShortcuts.onKeyUp(for: .processFiles) { [weak self] in
            self?.onHotkeyPressed?()
        }
    }
}
```

- [ ] **Step 3: Wire HotkeyManager into AppDelegate**

Update `AppDelegate.applicationDidFinishLaunching`:

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    // Start listening for global hotkey
    HotkeyManager.shared.onHotkeyPressed = { [weak self] in
        self?.handleHotkeyPressed()
    }
    HotkeyManager.shared.start()

    showSettingsWindow()
}

/// Entry point when user presses the global hotkey
private func handleHotkeyPressed() {
    // TODO: Will be wired to ProcessingCoordinator in Task 7
    print("[MiddleOut] Hotkey pressed!")
}
```

Add `import KeyboardShortcuts` at the top of AppDelegate.swift.

- [ ] **Step 4: Build and run to verify**

Run: `Cmd + R` in Xcode
Expected: BUILD SUCCEEDED. The shortcut isn't bound yet (user must set it in settings), but the listener is active.

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/HotkeyManager.swift MiddleOut/App/AppDelegate.swift
git commit -m "feat: add HotkeyManager with KeyboardShortcuts integration"
```

---

## Task 4: FinderBridge

**Files:**
- Create: `MiddleOut/Core/FinderBridge.swift`

- [ ] **Step 1: Create FinderBridge**

Create `MiddleOut/Core/FinderBridge.swift`:

```swift
// FinderBridge.swift
// Executes AppleScript to retrieve the currently selected file URLs from Finder.
// Returns an empty array if Finder is not frontmost or nothing is selected.

import AppKit

enum FinderBridgeError: Error {
    case scriptFailed(String)
    case permissionDenied
}

struct FinderBridge {

    /// Get the currently selected file URLs from Finder.
    /// Returns an empty array if nothing is selected or Finder is not active.
    static func getSelection() throws -> [URL] {
        let script = """
        tell application "Finder"
            set theSelection to selection
            if theSelection is {} then
                return {}
            end if
            set thePaths to {}
            repeat with theItem in theSelection
                set end of thePaths to POSIX path of (theItem as alias)
            end repeat
            return thePaths
        end tell
        """

        let appleScript = NSAppleScript(source: script)!
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 = user denied permission
            if errorNumber == -1743 {
                throw FinderBridgeError.permissionDenied
            }
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw FinderBridgeError.scriptFailed(message)
        }

        // Parse result: can be a single string or a list of strings
        var urls: [URL] = []
        let count = result.numberOfItems
        if count == 0 {
            // Single item or empty
            if let path = result.stringValue, !path.isEmpty {
                urls.append(URL(fileURLWithPath: path))
            }
        } else {
            for i in 1...count {
                if let item = result.atIndex(i), let path = item.stringValue {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
        }

        return urls
    }
}
```

- [ ] **Step 2: Quick test in AppDelegate**

Temporarily update `handleHotkeyPressed` in AppDelegate to test:

```swift
private func handleHotkeyPressed() {
    do {
        let urls = try FinderBridge.getSelection()
        print("[MiddleOut] Selected \(urls.count) files:")
        for url in urls {
            print("  - \(url.path)")
        }
    } catch FinderBridgeError.permissionDenied {
        print("[MiddleOut] Permission denied - need Automation access for Finder")
    } catch {
        print("[MiddleOut] Error: \(error)")
    }
}
```

- [ ] **Step 3: Build, run, and manually verify**

Run: `Cmd + R`
1. Open Finder, select some files
2. Set a keyboard shortcut in MiddleOut settings (once the settings UI is built — for now, set it programmatically or skip manual test)
3. Press the shortcut
4. Check Xcode console for printed file paths

Note: macOS will prompt for Automation permission on first AppleScript execution. Grant it.

- [ ] **Step 4: Commit**

```bash
git add MiddleOut/Core/FinderBridge.swift MiddleOut/App/AppDelegate.swift
git commit -m "feat: add FinderBridge to get Finder selection via AppleScript"
```

---

## Task 5: OutputNamer & FileRouter

**Files:**
- Create: `MiddleOut/Core/OutputNamer.swift`
- Create: `MiddleOut/Core/FileRouter.swift`
- Create: `MiddleOutTests/OutputNamerTests.swift`
- Create: `MiddleOutTests/FileRouterTests.swift`

- [ ] **Step 1: Write OutputNamer tests**

Create `MiddleOutTests/OutputNamerTests.swift`:

```swift
import XCTest
@testable import MiddleOut

final class OutputNamerTests: XCTestCase {

    func testImageOutputName() {
        let input = URL(fileURLWithPath: "/Users/test/photo.heic")
        let output = OutputNamer.imageOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "photo_opt.jpg")
        XCTAssertEqual(output.deletingLastPathComponent().path, "/Users/test")
    }

    func testImageOutputNameForJPG() {
        let input = URL(fileURLWithPath: "/Users/test/photo.jpg")
        let output = OutputNamer.imageOutputURL(for: input)
        XCTAssertEqual(output.lastPathComponent, "photo_opt.jpg")
    }

    func testPDFOutputFolder() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let folder = OutputNamer.pdfOutputFolderURL(for: input)
        XCTAssertEqual(folder.lastPathComponent, "report_pages")
        XCTAssertEqual(folder.deletingLastPathComponent().path, "/Users/test")
    }

    func testPDFPageName() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let page = OutputNamer.pdfPageURL(for: input, pageIndex: 0)
        XCTAssertEqual(page.lastPathComponent, "report_page_1.jpg")
    }

    func testPDFPageNameMultiDigit() {
        let input = URL(fileURLWithPath: "/Users/test/report.pdf")
        let page = OutputNamer.pdfPageURL(for: input, pageIndex: 9)
        XCTAssertEqual(page.lastPathComponent, "report_page_10.jpg")
    }

    func testUniqueURL_noConflict() {
        // When no file exists at the path, return as-is
        let url = URL(fileURLWithPath: "/tmp/middleout_test_noconflict_\(UUID().uuidString).jpg")
        let result = OutputNamer.uniqueURL(for: url)
        XCTAssertEqual(result, url)
    }

    func testUniqueURL_withConflict() throws {
        // Create a file to force a conflict
        let dir = FileManager.default.temporaryDirectory
        let base = dir.appendingPathComponent("conflict_test_opt.jpg")
        try Data().write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }

        let result = OutputNamer.uniqueURL(for: base)
        XCTAssertEqual(result.lastPathComponent, "conflict_test_opt_2.jpg")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Cmd + U` in Xcode (or `xcodebuild test`)
Expected: Compilation error — `OutputNamer` doesn't exist yet.

- [ ] **Step 3: Implement OutputNamer**

Create `MiddleOut/Core/OutputNamer.swift`:

```swift
// OutputNamer.swift
// Generates unique output file names for processed files.
// Handles image _opt.jpg naming, PDF folder/page naming, and conflict resolution.

import Foundation

struct OutputNamer {

    /// Generate output URL for an image: same directory, `name_opt.jpg`
    static func imageOutputURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        let output = dir.appendingPathComponent("\(name)_opt.jpg")
        return uniqueURL(for: output)
    }

    /// Generate the output folder URL for a PDF: same directory, `name_pages/`
    static func pdfOutputFolderURL(for input: URL) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let dir = input.deletingLastPathComponent()
        return dir.appendingPathComponent("\(name)_pages")
    }

    /// Generate a page URL inside the PDF output folder: `name_page_N.jpg`
    static func pdfPageURL(for input: URL, pageIndex: Int) -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let folder = pdfOutputFolderURL(for: input)
        return folder.appendingPathComponent("\(name)_page_\(pageIndex + 1).jpg")
    }

    /// If a file already exists at the URL, append an incrementing number.
    /// `photo_opt.jpg` -> `photo_opt_2.jpg` -> `photo_opt_3.jpg`
    static func uniqueURL(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let baseName = url.deletingPathExtension().lastPathComponent

        var counter = 2
        while true {
            let candidate = dir.appendingPathComponent("\(baseName)_\(counter).\(ext)")
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
}
```

- [ ] **Step 4: Run OutputNamer tests**

Run: `Cmd + U`
Expected: All OutputNamerTests pass.

- [ ] **Step 5: Write FileRouter tests**

Create `MiddleOutTests/FileRouterTests.swift`:

```swift
import XCTest
@testable import MiddleOut

final class FileRouterTests: XCTestCase {

    func testClassifyImages() {
        let urls = [
            URL(fileURLWithPath: "/test/a.heic"),
            URL(fileURLWithPath: "/test/b.png"),
            URL(fileURLWithPath: "/test/c.tiff"),
            URL(fileURLWithPath: "/test/d.webp"),
            URL(fileURLWithPath: "/test/e.jpg"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 5)
        XCTAssertEqual(result.pdfs.count, 0)
        XCTAssertEqual(result.skipped.count, 0)
    }

    func testClassifyPDF() {
        let urls = [URL(fileURLWithPath: "/test/doc.pdf")]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 0)
        XCTAssertEqual(result.pdfs.count, 1)
    }

    func testClassifyMixed() {
        let urls = [
            URL(fileURLWithPath: "/test/a.heic"),
            URL(fileURLWithPath: "/test/b.pdf"),
            URL(fileURLWithPath: "/test/c.docx"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.pdfs.count, 1)
        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertEqual(result.skipped[0].reason, "unsupported format")
    }

    func testClassifyCaseInsensitive() {
        let urls = [
            URL(fileURLWithPath: "/test/photo.HEIC"),
            URL(fileURLWithPath: "/test/doc.PDF"),
        ]
        let result = FileRouter.classify(urls)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.pdfs.count, 1)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `Cmd + U`
Expected: Compilation error — `FileRouter` doesn't exist yet.

- [ ] **Step 7: Implement FileRouter**

Create `MiddleOut/Core/FileRouter.swift`:

```swift
// FileRouter.swift
// Classifies files by extension and dispatches to the correct processor.
// Case-insensitive extension matching.

import Foundation

struct FileRouter {

    struct ClassificationResult {
        let images: [URL]
        let pdfs: [URL]
        let skipped: [(url: URL, reason: String)]
    }

    private static let imageExtensions: Set<String> = ["heic", "png", "tiff", "webp", "jpg", "jpeg"]
    private static let pdfExtensions: Set<String> = ["pdf"]

    /// Classify a list of URLs into images, PDFs, and skipped files.
    static func classify(_ urls: [URL]) -> ClassificationResult {
        var images: [URL] = []
        var pdfs: [URL] = []
        var skipped: [(url: URL, reason: String)] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                images.append(url)
            } else if pdfExtensions.contains(ext) {
                pdfs.append(url)
            } else {
                skipped.append((url: url, reason: "unsupported format"))
            }
        }

        return ClassificationResult(images: images, pdfs: pdfs, skipped: skipped)
    }
}
```

- [ ] **Step 8: Run all tests**

Run: `Cmd + U`
Expected: All FileRouterTests and OutputNamerTests pass.

- [ ] **Step 9: Commit**

```bash
git add MiddleOut/Core/OutputNamer.swift MiddleOut/Core/FileRouter.swift \
       MiddleOutTests/OutputNamerTests.swift MiddleOutTests/FileRouterTests.swift
git commit -m "feat: add FileRouter and OutputNamer with tests"
```

---

## Task 6: ImageProcessor & PDFProcessor

**Files:**
- Create: `MiddleOut/Core/ImageProcessor.swift`
- Create: `MiddleOut/Core/PDFProcessor.swift`
- Create: `MiddleOutTests/ImageProcessorTests.swift`
- Create: `MiddleOutTests/PDFProcessorTests.swift`
- Create: `MiddleOutTests/TestResources/` (test fixture files)

- [ ] **Step 1: Prepare test resource files**

Create `MiddleOutTests/TestResources/` directory.

Add test images to the test target:
- Create a small PNG programmatically in tests (avoids binary fixtures in git for basic cases)
- For HEIC/TIFF/WebP, add real sample files to the directory and include them in the test target's "Copy Bundle Resources" build phase
- Create `fake.heic`: a plain text file renamed to `.heic` to test extension-faking

For the simplest approach, we'll generate test images in code and use a minimal PDF.

- [ ] **Step 2: Write ImageProcessor tests**

Create `MiddleOutTests/ImageProcessorTests.swift`:

```swift
import XCTest
import AppKit
@testable import MiddleOut

final class ImageProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiddleOutTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Helper: create a PNG file at the given URL
    private func createTestPNG(at url: URL, width: Int = 100, height: Int = 100) throws {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG")
            return
        }
        try pngData.write(to: url)
    }

    func testProcessPNG() throws {
        let input = tempDir.appendingPathComponent("test.png")
        try createTestPNG(at: input)

        let result = try ImageProcessor.process(at: input, quality: 0.8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertEqual(result.outputURL.pathExtension, "jpg")
        XCTAssertTrue(result.outputURL.lastPathComponent.contains("_opt"))
    }

    func testProcessJPG_recompresses() throws {
        // Create a PNG, then convert it to JPG manually, then re-process
        let pngURL = tempDir.appendingPathComponent("test_src.png")
        try createTestPNG(at: pngURL)

        let jpgInput = tempDir.appendingPathComponent("photo.jpg")
        let image = NSImage(contentsOf: pngURL)!
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 1.0]) else {
            XCTFail("Failed to create JPG")
            return
        }
        try jpgData.write(to: jpgInput)

        let result = try ImageProcessor.process(at: jpgInput, quality: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        // Re-compressed file should be smaller than the original at quality 1.0
        let inputSize = try FileManager.default.attributesOfItem(atPath: jpgInput.path)[.size] as! UInt64
        let outputSize = try FileManager.default.attributesOfItem(atPath: result.outputURL.path)[.size] as! UInt64
        XCTAssertLessThan(outputSize, inputSize)
    }

    func testProcessFakeHEIC_throws() throws {
        let fakeFile = tempDir.appendingPathComponent("fake.heic")
        try "this is not an image".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try ImageProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case ImageProcessorError.invalidImage = error else {
                XCTFail("Expected invalidImage error, got \(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `Cmd + U`
Expected: Compilation error — `ImageProcessor` doesn't exist yet.

- [ ] **Step 4: Implement ImageProcessor**

Create `MiddleOut/Core/ImageProcessor.swift`:

```swift
// ImageProcessor.swift
// Converts supported image formats to compressed JPEG using ImageIO.
// Validates file content via CGImageSource before processing.

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessorError: Error, LocalizedError {
    case invalidImage
    case cannotCreateDestination
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "corrupted or mismatched format"
        case .cannotCreateDestination: return "cannot create output file"
        case .writeFailed: return "cannot write output"
        }
    }
}

struct ProcessingResult {
    let outputURL: URL
    let inputSize: UInt64
    let outputSize: UInt64
    var bytesSaved: Int64 { Int64(inputSize) - Int64(outputSize) }
}

struct ImageProcessor {

    /// Convert an image file to compressed JPEG.
    /// Validates the file content before processing — throws if content is not a valid image.
    static func process(at url: URL, quality: Double) throws -> ProcessingResult {
        // Validate: try to create an image source from the file
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageProcessorError.invalidImage
        }

        let outputURL = OutputNamer.imageOutputURL(for: url)

        // Create JPEG destination
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageProcessorError.cannotCreateDestination
        }

        // Set compression quality
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageProcessorError.writeFailed
        }

        // Calculate sizes
        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let outputSize = (try fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0

        return ProcessingResult(outputURL: outputURL, inputSize: inputSize, outputSize: outputSize)
    }
}
```

- [ ] **Step 5: Run ImageProcessor tests**

Run: `Cmd + U`
Expected: All ImageProcessorTests pass.

- [ ] **Step 6: Write PDFProcessor tests**

Create `MiddleOutTests/PDFProcessorTests.swift`:

```swift
import XCTest
import PDFKit
@testable import MiddleOut

final class PDFProcessorTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiddleOutTests_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    /// Helper: create a minimal 2-page PDF
    private func createTestPDF(at url: URL) throws {
        let pdfDoc = PDFDocument()

        for i in 0..<2 {
            let page = PDFPage()
            // PDFPage() creates a blank US Letter page
            pdfDoc.insert(page, at: i)
        }

        guard pdfDoc.write(to: url) else {
            XCTFail("Failed to create test PDF")
            return
        }
    }

    func testProcessPDF_createsFolder() throws {
        let input = tempDir.appendingPathComponent("report.pdf")
        try createTestPDF(at: input)

        let results = try PDFProcessor.process(at: input, quality: 0.8)

        // Should create 2 page images
        XCTAssertEqual(results.count, 2)

        // Verify folder exists
        let folderURL = OutputNamer.pdfOutputFolderURL(for: input)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify page file names
        XCTAssertEqual(results[0].outputURL.lastPathComponent, "report_page_1.jpg")
        XCTAssertEqual(results[1].outputURL.lastPathComponent, "report_page_2.jpg")
    }

    func testProcessFakePDF_throws() throws {
        let fakeFile = tempDir.appendingPathComponent("fake.pdf")
        try "not a pdf".data(using: .utf8)!.write(to: fakeFile)

        XCTAssertThrowsError(try PDFProcessor.process(at: fakeFile, quality: 0.8)) { error in
            guard case PDFProcessorError.invalidPDF = error else {
                XCTFail("Expected invalidPDF error, got \(error)")
                return
            }
        }
    }
}
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `Cmd + U`
Expected: Compilation error — `PDFProcessor` doesn't exist yet.

- [ ] **Step 8: Implement PDFProcessor**

Create `MiddleOut/Core/PDFProcessor.swift`:

```swift
// PDFProcessor.swift
// Extracts each page from a PDF and renders it as a compressed JPEG.
// Uses PDFKit for rendering and ImageIO for JPEG output.

import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

enum PDFProcessorError: Error, LocalizedError {
    case invalidPDF
    case pageRenderFailed(Int)
    case cannotCreateDestination(Int)
    case writeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "corrupted or mismatched format"
        case .pageRenderFailed(let i): return "failed to render page \(i + 1)"
        case .cannotCreateDestination(let i): return "cannot create output for page \(i + 1)"
        case .writeFailed(let i): return "cannot write page \(i + 1)"
        }
    }
}

struct PDFProcessor {

    /// Process a PDF file: extract each page as a JPEG image.
    /// Returns one ProcessingResult per page.
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            throw PDFProcessorError.invalidPDF
        }

        let fm = FileManager.default
        let inputSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let inputSizePerPage = inputSize / UInt64(document.pageCount)

        // Create output folder
        let folderURL = OutputNamer.pdfOutputFolderURL(for: url)
        try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var results: [ProcessingResult] = []

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else {
                throw PDFProcessorError.pageRenderFailed(i)
            }

            // Render page at 2x scale for good quality (144 DPI)
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = Int(bounds.width * scale)
            let height = Int(bounds.height * scale)

            guard let cgImage = page.thumbnail(of: CGSize(width: width, height: height), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw PDFProcessorError.pageRenderFailed(i)
            }

            let outputURL = OutputNamer.pdfPageURL(for: url, pageIndex: i)

            guard let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw PDFProcessorError.cannotCreateDestination(i)
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw PDFProcessorError.writeFailed(i)
            }

            let outputSize = (try fm.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64) ?? 0
            results.append(ProcessingResult(
                outputURL: outputURL,
                inputSize: inputSizePerPage,
                outputSize: outputSize
            ))
        }

        return results
    }
}
```

- [ ] **Step 9: Run all tests**

Run: `Cmd + U`
Expected: All tests pass (OutputNamerTests, FileRouterTests, ImageProcessorTests, PDFProcessorTests).

- [ ] **Step 10: Commit**

```bash
git add MiddleOut/Core/ImageProcessor.swift MiddleOut/Core/PDFProcessor.swift \
       MiddleOutTests/ImageProcessorTests.swift MiddleOutTests/PDFProcessorTests.swift
git commit -m "feat: add ImageProcessor and PDFProcessor with tests"
```

---

## Task 7: ProcessingCoordinator & SoundPlayer

**Files:**
- Create: `MiddleOut/Core/ProcessingCoordinator.swift`
- Create: `MiddleOut/Utility/SoundPlayer.swift`
- Modify: `MiddleOut/App/AppDelegate.swift`

- [ ] **Step 1: Create SoundPlayer**

Create `MiddleOut/Utility/SoundPlayer.swift`:

```swift
// SoundPlayer.swift
// Plays completion and error sounds.
// Uses bundled custom sounds. Falls back to system sounds if custom not found.

import AppKit

struct SoundPlayer {

    /// Play the completion chime (after successful processing)
    static func playComplete() {
        if let sound = NSSound(named: "complete") {
            sound.play()
        } else {
            // Fallback to system sound
            NSSound.beep()
        }
    }

    /// Play an error sound (when no files selected or all skipped)
    static func playError() {
        if let sound = NSSound(named: "error") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
```

Note: For V1, we use system beep as fallback. Custom `.aiff` sound files can be added to `Resources/Sounds/` later and included in the bundle's Copy Resources phase. Just name them `complete.aiff` and `error.aiff`.

- [ ] **Step 2: Create ProcessingCoordinator**

Create `MiddleOut/Core/ProcessingCoordinator.swift`:

```swift
// ProcessingCoordinator.swift
// Orchestrates the full processing pipeline:
// Finder selection -> FileRouter -> Processors -> Progress updates -> Sound
// All processing runs on a background queue; UI updates dispatch to main.

import Foundation

/// Progress callback data
struct ProcessingProgress {
    let currentFile: String
    let currentIndex: Int
    let totalCount: Int
    let bytesSaved: Int64
}

/// Final summary data
struct ProcessingSummary {
    let convertedCount: Int
    let skippedFiles: [(name: String, reason: String)]
    let totalBytesSaved: Int64
}

class ProcessingCoordinator {

    static let shared = ProcessingCoordinator()

    private let queue = DispatchQueue(label: "com.middleout.processing", qos: .userInitiated)
    private(set) var isProcessing = false

    /// Callbacks for UI updates (called on main thread)
    var onProgress: ((ProcessingProgress) -> Void)?
    var onCompleted: ((ProcessingSummary) -> Void)?
    var onError: ((String) -> Void)?

    private init() {}

    /// Start processing: get Finder selection and process all supported files.
    func start() {
        guard !isProcessing else { return }
        isProcessing = true

        // Get Finder selection on main thread (AppleScript)
        let urls: [URL]
        do {
            urls = try FinderBridge.getSelection()
        } catch FinderBridgeError.permissionDenied {
            isProcessing = false
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
            return
        } catch {
            isProcessing = false
            SoundPlayer.playError()
            return
        }

        guard !urls.isEmpty else {
            isProcessing = false
            SoundPlayer.playError()
            return
        }

        // Classify files
        let classified = FileRouter.classify(urls)
        let allProcessable = classified.images + classified.pdfs
        var allSkipped = classified.skipped.map { ($0.url.lastPathComponent, $0.reason) }

        guard !allProcessable.isEmpty else {
            isProcessing = false
            DispatchQueue.main.async {
                self.onCompleted?(ProcessingSummary(
                    convertedCount: 0,
                    skippedFiles: allSkipped,
                    totalBytesSaved: 0
                ))
            }
            SoundPlayer.playError()
            return
        }

        let totalCount = allProcessable.count
        let quality = SettingsStore.shared.jpegQuality

        // Process on background queue
        queue.async { [weak self] in
            guard let self else { return }

            var convertedCount = 0
            var totalBytesSaved: Int64 = 0

            for (index, url) in allProcessable.enumerated() {
                let fileName = url.lastPathComponent

                // Update progress on main thread
                DispatchQueue.main.async {
                    self.onProgress?(ProcessingProgress(
                        currentFile: fileName,
                        currentIndex: index,
                        totalCount: totalCount,
                        bytesSaved: totalBytesSaved
                    ))
                }

                let ext = url.pathExtension.lowercased()
                let isPDF = (ext == "pdf")

                do {
                    if isPDF {
                        let results = try PDFProcessor.process(at: url, quality: quality)
                        for result in results {
                            totalBytesSaved += result.bytesSaved
                        }
                        convertedCount += 1
                    } else {
                        let result = try ImageProcessor.process(at: url, quality: quality)
                        totalBytesSaved += result.bytesSaved
                        convertedCount += 1
                    }
                } catch {
                    let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    allSkipped.append((fileName, reason))
                }
            }

            let summary = ProcessingSummary(
                convertedCount: convertedCount,
                skippedFiles: allSkipped,
                totalBytesSaved: totalBytesSaved
            )

            DispatchQueue.main.async {
                self.isProcessing = false
                self.onCompleted?(summary)
                SoundPlayer.playComplete()
            }
        }
    }

    /// Show a one-time alert for Automation permission
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "MiddleOut Needs Permission"
        alert.informativeText = "MiddleOut needs Automation permission for Finder to read your file selection. Please grant access in System Settings > Privacy & Security > Automation."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
        isProcessing = false
    }
}
```

- [ ] **Step 3: Wire ProcessingCoordinator into AppDelegate**

Update `handleHotkeyPressed` in `AppDelegate.swift`:

```swift
private func handleHotkeyPressed() {
    // TODO: Wire to ProgressPanel in Task 8
    ProcessingCoordinator.shared.onCompleted = { summary in
        print("[MiddleOut] Done! \(summary.convertedCount) converted, \(summary.skippedFiles.count) skipped, saved \(summary.totalBytesSaved) bytes")
    }
    ProcessingCoordinator.shared.start()
}
```

- [ ] **Step 4: Build and run**

Run: `Cmd + R`
Expected: BUILD SUCCEEDED. When hotkey is pressed with files selected in Finder, console should print processing results.

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Core/ProcessingCoordinator.swift MiddleOut/Utility/SoundPlayer.swift \
       MiddleOut/App/AppDelegate.swift
git commit -m "feat: add ProcessingCoordinator to orchestrate full pipeline and SoundPlayer"
```

---

## Task 8: ProgressPanel

**Files:**
- Create: `MiddleOut/Panel/ProgressPanel.swift`
- Create: `MiddleOut/Panel/ProgressViewController.swift`
- Modify: `MiddleOut/App/AppDelegate.swift`

- [ ] **Step 1: Create ProgressViewController**

Create `MiddleOut/Panel/ProgressViewController.swift`:

```swift
// ProgressViewController.swift
// NSViewController hosting the progress UI inside the floating panel.
// Manages the progress bar, current file label, and summary display.

import AppKit

class ProgressViewController: NSViewController {

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "MiddleOut")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let fileLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let leftStatLabel = NSTextField(labelWithString: "")
    private let rightStatLabel = NSTextField(labelWithString: "")
    private let skipLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        self.view = container

        // App icon
        let iconImage = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "MiddleOut")
        iconView.image = iconImage
        iconView.frame = NSRect(x: 16, y: 110, width: 32, height: 32)
        container.addSubview(iconView)

        // Title
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 56, y: 124, width: 280, height: 18)
        container.addSubview(titleLabel)

        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 56, y: 108, width: 280, height: 16)
        container.addSubview(subtitleLabel)

        // Current file
        fileLabel.font = .systemFont(ofSize: 12)
        fileLabel.textColor = .labelColor
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.frame = NSRect(x: 16, y: 82, width: 328, height: 16)
        container.addSubview(fileLabel)

        // Progress bar
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1.0
        progressBar.frame = NSRect(x: 16, y: 62, width: 328, height: 8)
        container.addSubview(progressBar)

        // Stats
        leftStatLabel.font = .systemFont(ofSize: 11)
        leftStatLabel.textColor = .secondaryLabelColor
        leftStatLabel.frame = NSRect(x: 16, y: 42, width: 200, height: 14)
        container.addSubview(leftStatLabel)

        rightStatLabel.font = .systemFont(ofSize: 11)
        rightStatLabel.textColor = .secondaryLabelColor
        rightStatLabel.alignment = .right
        rightStatLabel.frame = NSRect(x: 144, y: 42, width: 200, height: 14)
        container.addSubview(rightStatLabel)

        // Skip label (hidden by default)
        skipLabel.font = .systemFont(ofSize: 11)
        skipLabel.textColor = .systemOrange
        skipLabel.frame = NSRect(x: 16, y: 8, width: 328, height: 30)
        skipLabel.isHidden = true
        container.addSubview(skipLabel)
    }

    func updateProgress(_ progress: ProcessingProgress) {
        subtitleLabel.stringValue = "Processing \(progress.totalCount) files..."
        fileLabel.stringValue = "Converting: \(progress.currentFile)"
        progressBar.doubleValue = Double(progress.currentIndex) / Double(progress.totalCount)
        leftStatLabel.stringValue = "\(progress.currentIndex) of \(progress.totalCount) completed"
        rightStatLabel.stringValue = "Saved \(formatBytes(progress.bytesSaved))"
    }

    func showCompleted(_ summary: ProcessingSummary) {
        let iconImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
        iconView.image = iconImage
        iconView.contentTintColor = .systemGreen

        titleLabel.stringValue = "Done!"
        titleLabel.textColor = .systemGreen
        subtitleLabel.stringValue = "\(summary.convertedCount + summary.skippedFiles.count) files processed"

        fileLabel.isHidden = true
        progressBar.doubleValue = 1.0

        let skippedCount = summary.skippedFiles.count
        leftStatLabel.stringValue = "\(summary.convertedCount) converted\(skippedCount > 0 ? " · \(skippedCount) skipped" : "")"
        rightStatLabel.stringValue = "Total saved: \(formatBytes(summary.totalBytesSaved))"

        if !summary.skippedFiles.isEmpty {
            let names = summary.skippedFiles.map { "\($0.name) (\($0.reason))" }.joined(separator: ", ")
            skipLabel.stringValue = "Skipped: \(names)"
            skipLabel.isHidden = false
        }
    }

    /// Reset to initial state for reuse
    func reset() {
        let iconImage = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "MiddleOut")
        iconView.image = iconImage
        iconView.contentTintColor = .labelColor
        titleLabel.stringValue = "MiddleOut"
        titleLabel.textColor = .labelColor
        subtitleLabel.stringValue = ""
        fileLabel.stringValue = ""
        fileLabel.isHidden = false
        progressBar.doubleValue = 0
        leftStatLabel.stringValue = ""
        rightStatLabel.stringValue = ""
        skipLabel.isHidden = true
        skipLabel.stringValue = ""
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
```

- [ ] **Step 2: Create ProgressPanel**

Create `MiddleOut/Panel/ProgressPanel.swift`:

```swift
// ProgressPanel.swift
// Floating NSPanel that shows processing progress.
// Appears at screen top-center, auto-dismisses after completion.

import AppKit

class ProgressPanel {

    static let shared = ProgressPanel()

    private var panel: NSPanel?
    private var viewController: ProgressViewController?
    private var dismissTimer: Timer?

    private init() {}

    /// Show the panel and prepare for progress updates
    func show() {
        dismissTimer?.invalidate()

        if panel == nil {
            let vc = ProgressViewController()
            vc.loadView()

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titlebarAppearsTransparent = true
            panel.titleVisibility = .hidden
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentViewController = vc
            panel.backgroundColor = .windowBackgroundColor

            self.panel = panel
            self.viewController = vc
        }

        viewController?.reset()

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 180  // 360 / 2
            let y = screenFrame.maxY - 180   // near top with some margin
            panel?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel?.orderFront(nil)
    }

    /// Update progress display
    func update(_ progress: ProcessingProgress) {
        viewController?.updateProgress(progress)
    }

    /// Show completion summary, then auto-dismiss after 2 seconds
    func showCompleted(_ summary: ProcessingSummary) {
        viewController?.showCompleted(summary)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Dismiss the panel
    func dismiss() {
        dismissTimer?.invalidate()
        panel?.orderOut(nil)
    }
}
```

- [ ] **Step 3: Wire ProgressPanel into AppDelegate**

Update `handleHotkeyPressed` in `AppDelegate.swift`:

```swift
private func handleHotkeyPressed() {
    let coordinator = ProcessingCoordinator.shared
    let panel = ProgressPanel.shared

    coordinator.onProgress = { progress in
        panel.show()
        panel.update(progress)
    }

    coordinator.onCompleted = { summary in
        panel.showCompleted(summary)
    }

    coordinator.start()
}
```

- [ ] **Step 4: Build and run to verify**

Run: `Cmd + R`
Expected:
1. Select files in Finder
2. Press hotkey
3. Floating progress panel appears at top of screen
4. Shows current file being processed
5. Shows "Done!" with summary
6. Auto-dismisses after 2 seconds
7. Completion sound plays

- [ ] **Step 5: Commit**

```bash
git add MiddleOut/Panel/ MiddleOut/App/AppDelegate.swift
git commit -m "feat: add floating ProgressPanel with auto-dismiss"
```

---

## Task 9: Settings UI (General Tab + About Tab)

**Files:**
- Create: `MiddleOut/UI/SettingsView.swift`
- Create: `MiddleOut/UI/GeneralTab.swift`
- Create: `MiddleOut/UI/AboutTab.swift`
- Create: `MiddleOut/UI/QualityControl.swift`
- Modify: `MiddleOut/App/SettingsWindowController.swift`

**UI Reference:** Open `docs/superpowers/specs/mockups/settings-window.html` in a browser for the exact visual target.

- [ ] **Step 1: Create QualityControl component**

Create `MiddleOut/UI/QualityControl.swift`:

```swift
// QualityControl.swift
// Reusable SwiftUI component: JPEG quality slider + preset buttons.
// Clicking a preset moves the slider; dragging the slider deselects presets
// if the value doesn't match.

import SwiftUI

struct QualityControl: View {

    @Binding var quality: Double

    private let presets: [(label: String, value: Double)] = [
        ("Low 40%", 0.4),
        ("Medium 60%", 0.6),
        ("High 80%", 0.8),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JPEG Quality")
                .font(.headline)

            // Preset buttons
            HStack(spacing: 8) {
                ForEach(presets, id: \.value) { preset in
                    Button(preset.label) {
                        quality = preset.value
                    }
                    .buttonStyle(.bordered)
                    .tint(isActive(preset.value) ? .accentColor : nil)
                }
            }

            // Slider with percentage label
            HStack {
                Slider(value: $quality, in: 0...1, step: 0.01)
                Text("\(Int(quality * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func isActive(_ value: Double) -> Bool {
        abs(quality - value) < 0.01
    }
}
```

- [ ] **Step 2: Create GeneralTab**

Create `MiddleOut/UI/GeneralTab.swift`:

```swift
// GeneralTab.swift
// Settings General tab: hotkey binding, JPEG quality, launch at login, quit button.
// See mockups/settings-window.html for visual reference.

import SwiftUI
import KeyboardShortcuts

struct GeneralTab: View {

    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Global Shortcut
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcut")
                    .font(.headline)
                KeyboardShortcuts.Recorder("", name: .processFiles)
            }

            // JPEG Quality
            QualityControl(quality: $store.jpegQuality)

            // Launch at Login
            Toggle("Launch at Login", isOn: $store.launchAtLogin)

            Spacer()

            // Quit button
            Divider()
            Button("Quit MiddleOut") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 3: Create AboutTab**

Create `MiddleOut/UI/AboutTab.swift`:

```swift
// AboutTab.swift
// Settings About tab: app icon, version, description, links, easter egg.
// See mockups/settings-window.html for visual reference.

import SwiftUI

struct AboutTab: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // App Icon
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .resizable()
                .frame(width: 48, height: 48)
                .padding(16)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .foregroundColor(.white)

            Text("MiddleOut")
                .font(.title2.bold())

            Text("Version \(appVersion)")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("A lightweight macOS tool that instantly\nconverts and compresses images & PDFs\n— all triggered by a global hotkey.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.vertical, 4)

            // Links
            VStack(spacing: 6) {
                Link("GitHub Repository →",
                     destination: URL(string: "https://github.com/example/MiddleOut")!)
                    .font(.caption)
                Link("Report an Issue →",
                     destination: URL(string: "https://github.com/example/MiddleOut/issues")!)
                    .font(.caption)
            }

            Spacer()

            // Easter egg
            Text("Inspired by the Middle-Out algorithm\nfrom HBO's *Silicon Valley*")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary.opacity(0.6))
                .font(.system(size: 10))
                .italic()
                .padding(.bottom, 8)
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 4: Create SettingsView with tabs**

Create `MiddleOut/UI/SettingsView.swift`:

```swift
// SettingsView.swift
// Main settings view with General and About tabs.
// Hosted inside SettingsWindowController's NSWindow.

import SwiftUI

struct SettingsView: View {

    @ObservedObject var store = SettingsStore.shared

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 400, height: 350)
    }
}
```

- [ ] **Step 5: Update SettingsWindowController to use SettingsView**

In `SettingsWindowController.swift`, replace the placeholder:

```swift
convenience init() {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "MiddleOut Settings"
    window.center()
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: SettingsView())

    self.init(window: window)
    window.delegate = self
}
```

- [ ] **Step 6: Build and run to verify**

Run: `Cmd + R`
Expected:
- Settings window shows with General and About tabs
- General tab: shortcut recorder, quality slider with preset buttons, launch at login toggle, quit button
- About tab: app icon, version, description, links, easter egg text
- Clicking preset buttons moves the slider
- Shortcut recorder works (try binding Ctrl+Option+J)
- Quit button terminates the app

- [ ] **Step 7: Commit**

```bash
git add MiddleOut/UI/ MiddleOut/App/SettingsWindowController.swift
git commit -m "feat: add Settings UI with General and About tabs"
```

---

## Task 10: End-to-End Integration & Polish

**Files:**
- Modify: `MiddleOut/App/AppDelegate.swift` (final wiring)
- Verify: all modules connected

- [ ] **Step 1: Final AppDelegate wiring**

Ensure `AppDelegate.swift` has the complete, final version:

```swift
import AppKit
import KeyboardShortcuts

class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Start listening for global hotkey
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
        }
        HotkeyManager.shared.start()

        // Show settings on first launch so user can set the hotkey
        showSettingsWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        return false
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleHotkeyPressed() {
        let coordinator = ProcessingCoordinator.shared
        let panel = ProgressPanel.shared

        coordinator.onProgress = { progress in
            panel.show()
            panel.update(progress)
        }

        coordinator.onCompleted = { summary in
            panel.showCompleted(summary)
        }

        coordinator.start()
    }
}
```

- [ ] **Step 2: End-to-end manual test**

Comprehensive test checklist:

1. **Launch:** App launches with no Dock icon, settings window appears
2. **Hotkey setup:** Set shortcut to `Ctrl + Option + J` in General tab
3. **Close settings:** Click red X — app stays alive (verify in Activity Monitor)
4. **Reopen settings:** Click app in Launchpad — settings window reappears
5. **Image conversion:** Select a PNG/HEIC in Finder → press hotkey → `_opt.jpg` appears
6. **JPG re-compression:** Select a JPG → press hotkey → `_opt.jpg` appears, smaller
7. **PDF extraction:** Select a PDF → press hotkey → `_pages/` folder appears with page JPGs
8. **Mixed batch:** Select PNG + PDF + DOCX → hotkey → PNG and PDF processed, DOCX skipped with reason
9. **Fake file:** Rename a .txt to .heic → hotkey → skipped with "corrupted or mismatched format"
10. **No selection:** Press hotkey with nothing selected in Finder → error sound, no panel
11. **Quality slider:** Change quality to 40%, process image → smaller output than at 80%
12. **Duplicate names:** Process the same file twice → second output is `_opt_2.jpg`
13. **Progress panel:** Panel appears during processing, shows progress, shows "Done!", auto-dismisses
14. **Completion sound:** Sound plays when processing completes
15. **Launch at Login:** Toggle on, restart Mac → app starts automatically

- [ ] **Step 3: Fix any issues found during testing**

Address bugs discovered during manual testing.

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete end-to-end integration of MiddleOut V1.0"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Xcode project skeleton & agent mode | main.swift, AppDelegate, Info.plist, entitlements |
| 2 | Settings store (quality + login) | SettingsStore.swift |
| 3 | KeyboardShortcuts & HotkeyManager | HotkeyManager.swift |
| 4 | FinderBridge (AppleScript) | FinderBridge.swift |
| 5 | FileRouter & OutputNamer + tests | FileRouter, OutputNamer, tests |
| 6 | ImageProcessor & PDFProcessor + tests | ImageProcessor, PDFProcessor, tests |
| 7 | ProcessingCoordinator & SoundPlayer | ProcessingCoordinator, SoundPlayer |
| 8 | ProgressPanel (floating NSPanel) | ProgressPanel, ProgressViewController |
| 9 | Settings UI (General + About) | SettingsView, GeneralTab, AboutTab, QualityControl |
| 10 | End-to-end integration & polish | Final wiring, manual test checklist |
