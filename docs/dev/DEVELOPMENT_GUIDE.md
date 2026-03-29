# MiddleOut 开发指南

> 本文档总结 V1 开发过程中踩过的坑、架构设计决策，以及后续扩展新格式（Word、Excel、PPT、Markdown 等）的实施路径。

## 目录

1. [项目架构概览](#项目架构概览)
2. [核心处理流程](#核心处理流程)
3. [踩坑记录与避坑指南](#踩坑记录与避坑指南)
4. [打包与分发流程](#打包与分发流程)
5. [扩展新格式指南](#扩展新格式指南)

---

## 项目架构概览

```
MiddleOut/
├── App/                    # 应用入口与生命周期
│   ├── main.swift          # NSApplication 启动
│   ├── AppDelegate.swift   # 热键监听、窗口管理
│   └── SettingsWindowController.swift
├── Core/                   # 核心处理逻辑
│   ├── HotkeyManager.swift       # 全局快捷键 (KeyboardShortcuts SPM)
│   ├── FinderBridge.swift         # AppleScript 获取 Finder 选中文件
│   ├── FileRouter.swift           # 文件分类路由 (按扩展名)
│   ├── OutputNamer.swift          # 输出文件命名 (_opt.jpg, _pages/)
│   ├── ProcessingCoordinator.swift # 处理流程编排
│   ├── ImageProcessor.swift       # 图片→JPEG (ImageIO)
│   └── PDFProcessor.swift         # PDF→JPEG (PDFKit + ImageIO)
├── Panel/                  # 浮动进度面板 (AppKit)
│   ├── ProgressPanel.swift        # NSPanel 管理
│   └── ProgressViewController.swift
├── UI/                     # 设置界面 (SwiftUI)
│   ├── SettingsView.swift
│   ├── GeneralTab.swift
│   ├── AboutTab.swift
│   └── QualityControl.swift
└── Utility/                # 工具类
    ├── SettingsStore.swift        # UserDefaults 持久化
    ├── SoundPlayer.swift          # 完成/错误提示音
    └── DebugLog.swift             # 文件日志 (调试用)
```

### 处理管线数据流

```
快捷键 → AppDelegate → ProgressPanel.show()
                      → ProcessingCoordinator.start()
                          ↓ (background queue)
                      → FinderBridge.getSelection() [AppleScript]
                      → FileRouter.classify()
                      → ImageProcessor / PDFProcessor
                      → onProgress → ProgressPanel.update() [main thread]
                      → onCompleted → ProgressPanel.showCompleted() [main thread]
```

---

## 核心处理流程

### 添加新格式的扩展点

整个处理流程有 3 个扩展点，添加新格式只需修改这 3 处：

| 扩展点 | 文件 | 说明 |
|--------|------|------|
| **1. 文件分类** | `FileRouter.swift` | 在 `classify()` 中添加新的文件类型分支 |
| **2. 处理器** | 新建 `XXXProcessor.swift` | 实现具体的转换逻辑 |
| **3. 调度** | `ProcessingCoordinator.swift` | 在处理循环中调用新处理器 |

---

## 踩坑记录与避坑指南

### 坑 1：Accessory 模式下窗口不可见

**现象**：`NSPanel` 调用了 `orderFront` 但窗口完全不显示。

**原因**：`NSApp.setActivationPolicy(.accessory)` 让 app 不出现在 Dock 和菜单栏，但同时也让 `orderFront` 失效——系统不会把非活跃 app 的窗口提到最前。

**解决方案**（`ProgressPanel.swift`）：
```swift
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
NSApp.activate(ignoringOtherApps: true)  // 关键：临时激活 app
panel.makeKeyAndOrderFront(nil)          // 用 makeKey 而不是 orderFront
```

**教训**：Accessory 模式的 app 显示任何窗口前，必须先调用 `NSApp.activate(ignoringOtherApps: true)`。

---

### 坑 2：App Sandbox 阻止 AppleScript 通信

**现象**：AppleScript 访问 Finder 报错 "Application isn't running"，禁用 Sandbox 后变成权限静默失败。

**原因**：App Sandbox 完全阻断 Apple Events；即使禁用 Sandbox，还需要声明 `com.apple.security.automation.apple-events` entitlement 和 `NSAppleEventsUsageDescription`。

**当前方案**（开发/分发阶段）：
- `MiddleOut.entitlements` 中 `com.apple.security.app-sandbox = false`
- 同时保留 `com.apple.security.automation.apple-events = true`
- Info.plist 中有 `NSAppleEventsUsageDescription` 描述

**上架 App Store 时**：必须启用 Sandbox，需要改用其他方式获取文件选择（如拖拽、Open Panel 等），而不是 AppleScript。

---

### 坑 3：AppleScript 阻塞主线程

**现象**：按下快捷键后，进度面板始终不显示，直到处理完成才闪一下然后消失。

**原因**：`FinderBridge.getSelection()` 执行 AppleScript，对于大量文件选择可能耗时 1.5-5 秒，阻塞主线程导致 UI 来不及渲染。

**解决方案**：
1. 先在主线程显示 `ProgressPanel`
2. 延迟 0.1 秒后启动 Coordinator（让面板渲染首帧）
3. Coordinator 的所有工作（包括 AppleScript）都在 `DispatchQueue` 后台队列执行
4. 所有 UI 更新通过 `DispatchQueue.main.async`（不用 sync）回到主线程

**关键代码模式**：
```swift
// AppDelegate.swift
panel.show()  // 先显示 UI
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    coordinator.start()  // 延迟启动处理
}

// ProcessingCoordinator.swift
func start() {
    queue.async { self.processOnBackground() }  // 后台执行全部逻辑
}
// 进度回调用 async，不用 sync
DispatchQueue.main.async { self.onProgress?(progress) }
```

---

### 坑 4：App Icon 在构建产物中缺失

**现象**：`xcodebuild` 构建出的 .app 文件没有图标，Info.plist 中缺少 `CFBundleIconName`。

**原因**：有两层问题。
1. 使用 Swift 脚本在 Retina 屏幕上渲染 SVG 为 PNG 时，实际像素是标称尺寸的 2 倍（如 `icon_1024x1024.png` 实际是 2048x2048 像素）
2. `actool`（Asset Catalog 编译器）检测到 PNG 实际像素与 Contents.json 声明的尺寸不匹配时，**静默跳过**该图标集，不报错也不警告

**解决方案**：
- 使用 `sips -z <width> <height>` 将所有 PNG 缩放到正确的像素尺寸
- 确保 Contents.json 包含完整的 10 个条目（5 种 size × 2 种 scale）
- 添加 `INFOPLIST_KEY_CFBundleIconName = AppIcon` 到 build settings

**验证方法**：
```bash
# 检查 PNG 实际像素
sips -g pixelWidth -g pixelHeight icon_1024x1024.png

# 手动运行 actool 检查是否生成了 icon 信息
xcrun actool --compile /tmp/test --platform macosx \
  --minimum-deployment-target 13.0 --app-icon AppIcon \
  --output-partial-info-plist /tmp/test_info.plist \
  MiddleOut/Assets.xcassets
plutil -p /tmp/test_info.plist
# 期望输出包含 CFBundleIconName 和 CFBundleIconFile
```

**macOS AppIcon.appiconset 的 Contents.json 标准格式**：
- idiom 必须是 `"mac"`
- 需要 5 种 size（16, 32, 128, 256, 512）× 2 种 scale（1x, 2x）= 10 个条目
- `512x512@2x` 的实际 PNG 尺寸必须是 1024x1024 像素

---

### 坑 5：公证 (Notarization) 失败

**现象**：提交 Apple 公证返回 `status: Invalid`。

**常见原因与修复**：

| 错误信息 | 原因 | 修复 |
|----------|------|------|
| `The signature does not include a secure timestamp` | 签名时未加时间戳 | 添加 `--timestamp` flag |
| `The executable requests the com.apple.security.get-task-allow entitlement` | 包含调试用 entitlement | 添加 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` |

**正确的构建命令**：
```bash
xcodebuild -scheme MiddleOut -configuration Release \
  -derivedDataPath build_temp \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAM_ID)" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  clean build
```

---

### 坑 6：Developer ID 证书导入

**现象**：从 Apple Developer 下载的 `.cer` 文件导入后，`security find-identity` 中看不到。

**原因**：`.cer` 只包含公钥证书，不包含私钥。代码签名需要证书+私钥的配对。

**解决方案**：将私钥和证书合并为 `.p12` 文件后导入：
```bash
# 合并（需要 -legacy 兼容 macOS 钥匙串）
openssl pkcs12 -export -inkey my_key.key -in developer.cer \
  -out developer.p12 -passout pass:"temp123" -legacy

# 导入钥匙串
security import developer.p12 -k ~/Library/Keychains/login.keychain-db \
  -P "temp123" -T /usr/bin/codesign

# 验证
security find-identity -v -p codesigning | grep "Developer ID"
```

---

## 打包与分发流程

完整的从构建到分发的命令行流程：

```bash
# 1. 构建（Developer ID 签名 + Hardened Runtime + 时间戳）
xcodebuild -scheme MiddleOut -configuration Release \
  -derivedDataPath build_temp \
  CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAM_ID)" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  clean build

# 2. 验证签名
codesign -dvvv build_temp/Build/Products/Release/MiddleOut.app

# 3. 打包为 zip 并提交公证
ditto -c -k --keepParent \
  build_temp/Build/Products/Release/MiddleOut.app /tmp/MiddleOut.zip

xcrun notarytool submit /tmp/MiddleOut.zip \
  --keychain-profile "MiddleOut" --wait

# 4. 钉入公证票据
xcrun stapler staple build_temp/Build/Products/Release/MiddleOut.app

# 5. 生成 DMG（含 Applications 快捷方式）
mkdir -p /tmp/dmg_staging
cp -R build_temp/Build/Products/Release/MiddleOut.app /tmp/dmg_staging/
ln -s /Applications /tmp/dmg_staging/Applications
hdiutil create -volname "MiddleOut" -srcfolder /tmp/dmg_staging \
  -ov -format UDZO MiddleOut.dmg

# 6. Gatekeeper 验证
spctl -a -vv build_temp/Build/Products/Release/MiddleOut.app
# 期望输出: source=Notarized Developer ID
```

**首次使用需要存储公证凭证**：
```bash
xcrun notarytool store-credentials "MiddleOut" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"
```

---

## 扩展新格式指南

### 目标格式

计划支持的新格式及转换策略：

| 格式 | 扩展名 | 转换方案 | macOS 框架 |
|------|--------|----------|-----------|
| Word | .docx | 渲染页面→截图→JPEG | NSAttributedString 或 qlmanage |
| Excel | .xlsx | 渲染页面→截图→JPEG | qlmanage / Quick Look |
| PPT | .pptx | 每页渲染→JPEG | qlmanage / Quick Look |
| Markdown | .md | 渲染 HTML→截图→JPEG | WebKit WKWebView |

### 实施步骤（以 Word 为例）

#### Step 1：FileRouter 添加新分类

```swift
// FileRouter.swift
struct ClassificationResult {
    let images: [URL]
    let pdfs: [URL]
    let documents: [URL]   // 新增
    let skipped: [(url: URL, reason: String)]
}

private static let documentExtensions: Set<String> = ["docx", "doc", "xlsx", "xls", "pptx", "ppt"]

// classify() 中添加:
} else if documentExtensions.contains(ext) {
    documents.append(url)
}
```

#### Step 2：创建 DocumentProcessor

```swift
// Core/DocumentProcessor.swift
// 方案 A：使用 qlmanage 命令行工具（简单但依赖系统 Quick Look 插件）
// 方案 B：使用 Quick Look Framework（QLThumbnailGenerator）
// 方案 C：对于 Markdown，使用 WKWebView 渲染后截图

struct DocumentProcessor {
    static func process(at url: URL, quality: Double) throws -> [ProcessingResult] {
        // 实现转换逻辑
    }
}
```

#### Step 3：ProcessingCoordinator 添加调度

```swift
// ProcessingCoordinator.swift - processOnBackground() 中
let classified = FileRouter.classify(urls)
let allProcessable = classified.images + classified.pdfs + classified.documents

// 处理循环中添加:
let docExts: Set<String> = ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "md"]
if docExts.contains(ext) {
    let results = try DocumentProcessor.process(at: url, quality: quality)
    for result in results { totalBytesSaved += result.bytesSaved }
    convertedCount += 1
}
```

### 各格式技术方案详解

#### Word / Excel / PPT — 方案 A：qlmanage（推荐起步方案）

```swift
// 使用 macOS 自带的 qlmanage 生成缩略图/预览
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
process.arguments = ["-t", "-s", "2048", "-o", outputDir, inputPath]
try process.run()
process.waitUntilExit()
```

**优点**：实现简单，支持系统已安装 Quick Look 插件的所有格式。
**缺点**：只能生成单页缩略图；Office 多页文档只拿到第一页。

#### Word / Excel / PPT — 方案 B：NSWorkspace + PDF 中转

如果用户安装了 Microsoft Office 或 LibreOffice，可以通过 AppleScript 驱动 Office 导出 PDF，再用现有的 `PDFProcessor` 处理：

```swift
// 1. 通过 AppleScript 让 Office 导出 PDF
// 2. 用 PDFProcessor 处理 PDF → JPEG
// 3. 删除临时 PDF
```

**优点**：可以获取所有页面，保真度最高。
**缺点**：依赖用户安装 Office。

#### Markdown — WKWebView 离屏渲染

```swift
import WebKit

// 1. 读取 .md 文件内容
// 2. 用 markdown 库（或简单的正则）转换为 HTML
// 3. 用 WKWebView 加载 HTML
// 4. 等待加载完成后截图：
webView.takeSnapshot(with: config) { image, error in
    // 将 NSImage 转为 JPEG
}
```

**注意**：WKWebView 必须在主线程操作，需要用 `DispatchSemaphore` 或 async/await 与后台处理队列协调。

### 扩展时的注意事项

1. **线程安全**：所有新 Processor 必须能在后台队列运行。如果某个框架要求主线程（如 WKWebView），需要用 `DispatchQueue.main.async` + 信号量或 continuation 来桥接。

2. **输出命名**：在 `OutputNamer.swift` 中为新格式添加对应的命名方法。多页文档建议参考 PDF 的做法（创建 `name_pages/` 文件夹）。

3. **错误处理**：参考 `ImageProcessorError` / `PDFProcessorError` 的模式，创建对应的 Error enum 并实现 `LocalizedError`。

4. **测试**：参考 `ImageProcessorTests.swift` / `PDFProcessorTests.swift`，为新 Processor 编写单元测试。

5. **App Sandbox**：如果将来上架 App Store 需要启用 Sandbox，使用 `qlmanage` 和 AppleScript 驱动 Office 的方案将不可用，需要改用纯框架方案。

---

## 调试技巧

### DebugLog 文件日志

由于 app 运行在 accessory 模式（没有 Dock 图标），很难通过 Xcode 控制台查看日志。`DebugLog` 将日志写入项目目录下的 `debug.log` 文件：

```swift
DebugLog.log("some message")  // 自动记录时间戳、线程、函数名、行号
DebugLog.clear()              // 清空日志文件
```

日志位置：`/Users/konghai/Code_local/Project/MiddleOut/debug.log`

### 常用调试命令

```bash
# 实时查看日志
tail -f debug.log

# 检查签名
codesign -dvvv MiddleOut.app

# 检查 entitlements
codesign -d --entitlements - MiddleOut.app

# 检查 Asset Catalog 内容
xcrun assetutil --info MiddleOut.app/Contents/Resources/Assets.car

# 检查 Info.plist
plutil -p MiddleOut.app/Contents/Info.plist

# Gatekeeper 验证
spctl -a -vv MiddleOut.app
```
