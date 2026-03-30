# MiddleOut

**グローバルホットキー一発で、画像・PDFをJPGに変換・圧縮できる軽量macOSユーティリティ。**

ウィンドウを開く必要なし。ドラッグ＆ドロップも不要。Finderでファイルを選択してホットキーを押すだけ、それだけです。

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://github.com/IAmKongHai/MiddleOut/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 抱えている問題

iPhoneからAirDropでMacに写真を転送したら、5MBのHEICファイルだった。Webサイトにアップロードしたいのに：

- そのサイトはHEIC形式に対応していない
- ファイルが大きすぎてアップロードできない
- アプリを開いて、インポートして、変換して、エクスポートして、ファイルを探して……

**毎回、これの繰り返し。**

macOSにはこうした作業をこなせるクイックアクションやショートカット機能が内蔵されていますが、メニューの奥深くに埋もれており、手動での設定も必要です。キーを一つ押すだけで済んだら？

## 解決策

MiddleOutはバックグラウンドで静かに動き続けます。ファイルを変換したいときは：

1. Finderでファイルを選択
2. `Ctrl + Option + J` を押す
3. 以上です。変換済みファイルが元のファイルの隣に現れます。

フローティングの進捗パネルがリアルタイムで処理状況を表示し、完了後は自動的に消えます。

## 機能

- **グローバルホットキー** — どのアプリからでも起動可能、アプリの切り替え不要。デフォルト：`Ctrl + Option + J`（カスタマイズ可）
- **画像変換** — HEIC、PNG、TIFF、WebPを圧縮JPGに変換（HEIC JPG変換 Mac に最適なツール）
- **PDF→JPG変換** — PDFの各ページを個別のJPG画像として書き出し
- **Word→JPG変換** — .docxの各ページをJPEG画像としてレンダリング
- **Excel→JPG変換** — .xlsxの各ワークシートをJPEG画像としてレンダリング
- **Markdown→JPG変換** — .mdをモバイル向け9:16 JPEG（2K解像度）に変換
- **バッチ処理** — 1ファイルでも1000ファイルでも、ホットキー一発で処理
- **品質調整** — JPEGクオリティを0%〜100%のスライダーで設定
- **非破壊処理** — 元のファイルは一切変更されません。出力ファイルは `ファイル名_opt.jpg` という名前で保存
- **UI摩擦ゼロ** — Dockアイコンなし、メニューバーも占有しない。ホットキーと進捗パネルだけ。

## 対応フォーマット

| 入力フォーマット | 出力 | 備考 |
|---|---|---|
| HEIC / HEIF | JPG | iPhoneの写真、Apple Live Photosの静止画 |
| PNG | JPG | スクリーンショット、Web画像 |
| TIFF | JPG | スキャン文書、印刷用画像 |
| WebP | JPG | Web画像 |
| JPG / JPEG | JPG | 指定品質で再圧縮 |
| PDF | JPG（ページごと） | 各ページを個別の画像として書き出し |
| Word (.docx) | JPG（ページごと） | 各ページを個別の画像としてレンダリング |
| Excel (.xlsx) | JPG（シートごと） | 各ワークシートを個別の画像としてレンダリング |
| Markdown (.md) | JPG | 単ページまたは複数ページ（9:16比率、2K解像度） |

## ロードマップ

| フォーマット | 状態 |
|---|---|
| Word (.docx) | ✅ 完了 |
| Excel (.xlsx) | ✅ 完了 |
| PowerPoint (.pptx) | 予定 |
| Markdown (.md) | ✅ 完了 |

## インストール

### ダウンロード（推奨）

