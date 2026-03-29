# MiddleOut

**一款輕量級 macOS 工具，可透過全域快速鍵將圖片與 PDF 即時轉換並壓縮為 JPG。**

無需開啟任何視窗，無需拖放操作。只要在 Finder 中選取檔案，按下快速鍵，搞定。

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://github.com/IAmKongHai/MiddleOut/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 問題所在

你用 AirDrop 從 iPhone 傳了一張照片到 Mac——一個 5MB 的 HEIC 檔案。你需要將它上傳到某個網站，但：

- 該網站不支援 HEIC 格式
- 檔案太大，無法上傳
- 你不得不打開一個應用程式，匯入、轉換、匯出，再找到檔案……

**每一次，都是這樣。**

macOS 內建了「快速動作」和「捷徑」可以處理這類任務，但它們藏在層層選單裡，還需要手動設定。如果只需要按一個鍵呢？

## 解決方案

MiddleOut 靜默在背景執行。需要轉換檔案時：

1. 在 Finder 中選取檔案
2. 按下 `Ctrl + Option + J`
3. 就這樣。轉換後的檔案直接出現在原始檔案旁邊。

浮動進度面板會即時顯示處理狀態，完成後自動消失。

## 功能特色

- **全域快速鍵** — 在任何應用程式中均可觸發，無需切換。預設：`Ctrl + Option + J`（可自訂）
- **圖片轉換** — 將 HEIC、PNG、TIFF、WebP 轉換為壓縮後的 JPG（HEIC轉JPG Mac 首選工具）
- **PDF 轉 JPG** — 將 PDF 每一頁分別匯出為 JPG 圖片
- **批次處理** — 選取 1 個或 1000 個檔案，按下快速鍵即可
- **可調整品質** — JPEG 品質滑桿，範圍 0% 至 100%
- **非破壞性處理** — 原始檔案永遠不會被修改。輸出檔案命名為 `檔名_opt.jpg`
- **零介面干擾** — 無 Dock 圖示，無選單列佔用。只有一個快速鍵和一個進度面板。

## 支援格式

| 輸入格式 | 輸出 | 說明 |
|---|---|---|
| HEIC / HEIF | JPG | iPhone 照片、Apple 動態照片靜幀 |
| PNG | JPG | 截圖、網頁圖形 |
| TIFF | JPG | 掃描文件、印刷圖形 |
| WebP | JPG | 網路圖片 |
| JPG / JPEG | JPG | 按所選品質重新壓縮 |
| PDF | JPG（每頁） | 每頁分別匯出為一張圖片 |

## 開發藍圖

未來版本計畫支援的格式：

| 格式 | 狀態 |
|---|---|
| Word (.docx) | 計畫中 |
| Excel (.xlsx) | 計畫中 |
| PowerPoint (.pptx) | 計畫中 |
| Markdown (.md) | 計畫中 |

## 安裝

### 下載安裝（建議）

從 [Releases](https://github.com/IAmKongHai/MiddleOut/releases) 下載最新的 `.dmg` 檔案，開啟後將 MiddleOut 拖入 Applications 資料夾即可。

此應用程式已使用 Developer ID 憑證簽署並經過 Apple 公證——不會觸發 Gatekeeper 警告。

### 從原始碼建置

```bash
git clone https://github.com/IAmKongHai/MiddleOut.git
cd MiddleOut
open MiddleOut.xcodeproj
```

在 Xcode 中建置並執行。需要 macOS 13.0+ 與 Xcode 15+。

## 使用方式

### 首次啟動

1. 開啟 MiddleOut——設定視窗會自動出現
2. 依提示授予**輔助使用**權限（全域快速鍵所必需）
3. 依提示授予**自動化 > Finder** 權限（讀取檔案選取所必需）
4. 視需要自訂快速鍵與 JPEG 品質
5. 關閉設定視窗——MiddleOut 將繼續在背景執行

### 日常使用

1. 在 Finder 中選取一個或多個檔案
2. 按下 `Ctrl + Option + J`（或你自訂的快速鍵）
3. 螢幕頂端出現浮動進度面板
4. 轉換後的檔案出現在原始檔案所在的目錄中
5. 面板在 3 秒後自動消失

### 輸出命名規則

| 輸入 | 輸出 |
|---|---|
| `photo.heic` | `photo_opt.jpg` |
| `screenshot.png` | `screenshot_opt.jpg` |
| `document.pdf`（3 頁） | `document_pages/document_page_1.jpg`、`document_page_2.jpg`、`document_page_3.jpg` |

若 `photo_opt.jpg` 已存在，MiddleOut 會自動建立 `photo_opt_2.jpg`、`photo_opt_3.jpg` 等。

### 設定

若需重新開啟設定視窗，再次啟動 MiddleOut 即可（在 Applications 資料夾中按兩下，或透過 Spotlight 搜尋）。

## 技術架構

- **開發語言：** Swift 5.9+
- **介面框架：** AppKit（應用程式主體及進度面板）+ SwiftUI（設定視窗）
- **圖片處理：** ImageIO 框架（原生，無第三方相依性）
- **PDF 處理：** PDFKit 框架
- **快速鍵：** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（by Sindre Sorhus）
- **目標平台：** macOS 13.0 Ventura 及以上

## 架構

```
快速鍵觸發
    |
    v
AppDelegate ──> ProgressPanel.show()
    |
    v（背景佇列）
FinderBridge ──> AppleScript ──> Finder 選取項目 [URL]
    |
    v
FileRouter ──> 依副檔名分類
    |
    v
ImageProcessor / PDFProcessor ──> 輸出 _opt.jpg
    |
    v（主執行緒）
ProgressPanel ──> 更新 / 完成 / 自動消失
```

所有處理均在背景佇列中執行，主執行緒保持空閒以確保流暢的介面更新。

## 參與貢獻

歡迎貢獻！無論是修正錯誤、支援新格式，還是改善介面。

1. Fork 本儲存庫
2. 建立功能分支（`git checkout -b feature/word-support`）
3. 提交你的變更
4. 發起 Pull Request

架構細節、注意事項及新格式支援方式，請參閱 [DEVELOPMENT_GUIDE.md](docs/dev/DEVELOPMENT_GUIDE.md)。

## 為什麼叫「MiddleOut」？

這個名字源自 HBO 影集《矽谷》（*Silicon Valley*）中虛構的 **Middle-Out 壓縮演算法**——那個 Weissman 分數高到足以改變世界的傳奇演算法。雖然這款應用程式達不到那種神話般的壓縮率，但它確實能讓你只按一個鍵就讓檔案變小。

## 授權條款

MIT 授權條款。詳情請參閱 [LICENSE](LICENSE)。

---

**MiddleOut** — 在 macOS 上用一個快速鍵完成圖片轉換與壓縮。HEIC轉JPG，PNG轉JPG，PDF轉JPG。快速、輕量、開源。
