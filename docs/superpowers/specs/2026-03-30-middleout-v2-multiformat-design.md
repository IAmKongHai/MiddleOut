# MiddleOut V2 设计文档 — 多格式支持

> 日期：2026-03-30
> 状态：已批准

## 概述

MiddleOut V2 新增对 Word (.docx)、Excel (.xlsx)、PowerPoint (.pptx)、Markdown (.md) 四种格式的支持，将它们转换为 JPEG 图片。核心设计原则：

- **完整文档转换**（非预览/缩略图），类似 V1 的 PDF 全页转换
- **零外部依赖**，不依赖 Microsoft Office 或 LibreOffice
- **不动 V1 已稳定的代码**，现有 ImageProcessor / PDFProcessor 零改动

---

## 1. 整体架构

### 新增文件

```
Core/
├── ImageProcessor.swift            (现有，不动)
├── PDFProcessor.swift              (现有，不动)
├── FileRouter.swift                (改造：magic bytes 两级识别)
├── ProcessingCoordinator.swift     (改造：新增 dispatch 分支)
├── OutputNamer.swift               (改造：新增文档类命名方法)
├── WordProcessor.swift             (新增)
├── PPTProcessor.swift              (新增)
├── WebViewRenderer.swift           (新增，统一 WKWebView 渲染引擎)
├── ExcelProcessor.swift            (新增，CoreXLSX → HTML → WebViewRenderer)
└── MarkdownProcessor.swift         (新增，cmark → HTML → WebViewRenderer)
```

### 新增 SPM 依赖

| 依赖 | 用途 | 许可证 |
|------|------|--------|
| CoreXLSX | 解析 .xlsx 数据和样式 | MIT |
| PPTXKit (pptx-swift) | 解析并渲染 .pptx 幻灯片 | MIT |
| swift-cmark | Markdown → HTML | MIT |

Word 和 PDF 不需要新依赖（NSAttributedString + Core Text + PDFKit 都是系统框架）。

### 数据流总览

```
快捷键 → AppDelegate → ProgressPanel.show()
                      → ProcessingCoordinator.start()
                          ↓ (background queue)
                      → FinderBridge.getSelection()
                      → FileRouter.classify()  ← magic bytes 两级识别
                      → 按类型 dispatch:
                          images    → ImageProcessor      (现有)
                          pdfs      → PDFProcessor        (现有)
                          words     → WordProcessor       → Core Text 分页 → JPEG
                          excels    → ExcelProcessor      → CoreXLSX → HTML → WebViewRenderer → JPEG
                          ppts      → PPTProcessor        → PPTXKit → slide images → JPEG
                          markdowns → MarkdownProcessor   → cmark → HTML → WebViewRenderer → JPEG
                      → onProgress / onCompleted → ProgressPanel
```

---

## 2. FileRouter 改造 — Magic Bytes 两级识别

### 类型定义

```swift
enum FileCategory {
    case image      // JPEG, PNG, TIFF, WebP, HEIC
    case pdf
    case word       // .docx
    case excel      // .xlsx
    case ppt        // .pptx
    case markdown   // .md
}
```

### ClassificationResult 扩展

```swift
struct ClassificationResult {
    let images: [URL]
    let pdfs: [URL]
    let words: [URL]
    let excels: [URL]
    let ppts: [URL]
    let markdowns: [URL]
    let skipped: [(url: URL, reason: String)]
}
```

### 两级识别流程

```
读取文件前 16 字节
    │
    ├─ FF D8 FF                        → image (JPEG)
    ├─ 89 50 4E 47                     → image (PNG)
    ├─ 49 49 2A 00 / 4D 4D 00 2A      → image (TIFF)
    ├─ 52 49 46 46 .. WEBP             → image (WebP)
    ├─ offset 4: 66 74 79 70 (ftyp)   → image (HEIC)
    ├─ 25 50 44 46                     → pdf
    ├─ 50 4B 03 04                     → ZIP → 进入第二级
    │   ├─ 包含 word/document.xml      → word
    │   ├─ 包含 xl/workbook.xml        → excel
    │   ├─ 包含 ppt/presentation.xml   → ppt
    │   └─ 无法识别的 ZIP              → skipped("unsupported ZIP archive")
    │
    └─ 以上都不匹配 → 回退扩展名检查
        ├─ .md / .markdown             → markdown
        └─ 其他                         → skipped("unsupported format")
```