[Releases](https://github.com/IAmKongHai/MiddleOut/releases) から最新の `.dmg` をダウンロードし、開いてMiddleOutをApplicationsフォルダにドラッグしてください。

このアプリはDeveloper ID証明書で署名され、Appleに公証されています——Gatekeeperの警告は表示されません。

### ソースからビルド

```bash
git clone https://github.com/IAmKongHai/MiddleOut.git
cd MiddleOut
open MiddleOut.xcodeproj
```

Xcodeでビルドして実行してください。macOS 13.0+とXcode 15+が必要です。

## 使い方

### 初回起動

1. MiddleOutを開く——設定ウィンドウが表示されます
2. 求められたら**アクセシビリティ**の権限を許可（グローバルホットキーに必要）
3. 求められたら**自動化 > Finder**の権限を許可（ファイル選択の読み取りに必要）
4. 必要に応じてホットキーとJPEGクオリティをカスタマイズ
5. 設定ウィンドウを閉じる——MiddleOutはバックグラウンドで動き続けます

### 通常の使い方

1. Finderで1つ以上のファイルを選択
2. `Ctrl + Option + J`（またはカスタムのショートカットキー）を押す
3. 画面上部にフローティングの進捗パネルが表示される
4. 変換済みファイルが元のファイルと同じディレクトリに保存される
5. パネルは3秒後に自動的に消える

### 出力ファイルの命名規則

| 入力 | 出力 |
|---|---|
| `photo.heic` | `photo_opt.jpg` |
| `screenshot.png` | `screenshot_opt.jpg` |
| `document.pdf`（3ページ） | `document_pages/document_page_1.jpg`、`document_page_2.jpg`、`document_page_3.jpg` |

`photo_opt.jpg` がすでに存在する場合、MiddleOutは `photo_opt_2.jpg`、`photo_opt_3.jpg` のように連番で作成します。

### 設定

設定ウィンドウを再度開くには、MiddleOutをもう一度起動してください（ApplicationsでダブルクリックするかSpotlightで検索）。

## 技術スタック

- **言語：** Swift 5.9+
- **UI：** AppKit（アプリ本体・進捗パネル）+ SwiftUI（設定ウィンドウ）
- **画像処理：** ImageIOフレームワーク（ネイティブ、サードパーティ依存なし）
- **PDF処理：** PDFKitフレームワーク
- **ホットキー：** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（by Sindre Sorhus）
- **対象環境：** macOS 13.0 Ventura以降

## アーキテクチャ

```
ホットキー押下
    |
    v
AppDelegate ──> ProgressPanel.show()
    |
    v（バックグラウンドキュー）
FinderBridge ──> AppleScript ──> Finder選択ファイル [URL]
    |
    v
FileRouter ──> マジックバイト + ZIP構造で分類
    |
    v
ImageProcessor / PDFProcessor / WordProcessor
ExcelProcessor / MarkdownProcessor ──> _opt.jpg を出力
    |
    v（メインスレッド）
ProgressPanel ──> 更新 / 完了 / 自動消去
```

すべての処理はバックグラウンドキューで実行されます。メインスレッドは常に解放されており、スムーズなUI更新を実現しています。

## コントリビューション

バグ修正、新フォーマットのサポート、UIの改善など、コントリビューションは大歓迎です。

1. リポジトリをFork
2. フィーチャーブランチを作成（`git checkout -b feature/word-support`）
3. 変更をコミット
4. Pull Requestを作成

アーキテクチャの詳細、注意点、新フォーマットの追加方法については [DEVELOPMENT_GUIDE.md](docs/dev/DEVELOPMENT_GUIDE.md) を参照してください。

## なぜ「MiddleOut」？

この名前はHBOのドラマ『シリコンバレー』（*Silicon Valley*）に登場する架空の圧縮アルゴリズム、**Middle-Out圧縮**へのオマージュです——世界を変えるほど高いWeissman Scoreを叩き出した伝説のアルゴリズム。このアプリがその神話的な圧縮率に届くことはありませんが、キー一つでファイルを小さくするという約束は果たします。

## ライセンス

MITライセンス。詳細は [LICENSE](LICENSE) を参照してください。

---

**MiddleOut** — ホットキー一つでmacOS上の画像を変換・圧縮。HEIC JPG変換 Mac、PNG→JPG、PDF→JPG。高速・軽量・オープンソース。
