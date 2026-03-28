为了让 AI Coding Agent（如 Cursor 或 GitHub Copilot）能够最精准地理解并生成代码，PRD（产品需求文档）和 TDD（技术设计文档）必须保持**高度结构化、模块边界清晰、且技术栈明确**。AI 最怕模糊的描述，因此我们将采用“面向 Agent 的 Prompt 友好型”格式来撰写。

你可以直接将以下内容作为 Context 喂给你的 AI Agent。

---

### 产品需求文档 (PRD) - V1.0

**项目名称:** MiddleOut
**产品定位:** 一款运行在 macOS 的轻量级效率工具。用户在 Finder 中选中文件后，通过全局快捷键即可在后台瞬间完成图片/PDF的格式转换和压缩。
**核心目标:** 无感操作、极致速度、原生体验。

#### 1. 核心功能需求 (P0 - 必须实现)
* **F1. 全局快捷键触发:**
    * 支持用户自定义快捷键组合（例如 `Cmd + Shift + E`）。
    * 无论焦点在哪个应用，按下快捷键后，App 自动获取当前 Finder 中被选中的文件路径。
* **F2. 图片格式转换:**
    * 输入支持：`.heic`, `.png`, `.tiff`, `.webp`。
    * 输出支持：强制统一转换为 `.jpg` (JPEG)。
* **F3. 图片体积压缩:**
    * 提供固定档位的压缩率偏好设置（例如：高质量 80%，中等质量 60%，极限压缩 40%）。
* **F4. PDF 转图片:**
    * 输入支持：`.pdf`。
    * 输出支持：将 PDF 逐页提取并渲染为 `.jpg`，输出到一个以 PDF 文件名命名的新文件夹中。
* **F5. 结果反馈机制:**
    * 处理完成后，在原文件同级目录生成新文件（自动重命名，例如 `原名_opt.jpg`，避免覆盖原文件）。
    * 调用 macOS 原生通知中心，提示“处理成功：节省了 XX MB 空间”或“处理失败”。

#### 2. UI/UX 需求 (P1 - 基础界面)
* **状态栏图标 (Menu Bar Item):** 常驻顶部菜单栏，点击展开菜单。
* **菜单项包含:**
    * “偏好设置...” (Preferences...)
    * “退出” (Quit)
* **偏好设置窗口 (Settings Window):**
    * **快捷键 Tab:** 绑定和修改全局快捷键。
    * **处理选项 Tab:** 设置 JPEG 压缩质量滑动条 (0-100%)。

---

### 技术设计文档 (TDD) - V1.0

**目标受众:** AI Coding Agent
**技术栈:** Swift 5.9+, SwiftUI, macOS 13.0+
**架构模式:** MVVM

#### 1. 核心模块与系统框架依赖
* **UI 框架:** `SwiftUI` (用于偏好设置窗口) + `AppKit` (`NSStatusItem` 用于状态栏图标)。
* **文件选择引擎:** `NSAppleScript`。**（关键提示）** App Store 沙盒机制下，获取当前 Finder 选中文件的唯一合规且最稳定的方式是执行一段轻量级的 AppleScript 获取 Finder Selection。
* **图片处理引擎:** `ImageIO` 和 `UniformTypeIdentifiers`。不使用第三方库，直接使用 `CGImageDestination` 控制 JPEG 压缩质量参数 (`kCGImageDestinationLossyCompressionQuality`)。
* **PDF 处理引擎:** `PDFKit` (`PDFDocument` 和 `PDFPage`)。将 `PDFPage` 渲染为 `NSImage` 或 `CGImage` 后再通过 `ImageIO` 导出。
* **快捷键管理:** 引入开源包 `sindresorhus/KeyboardShortcuts`。它是目前 macOS Swift 开发中最稳定、最易用的全局快捷键库。

#### 2. 系统权限与沙盒配置 (App Store Requirement)
为了未来能上架 Mac App Store，必须在 Xcode 的 Signing & Capabilities 中配置：
* 开启 **App Sandbox**。
* 开启 **File Access:** User Selected File (Read/Write) 并在实际处理时可能需要申请临时安全书签 (Security Scoped Bookmarks)，或者在同级目录写入时依赖沙盒的隐式权限。
* **Apple Events:** 添加 `com.apple.security.temporary-exception.apple-events` 权限，允许向 `com.apple.finder` 发送 AppleScript 以获取选中文件。

#### 3. 核心类与数据流设计
* **`FinderSelectionManager`:** 封装 AppleScript 执行逻辑，返回 `[URL]` 数组。
* **`MediaProcessor`:** 业务核心。接收 `[URL]`，判断文件扩展名（`.heic`, `.png`, `.pdf`），分发给具体的处理函数。
    * `func processImage(at url: URL, quality: Double) throws -> URL`
    * `func processPDF(at url: URL, quality: Double) throws -> [URL]`
* **`NotificationManager`:** 封装 `UNUserNotificationCenter`，发送处理成功/失败的横幅通知。
* **`SettingsViewModel`:** 使用 `@AppStorage` 持久化存储用户的压缩质量偏好和快捷键状态。

#### 4. AI 编码执行顺序建议 (给 Agent 的 Prompt 步骤)
1.  **Phase 1: 骨架搭建。** 创建一个基于 SwiftUI 的 macOS App，隐藏 Dock 栏图标，仅在状态栏 (Menu Bar) 显示，并搭建好带 Tab 的偏好设置窗口。
2.  **Phase 2: 快捷键绑定。** 引入 `KeyboardShortcuts` 包，在偏好设置中完成 UI 绑定，并在 AppDelegate 或主体 App 结构中监听快捷键按下事件。
3.  **Phase 3: Finder 交互。** 编写并测试 `NSAppleScript` 逻辑，确保快捷键按下时，能正确打印出当前 Finder 中选中文件的绝对路径。
4.  **Phase 4: 核心算法。** 实现 `ImageIO` 转换 HEIC 到 JPEG 及体积压缩逻辑；实现 `PDFKit` 拆页逻辑。
5.  **Phase 5: 闭环与权限。** 将模块串联，处理沙盒权限导致的写入失败问题，并添加系统通知。

---

把这两份文档喂给你的 AI，它就能建立起一个非常清晰的全局上下文，避免它在开发过程中“胡思乱想”或者使用过时的 API。

如果你准备好了，需要我为你生成 **Phase 1（骨架搭建与状态栏配置）** 的第一段具体执行 Prompt 吗？我们可以直接复制给 AI 让它开始干活。