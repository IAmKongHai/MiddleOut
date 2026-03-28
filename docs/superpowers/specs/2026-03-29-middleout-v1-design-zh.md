# MiddleOut V1.0 设计规格书

## 概述

MiddleOut 是一款轻量级 macOS 后台工具，通过一个全局快捷键即可将图片/PDF 转换并压缩为 JPG。名称致敬 HBO 美剧《硅谷》中虚构的 Middle-Out 压缩算法。

**目标系统：** macOS 13.0+
**技术栈：** Swift 5.9+，AppKit（生命周期管理）+ SwiftUI（设置界面），MVVM 架构
**发布方式：** GitHub 开源 + Mac App Store 付费上架

## 产品需求

### 核心交互模型

- App 以不可见的后台 Agent 运行 — 无 Dock 图标，无 Menu Bar 图标
- 用户在 Finder 中选中文件，按下 `Ctrl + Option + J`（可自定义）
- MiddleOut 处理所有支持的文件，显示浮动进度条面板，完成后播放提示音
- 重新启动 App（如从 Launchpad 点击）会打开设置窗口；关闭窗口只是隐藏，不会退出程序

### 支持的格式

| 输入格式 | 输出格式 |
|---------|---------|
| .heic, .png, .tiff, .webp, .jpg | 同目录下生成 `原文件名_opt.jpg` |
| .pdf | 同目录下创建 `原文件名_pages/` 文件夹，内含 `原文件名_page_1.jpg`, `原文件名_page_2.jpg`... |
| 其他格式 | 跳过，并在进度面板中显示原因 |

### 文件类型验证

扩展名仅用于初步分类路由，真实类型通过尝试用 `CGImageSource`（图片）或 `PDFDocument`（PDF）打开文件来验证。如果文件内容与扩展名不匹配，该文件将被跳过并提示"文件损坏或格式不匹配"。App 绝不会因为错误输入而崩溃。

### 输出文件命名

- 图片：`原文件名_opt.jpg`，保存在源文件同目录下
- PDF：`原文件名_pages/原文件名_page_1.jpg`, `原文件名_page_2.jpg`...，保存在源文件同目录下
- 如果 `_opt.jpg` 已存在：递增编号为 `_opt_2.jpg`, `_opt_3.jpg`...
- 原始文件永远不会被修改或删除

### JPEG 压缩质量

- 默认值：80%（高质量）
- 通过滑动条（0-100%）配合三个预设按钮进行调节：
  - 低质量：40%
  - 中等质量：60%
  - 高质量：80%（默认，高亮显示）
- 点击预设按钮联动滑动条；拖动滑动条到非预设值时取消预设按钮的高亮

### 批量与混合选择

- 多个文件在同一批次中按顺序处理
- 混合选择（图片 + PDF + 不支持的格式）可正常处理：支持的文件被处理，不支持的文件被跳过
- JPG 文件也会被处理（按当前质量设置重新压缩）

## 系统架构

### 方案：AppKit 驱动生命周期 + SwiftUI 设置界面

AppDelegate 掌控 App 生命周期，以实现对 Agent 模式、窗口管理和重新启动检测的完全控制。SwiftUI 仅用于在 AppKit 管理的 NSWindow 中渲染设置界面。

### 模块划分

| 模块 | 框架 | 职责 |
|------|------|------|
| **AppDelegate** | AppKit | App 生命周期、Agent 模式（LSUIElement）、重新启动检测、窗口显示/隐藏 |
| **HotkeyManager** | KeyboardShortcuts (SPM) | 注册和监听全局快捷键，触发处理回调 |
| **FinderBridge** | NSAppleScript | 执行 AppleScript 获取 Finder 当前选中文件的 URL 列表 |
| **FileRouter** | Foundation | 按扩展名分类文件，分发给 ImageProcessor 或 PDFProcessor，收集跳过列表 |
| **ImageProcessor** | ImageIO, UniformTypeIdentifiers | 通过 CGImageSource 验证图片，使用 CGImageDestination 按质量参数转换为 JPG |
| **PDFProcessor** | PDFKit, ImageIO | 通过 PDFDocument 验证，逐页渲染为 CGImage，通过 CGImageDestination 导出为 JPG |
| **ProgressPanel** | AppKit (NSPanel) | 浮动进度窗口：当前文件、进度条、已节省空间、跳过详情、自动消失 |
| **SoundPlayer** | NSSound | 播放完成提示音（内置自定义音效，不可配置） |
| **SettingsWindowController** | AppKit (NSWindowController) | 管理设置窗口的 NSWindow 生命周期：创建、显示、关闭时隐藏 |
| **SettingsView** | SwiftUI | 设置界面：快捷键绑定、质量滑动条+预设、开机自启开关、关于页面 |
| **SettingsStore** | @AppStorage / UserDefaults | 持久化存储：JPEG 质量（Double）、开机自启状态 |

### 数据流

```
用户按下 Ctrl+Option+J
    |
    v
HotkeyManager 触发回调
    |
    v
FinderBridge.getSelection() -> [URL]
    |
    +--> 为空？-> 播放错误提示音，结束
    |
    v
FileRouter.classify([URL]) -> (images: [URL], pdfs: [URL], skipped: [(URL, reason)])
    |
    +--> 全部跳过？-> 面板显示"选中的文件中没有支持的格式"，自动消失
    |
    v
ProgressPanel.show(totalCount)
    |
    v
后台队列：逐文件顺序处理：
    |
    +--> ImageProcessor.process(url, quality) 或 PDFProcessor.process(url, quality)
    |       |
    |       +--> 验证文件内容（magic bytes）
    |       |       +--> 无效？-> 跳过，提示"文件损坏或格式不匹配"
    |       |
    |       +--> 转换/压缩 -> 写入输出文件
    |       |       +--> 写入失败？-> 跳过，提示"无法写入输出文件"
    |       |
    |       +--> 返回 (outputURL, bytesSaved)
    |
    +--> 主线程：ProgressPanel.update(current, total, bytesSaved)
    |
    v
ProgressPanel.showCompleted(summary)
SoundPlayer.playCompletionSound()
    |
    v
2 秒后自动消失
```