### 设计要点

- **ZIP 内部检查不解压全部内容** — 只读取 ZIP 的 central directory（文件名列表），不解压文件内容，性能开销极小。复用 CoreXLSX 引入的 ZIPFoundation 依赖。
- **Markdown 的特殊性** — 纯文本没有 magic bytes，只能靠扩展名。这是唯一的例外。
- **错误隔离** — 文件头读取失败（权限不足、文件为空等）直接归入 skipped，附带具体原因，不抛异常不崩溃。
- **扩展名作为最后的参考** — magic bytes 无法识别时才看扩展名，且仅用于 Markdown。

---

## 3. WebViewRenderer — 统一 WKWebView 渲染引擎

服务于 Excel 和 Markdown，接收 HTML + viewport 尺寸，离屏渲染后截图输出 NSImage。

### 接口设计

```swift
struct WebViewRenderer {
    struct RenderOptions {
        let html: String
        let viewportWidth: CGFloat
        let viewportHeight: CGFloat?   // nil = 按内容自适应高度
    }

    struct RenderResult {
        let image: NSImage
        let actualSize: CGSize
    }

    /// 渲染单张 HTML → NSImage（同步阻塞，必须在后台队列调用）
    static func render(_ options: RenderOptions) throws -> RenderResult

    /// 批量渲染多张 HTML → [NSImage]（用于 Excel 多 sheet）
    static func renderBatch(_ optionsList: [RenderOptions]) throws -> [RenderResult]
}
```

### 主线程协调方案

```
后台队列 (调用方)                    主线程 (WKWebView)
    │                                    │
    ├─ 调用 render()                     │
    │   创建 DispatchSemaphore           │
    │                                    │
    ├─ DispatchQueue.main.async ────────>│
    │                                    ├─ 创建 WKWebView（离屏，不加入窗口层级）
    │                                    ├─ loadHTMLString()
    │                                    ├─ 等待 didFinish 回调
    │                                    ├─ JS 获取 document.body.scrollHeight
    │                                    ├─ 调整 viewport 高度
    │                                    ├─ takeSnapshot()
    │                                    ├─ signal semaphore
    │   semaphore.wait() <───────────────┤
    │                                    │
    ├─ 拿到 NSImage，继续处理            │
```

### 关键设计细节

- **离屏渲染** — WKWebView 不加入任何窗口的 view 层级，只设置 frame 尺寸。
- **高度自适应** — 加载完成后通过 JS 获取 `document.body.scrollHeight`，动态调整 frame 高度后截图。用于 Excel（一个 sheet 一张图）。
- **超时保护** — semaphore.wait 设 30 秒超时，超时归入 skipped。
- **资源清理** — 每次渲染完成后，WKWebView 实例在主线程销毁，不复用实例。

---

## 4. 四个新处理器

### 4.1 WordProcessor — NSAttributedString + Core Text 分页

**输入**：.docx 文件 URL
**输出**：每页一张 JPEG，放入 `filename_pages/`

```
docx URL
  → NSAttributedString(url:, documentType: .docx)
  → CTFramesetter 创建
  → 循环分页：
      CTFramesetterSuggestFrameSizeWithConstraints (A4 页面)
      → CTFramesetterCreateFrame
      → CGContext (bitmap context) 绘制
      → CGImage → NSImage → JPEG
      → 更新剩余文本范围，下一页
```

