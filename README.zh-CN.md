# MiddleOut

**一款轻量级 macOS 工具，可通过全局快捷键将图片和 PDF 即时转换并压缩为 JPG。**

无需打开任何窗口，无需拖拽操作。只需在 Finder 中选中文件，按下快捷键，完成。

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://github.com/IAmKongHai/MiddleOut/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 问题所在

你用 AirDrop(隔空投送) 从 iPhone 传了一张照片到 Mac——一个 5MB 的 HEIC 文件。你需要把它上传到某个网站，但：

- 该网站不支持 HEIC 格式
- 文件太大，无法上传
- 你不得不打开一个应用，导入、转换、导出，再找到文件……

**每一次，都是这样。**

macOS 自带了"快速操作"和"快捷指令"可以处理这类任务，但它们藏在层层菜单里，还需要手动配置。如果只需按一个键呢？

## 解决方案

MiddleOut 静默运行在后台。需要转换文件时：

1. 在 Finder 中选中文件
2. 按下 `Ctrl + Option + J`
3. 就这样。转换后的文件直接出现在原文件旁边。

一个浮动进度面板会实时显示处理状态，完成后自动消失。

## 功能特性

- **全局快捷键** — 在任何应用中均可触发，无需切换。默认：`Ctrl + Option + J`（可自定义）
- **图片转换** — 将 HEIC、PNG、TIFF、WebP 转换为压缩后的 JPG（HEIC转JPG Mac 首选工具）
- **PDF 转 JPG** — 将 PDF 每一页单独导出为 JPG 图片
- **Markdown 转 JPG** — 将 .md 转换为适合移动端的 9:16 JPEG（2K 分辨率）
- **批量处理** — 选中 1 个或 1000 个文件，按下快捷键即可
- **可调节质量** — JPEG 质量滑块，范围 0% 至 100%
- **非破坏性处理** — 原始文件永远不会被修改。输出文件命名为 `文件名_opt.jpg`
- **零界面干扰** — 无 Dock 图标，无菜单栏占用。只有一个快捷键和一个进度面板。

## 支持格式

| 输入格式 | 输出 | 说明 |
|---|---|---|
| HEIC / HEIF | JPG | iPhone 照片、Apple 实况照片静帧 |
| PNG | JPG | 截图、网页图形 |
| TIFF | JPG | 扫描文档、印刷图形 |
| WebP | JPG | 网络图片 |
| JPG / JPEG | JPG | 按所选质量重新压缩 |
| PDF | JPG（每页） | 每页单独导出为一张图片 |
| Markdown (.md) | JPG | 单页或多页（9:16 比例，2K 分辨率） |

## 路线图

| 格式 | 状态 |
|---|---|
| Word (.docx) | 计划中 |
| Excel (.xlsx) | 计划中 |
| PowerPoint (.pptx) | 计划中 |
| Markdown (.md) | ✅ 已完成 |

## 安装

### 下载安装（推荐）

从 [Releases](https://github.com/IAmKongHai/MiddleOut/releases) 下载最新的 `.dmg` 文件，打开后将 MiddleOut 拖入 Applications 文件夹即可。

该应用已使用 Developer ID 证书签名并经过 Apple 公证——不会触发 Gatekeeper 警告。

### 从源码构建

```bash
git clone https://github.com/IAmKongHai/MiddleOut.git
cd MiddleOut
open MiddleOut.xcodeproj
```

在 Xcode 中构建并运行。需要 macOS 13.0+ 和 Xcode 15+。

## 使用方法

### 首次启动

1. 打开 MiddleOut——设置窗口会自动显示
2. 根据提示授予**辅助功能**权限（全局快捷键所必需）
3. 根据提示授予**自动操作 > Finder** 权限（读取文件选择所必需）
4. 根据需要自定义快捷键和 JPEG 质量
5. 关闭设置窗口——MiddleOut 将继续在后台运行

### 日常使用

1. 在 Finder 中选中一个或多个文件
2. 按下 `Ctrl + Option + J`（或你自定义的快捷键）
3. 屏幕顶部出现浮动进度面板
4. 转换后的文件出现在原文件所在目录中
5. 面板在 3 秒后自动消失

### 输出命名规则

| 输入 | 输出 |
|---|---|
| `photo.heic` | `photo_opt.jpg` |
| `screenshot.png` | `screenshot_opt.jpg` |
| `document.pdf`（3 页） | `document_pages/document_page_1.jpg`、`document_page_2.jpg`、`document_page_3.jpg` |

如果 `photo_opt.jpg` 已存在，MiddleOut 会自动创建 `photo_opt_2.jpg`、`photo_opt_3.jpg` 等。

### 设置

若需重新打开设置窗口，再次启动 MiddleOut 即可（在 Applications 文件夹中双击，或通过 Spotlight 搜索）。

## 技术栈

- **开发语言：** Swift 5.9+
- **界面框架：** AppKit（应用主体及进度面板）+ SwiftUI（设置窗口）
- **图片处理：** ImageIO 框架（原生，无第三方依赖）
- **PDF 处理：** PDFKit 框架
- **快捷键：** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（by Sindre Sorhus）
- **目标平台：** macOS 13.0 Ventura 及以上

## 架构

```
快捷键触发
    |
    v
AppDelegate ──> ProgressPanel.show()
    |
    v（后台队列）
FinderBridge ──> AppleScript ──> Finder 选中项 [URL]
    |
    v
FileRouter ──> 按魔数字节 + ZIP 结构分类
    |
    v
ImageProcessor / PDFProcessor / WordProcessor
ExcelProcessor / MarkdownProcessor ──> 输出 _opt.jpg
    |
    v（主线程）
ProgressPanel ──> 更新 / 完成 / 自动消失
```

所有处理均在后台队列中运行，主线程保持空闲以保证流畅的界面更新。

## 参与贡献

欢迎贡献！无论是修复 Bug、支持新格式，还是改进界面。

1. Fork 本仓库
2. 创建功能分支（`git checkout -b feature/word-support`）
3. 提交你的修改
4. 发起 Pull Request

架构细节、注意事项及新格式支持方法，请参阅 [DEVELOPMENT_GUIDE.md](docs/dev/DEVELOPMENT_GUIDE.md)。

## 为什么叫"MiddleOut"？

这个名字来源于 HBO 美剧《硅谷》（*Silicon Valley*）中虚构的 **Middle-Out 压缩算法**——那个 Weissman 分数高到改变世界的传奇算法。虽然这款应用达不到那种神话般的压缩率，但它确实能让你只按一个键就让文件变小。

## 许可证

MIT 许可证。详情请参阅 [LICENSE](LICENSE)。

---

**MiddleOut** — 在 macOS 上用一个快捷键完成图片转换与压缩。HEIC转JPG，PNG转JPG，PDF转JPG。快速、轻量、开源。
