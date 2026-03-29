# MiddleOut

**전역 단축키 하나로 이미지와 PDF를 즉시 JPG로 변환·압축하는 가벼운 macOS 유틸리티.**

창을 열 필요도 없고, 드래그 앤 드롭도 필요 없습니다. Finder에서 파일을 선택하고 단축키를 누르면 끝입니다.

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)](https://github.com/IAmKongHai/MiddleOut/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 문제 상황

iPhone에서 AirDrop으로 Mac에 사진을 전송했더니 5MB짜리 HEIC 파일입니다. 웹사이트에 업로드해야 하는데:

- 해당 사이트는 HEIC 형식을 지원하지 않음
- 파일이 너무 커서 업로드 불가
- 앱을 열고, 가져오고, 변환하고, 내보내고, 파일을 찾고……

**매번, 이 과정의 반복.**

macOS에는 이런 작업을 처리할 수 있는 빠른 동작과 단축어 기능이 내장되어 있지만, 메뉴 깊숙이 숨겨져 있고 수동 설정도 필요합니다. 그냥 키 하나만 누르면 되면 어떨까요?

## 해결책

MiddleOut은 백그라운드에서 조용히 실행됩니다. 파일을 변환해야 할 때는:

1. Finder에서 파일 선택
2. `Ctrl + Option + J` 입력
3. 끝입니다. 변환된 파일이 원본 파일 바로 옆에 생성됩니다.

플로팅 진행 패널이 실시간 처리 상태를 표시하고, 완료 후 자동으로 사라집니다.

## 주요 기능

- **전역 단축키** — 어떤 앱에서든 실행 가능, 앱 전환 불필요. 기본값: `Ctrl + Option + J` (커스터마이즈 가능)
- **이미지 변환** — HEIC, PNG, TIFF, WebP를 압축 JPG로 변환 (HEIC JPG 변환 Mac 최적의 도구)
- **PDF → JPG 변환** — PDF 각 페이지를 개별 JPG 이미지로 추출
- **일괄 처리** — 1개든 1,000개든 파일을 선택하고 단축키 한 번으로 처리
- **품질 조절** — JPEG 품질을 0%~100% 슬라이더로 설정
- **비파괴 처리** — 원본 파일은 절대 수정되지 않습니다. 출력 파일명은 `파일명_opt.jpg`
- **UI 마찰 제로** — Dock 아이콘도 없고, 메뉴바도 차지하지 않습니다. 단축키와 진행 패널만.

## 지원 형식

| 입력 형식 | 출력 | 비고 |
|---|---|---|
| HEIC / HEIF | JPG | iPhone 사진, Apple Live Photos 정지 이미지 |
| PNG | JPG | 스크린샷, 웹 그래픽 |
| TIFF | JPG | 스캔 문서, 인쇄용 이미지 |
| WebP | JPG | 웹 이미지 |
| JPG / JPEG | JPG | 선택한 품질로 재압축 |
| PDF | JPG (페이지별) | 각 페이지를 개별 이미지로 추출 |

## 로드맵

향후 버전에서 지원 예정인 형식:

| 형식 | 상태 |
|---|---|
| Word (.docx) | 계획 중 |
| Excel (.xlsx) | 계획 중 |
| PowerPoint (.pptx) | 계획 중 |
| Markdown (.md) | 계획 중 |

## 설치

### 다운로드 (권장)

[Releases](https://github.com/IAmKongHai/MiddleOut/releases)에서 최신 `.dmg` 파일을 다운로드하고, 열어서 MiddleOut을 Applications 폴더로 드래그하세요.

이 앱은 Developer ID 인증서로 서명되고 Apple의 공증을 받았습니다——Gatekeeper 경고가 표시되지 않습니다.

### 소스에서 빌드

```bash
git clone https://github.com/IAmKongHai/MiddleOut.git
cd MiddleOut
open MiddleOut.xcodeproj
```

Xcode에서 빌드하고 실행하세요. macOS 13.0+와 Xcode 15+가 필요합니다.

## 사용 방법

### 첫 실행

1. MiddleOut 실행——설정 창이 자동으로 표시됩니다
2. 메시지가 표시되면 **손쉬운 사용(Accessibility)** 권한 허용 (전역 단축키에 필요)
3. 메시지가 표시되면 **자동화 > Finder** 권한 허용 (파일 선택 읽기에 필요)
4. 필요에 따라 단축키와 JPEG 품질 커스터마이즈
5. 설정 창 닫기——MiddleOut은 백그라운드에서 계속 실행됩니다

### 일상적인 사용

1. Finder에서 하나 이상의 파일 선택
2. `Ctrl + Option + J` (또는 커스텀 단축키) 입력
3. 화면 상단에 플로팅 진행 패널이 표시됨
4. 변환된 파일이 원본과 같은 디렉터리에 생성됨
5. 패널이 3초 후 자동으로 사라짐

### 출력 파일명 규칙

| 입력 | 출력 |
|---|---|
| `photo.heic` | `photo_opt.jpg` |
| `screenshot.png` | `screenshot_opt.jpg` |
| `document.pdf` (3페이지) | `document_pages/document_page_1.jpg`, `document_page_2.jpg`, `document_page_3.jpg` |

`photo_opt.jpg`가 이미 존재하면, MiddleOut은 `photo_opt_2.jpg`, `photo_opt_3.jpg` 등으로 자동 생성합니다.

### 설정

설정 창을 다시 열려면 MiddleOut을 다시 실행하면 됩니다 (Applications에서 더블클릭하거나 Spotlight로 검색).

## 기술 스택

- **언어:** Swift 5.9+
- **UI:** AppKit (앱 본체 및 진행 패널) + SwiftUI (설정 창)
- **이미지 처리:** ImageIO 프레임워크 (네이티브, 서드파티 의존성 없음)
- **PDF 처리:** PDFKit 프레임워크
- **단축키:** [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (by Sindre Sorhus)
- **지원 환경:** macOS 13.0 Ventura 이상

## 아키텍처

```
단축키 입력
    |
    v
AppDelegate ──> ProgressPanel.show()
    |
    v (백그라운드 큐)
FinderBridge ──> AppleScript ──> Finder 선택 항목 [URL]
    |
    v
FileRouter ──> 확장자별 분류
    |
    v
ImageProcessor / PDFProcessor ──> _opt.jpg 출력
    |
    v (메인 스레드)
ProgressPanel ──> 업데이트 / 완료 / 자동 닫힘
```

모든 처리는 백그라운드 큐에서 실행됩니다. 메인 스레드는 항상 여유롭게 유지되어 UI 업데이트가 매끄럽게 이루어집니다.

## 기여하기

버그 수정, 새 형식 지원, UI 개선 등 어떤 형태의 기여든 환영합니다.

1. 저장소를 Fork
2. 기능 브랜치 생성 (`git checkout -b feature/word-support`)
3. 변경사항 커밋
4. Pull Request 열기

아키텍처 세부사항, 주의사항, 새 형식 지원 방법은 [DEVELOPMENT_GUIDE.md](docs/dev/DEVELOPMENT_GUIDE.md)를 참고하세요.

## 왜 "MiddleOut"인가?

이 이름은 HBO 드라마 《실리콘 밸리》(*Silicon Valley*)에 등장하는 가상의 **Middle-Out 압축 알고리즘**에서 따온 것입니다——Weissman Score가 너무 높아 세상을 바꿔버렸다는 그 전설의 알고리즘. 이 앱이 그런 신화적인 압축률에 도달하지는 못하지만, 단 한 번의 키 입력으로 파일을 작게 만든다는 것만큼은 확실합니다.

## 라이선스

MIT 라이선스. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.

---

**MiddleOut** — macOS에서 단축키 하나로 이미지 변환 및 압축. HEIC JPG 변환 Mac, PNG→JPG, PDF→JPG. 빠르고, 가볍고, 오픈소스.