### 外部依赖

| 依赖 | 用途 | 集成方式 |
|------|------|---------|
| [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 全局快捷键注册和设置界面录入控件 | Swift Package Manager |

其余所有功能均使用 Apple 原生框架（ImageIO、PDFKit、AppKit、SwiftUI），无其他第三方依赖。

## 界面设计

> **可视化 Mockup：** 交互式 HTML mockup 文件保存在 [`mockups/`](mockups/) 目录中，开发时请在浏览器中打开作为还原参考：
> - [架构概览](mockups/architecture.html)
> - [设置窗口](mockups/settings-window.html)
> - [进度面板](mockups/progress-panel.html)

### 设置窗口

- **尺寸：** 约 400x350pt，固定大小，屏幕居中
- **标签页：** General（通用）、About（关于）
- **关闭行为：** 隐藏窗口，App 继续在后台运行
- **退出方式：** 仅通过 General 标签页中的"Quit MiddleOut"按钮

#### General 标签页

1. **Global Shortcut（全局快捷键）** — KeyboardShortcuts 录入控件，显示当前绑定（默认 `^ ⌥ J`），点击可重新绑定
2. **JPEG Quality（压缩质量）** — 三个预设按钮（Low 40% / Medium 60% / High 80%）+ 滑动条（0-100%），联动
3. **Launch at Login（开机自启）** — 开关，基于 SMAppService.mainApp
4. **Quit MiddleOut（退出）** — 红色按钮，调用 NSApplication.shared.terminate

#### About 标签页

- App 图标 + "MiddleOut" + 版本号
- 一句话简介
- 链接：GitHub 仓库、提交 Issue
- 彩蛋："Inspired by the Middle-Out algorithm from HBO's *Silicon Valley*"

### 进度面板

- **类型：** NSPanel，.floating 层级，无标题栏按钮，不可调整大小
- **尺寸：** 约 360x160pt
- **位置：** 屏幕顶部居中
- 该面板不会产生 Dock 图标

#### 处理中状态

- App 图标（32px）+ "MiddleOut" + "Processing N files..."
- 当前文件："Converting: filename.heic -> filename_opt.jpg"
- 进度条（X of N）
- 已节省空间："Saved X.X MB"

#### 完成状态（2 秒后自动消失）

- 绿色对勾 + "Done!" + "N files processed"
- 进度条满格变绿
- 摘要："X converted · Y skipped" + "Total saved: X.X MB"
- 跳过的文件以黄色/琥珀色列出（如果有）
- 此时播放完成提示音

## 错误处理

| 场景 | 行为 |
|------|------|
| Finder 不在前台 / 未选中文件 | 播放短促错误提示音，不弹出面板 |
| 选中的文件全部是不支持的格式 | 面板显示"选中的文件中没有支持的格式"，自动消失 |
| 文件扩展名伪造（内容与扩展名不匹配） | CGImageSource/PDFDocument 无法打开 -> 跳过，提示"文件损坏或格式不匹配" |
| 文件被锁定 / 无读取权限 | 跳过，提示"无法读取文件" |
| 输出写入失败（沙盒限制 / 磁盘已满） | 跳过，提示"无法写入输出文件" |
| 输出文件名已存在 | 递增编号：`_opt_2.jpg`, `_opt_3.jpg`... |
| AppleScript 权限被用户拒绝 | 弹出一次性提示框："MiddleOut 需要 Finder 的自动化权限"，附带按钮跳转到 系统设置 > 隐私与安全性 > 自动化 |

**核心原则：永不崩溃，永不阻塞。每个错误都是一次优雅的"跳过"，附带人类可读的原因说明。**

## 沙盒与权限配置

为满足 Mac App Store 上架要求：

- **App Sandbox：** 启用
- **文件访问：** User Selected File 读写权限。输出文件写入源文件同目录（利用沙盒对同级目录写入的隐式权限，必要时使用 Security-Scoped Bookmarks）
- **Apple Events：** 添加 `com.apple.security.temporary-exception.apple-events` 权限，目标为 `com.apple.finder`，用于 AppleScript 访问 Finder 选中文件
- **开机自启：** SMAppService.mainApp（macOS 13+），无需 Helper App
- **Info.plist：** `LSUIElement = YES`，隐藏 Dock 图标和应用切换器中的显示

## 实施阶段

1. **骨架搭建** — Xcode 项目、Agent 模式、AppDelegate、重新启动时显示/隐藏设置窗口
2. **快捷键绑定** — 集成 KeyboardShortcuts，连接触发回调，设置界面中的快捷键录入控件
3. **Finder 桥接** — AppleScript 获取 Finder 选中文件，权限处理
4. **处理核心** — ImageProcessor（ImageIO）、PDFProcessor（PDFKit）、FileRouter
5. **进度与音效** — NSPanel 进度面板、完成提示音、自动消失
6. **设置界面** — 质量滑动条+预设按钮、开机自启开关、关于页面
7. **打磨与沙盒** — Entitlements 配置、沙盒测试、错误边界情况、输出命名冲突处理