- 页面尺寸：A4 比例 595×842 pt → 渲染 1190×1684 像素（2x 缩放）
- 空文档归入 skipped
- 损坏文件捕获异常归入 skipped
- 已知局限：复杂表格、浮动图片、多栏排版还原度有限

### 4.2 ExcelProcessor — CoreXLSX → HTML → WebViewRenderer

**输入**：.xlsx 文件 URL
**输出**：每个 sheet 一张 JPEG，放入 `filename_pages/`

```
xlsx URL
  → CoreXLSX 打开 XLSXFile
  → 遍历每个 worksheet：
      → 读取单元格数据 + 合并单元格 + 基础样式
      → 生成 HTML <table>（含 CSS）
      → WebViewRenderer.render(html, viewportWidth: 按列数自适应, viewportHeight: nil)
      → NSImage → JPEG
```

- 读取：单元格值（字符串、数字、日期）、合并单元格（colspan/rowspan）、列宽行高
- CSS：边框、对齐方式、背景色、字体大小
- viewport 宽度按实际列数和列宽计算，高度自适应
- 不处理：图表、条件格式、公式执行（读取缓存值）

### 4.3 PPTProcessor — PPTXKit 渲染

**输入**：.pptx 文件 URL
**输出**：每张幻灯片一张 JPEG，放入 `filename_pages/`

```
pptx URL
  → PPTXKit 打开文档
  → 遍历每张 slide：
      → PPTXKit 渲染 slide → NSImage / CGImage
      → JPEG 压缩输出
```

- 输出尺寸按幻灯片原始宽高比（通常 16:9 或 4:3）
- 渲染分辨率 2x 保证清晰度
- 风险：PPTXKit 相对小众，需在实现阶段验证渲染质量。备选方案为解析 slide XML → HTML → WebViewRenderer

### 4.4 MarkdownProcessor — cmark → HTML → WebViewRenderer

**输入**：.md 文件 URL
**输出**：单页或多页 JPEG（按内容长度决定）

```
md URL
  → 读取文件文本内容（UTF-8）
  → swift-cmark 解析 → HTML
  → 注入 CSS 样式（排版、字体、代码高亮）
  → WebViewRenderer.render(html, viewportWidth: 2160, viewportHeight: nil)
  → 获取实际内容高度
  → ≤ 3840px：单张截图
  → > 3840px：按 3740px 步长逐页截图（100px 重叠）
  → NSImage → JPEG
```

**Markdown 渲染参数**：
- 每页 viewport：2160×3840（9:16，2K 分辨率）
- 分页步长：3740px（重叠 100px 防止文字被截断）
- 页数无上限，由内容决定
- CSS：GitHub 风格阅读样式，font-size 适配 2K 屏幕，代码块等宽字体 + 浅灰背景
- 图片引用：设置 baseURL 为 md 文件所在目录，支持相对路径

**分页计算**：

```
第 1 页：y = 0,      截取 3840px
第 2 页：y = 3740,   截取 3840px
第 3 页：y = 7480,   截取 3840px
...
末页：  y = n×3740,  截取剩余高度（≤ 3840px）
```

---

## 5. 输出命名规则

与现有 PDF 一致的 `_pages/` 模式，OutputNamer 扩展：

| 输入 | 输出 |
|------|------|
| `report.docx` (3 页) | `report_pages/report_page_1.jpg`, `report_page_2.jpg`, `report_page_3.jpg` |
| `data.xlsx` (2 个 sheet: Sheet1, 销售数据) | `data_pages/data_Sheet1.jpg`, `data_销售数据.jpg` |
| `pitch.pptx` (5 张 slide) | `pitch_pages/pitch_page_1.jpg` ~ `pitch_page_5.jpg` |
| `notes.md` (短文) | `notes_opt.jpg` |
| `novel.md` (长文) | `novel_pages/novel_page_1.jpg` ~ `novel_page_n.jpg` |

- Excel 用 sheet 名称命名（特殊字符替换为 `_`）
- Markdown 短内容用 `_opt.jpg`，长内容进入 `_pages/`

---

## 6. ProcessingCoordinator 改造

### Dispatch 逻辑

```swift
let classified = FileRouter.classify(urls)
let allProcessable = classified.images + classified.pdfs
    + classified.words + classified.excels
    + classified.ppts + classified.markdowns

for url in allProcessable {
    do {
        let category = FileRouter.identifyCategory(url)
        switch category {
        case .image:    // ImageProcessor
        case .pdf:      // PDFProcessor
        case .word:     // WordProcessor
        case .excel:    // ExcelProcessor
        case .ppt:      // PPTProcessor
        case .markdown: // MarkdownProcessor
        }
        convertedCount += 1
    } catch {
        allSkipped.append((url, error.localizedDescription))
    }
}
```

### 错误处理

| 处理器 | Error 类型 | 典型错误 |
|--------|-----------|----------|
| WordProcessor | WordProcessorError | .invalidDocument / .emptyDocument / .renderFailed(page:) |
| ExcelProcessor | ExcelProcessorError | .invalidFile / .emptyWorkbook / .sheetRenderFailed(name:) |
| PPTProcessor | PPTProcessorError | .invalidFile / .emptyPresentation / .slideRenderFailed(index:) |
| MarkdownProcessor | MarkdownProcessorError | .readFailed / .parseFailed / .renderTimeout |

核心原则：
- 单个文件失败不中断批处理
- 多页文档中单页失败不中断该文档，跳过并记录
- WebViewRenderer 超时 30 秒视为失败

### ProcessingSummary 扩展

```swift
struct ProcessingSummary {
    let totalFiles: Int
    let convertedFiles: Int
    let totalOutputImages: Int    // 新增：实际生成的 JPEG 数量
    let totalBytesSaved: Int64
    let skipped: [(url: URL, reason: String)]
    let duration: TimeInterval
}
```

---

## 7. 兼容性与测试

### 兼容性

| 项目 | 要求 |
|------|------|
| macOS 最低版本 | 维持 13.0 |
| Swift 版本 | 维持 5.9+ |
| Xcode | 维持 15+ |
| App Sandbox | 维持关闭 |

### 测试策略

| 测试文件 | 覆盖内容 |
|----------|----------|
| FileRouterTests | magic bytes 正确识别、错误扩展名、损坏文件、空文件、ZIP 非 Office |
| WordProcessorTests | 基础 docx 转换、空文档、损坏文件 |
| ExcelProcessorTests | 单/多 sheet、合并单元格、空工作簿、损坏文件 |
| PPTProcessorTests | 单/多 slide、空演示文稿、损坏文件 |
| MarkdownProcessorTests | 短文单页、长文多页分页、含图片引用、空文件 |
| WebViewRendererTests | 渲染输出尺寸、超时处理、高度自适应 |

测试资源放置于 `Tests/Resources/`。

### 实现优先级

```
Phase 1: 基础设施
  ├─ FileRouter 改造（magic bytes 两级识别）
  └─ OutputNamer 扩展（新格式命名方法）

Phase 2: WebViewRenderer
  └─ 统一渲染引擎（含分页截图、超时保护）

Phase 3: 处理器（按复杂度从低到高）
  ├─ MarkdownProcessor（最简单，验证 WebViewRenderer 管线）
  ├─ ExcelProcessor（验证 CoreXLSX + WebViewRenderer 集成）
  ├─ WordProcessor（独立管线，Core Text 分页）
  └─ PPTProcessor（依赖 PPTXKit，需验证第三方库质量）

Phase 4: 集成
  ├─ ProcessingCoordinator 新增 dispatch 分支
  ├─ ProcessingSummary 扩展
  └─ 端到端测试
```

Markdown 优先实现的理由：它是 WebViewRenderer 最简单的消费者，可以最快验证 WKWebView 离屏渲染 → 截图 → JPEG 管线。
