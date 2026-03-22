# TinyJSON

A native macOS JSON editor. Collapsible tree on one side, syntax-highlighted source on the other. Tells you exactly where it's broken.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

![TinyJSON screenshot](screenshot.png)

## Features

- **Three-panel layout** — file sidebar, editor, and tree preview
- **Syntax highlighting** — keys, strings, numbers, booleans, nulls
- **Live preview** — collapsible tree view rendered as you type
- **Directory browsing** — navigate folders, subdirectories, and files
- **Quick open** — fuzzy file finder (Cmd+P)
- **Auto-save** — saves as you type with dirty-file indicators
- **Find & replace** — native macOS find bar (Cmd+F)
- **JSON validation** — real-time error reporting with line numbers
- **Tab support** — multiple files in tabs
- **Line numbers** — optional gutter with current line highlight
- **Word wrap** — toggle with Opt+Z
- **Font size control** — Cmd+/Cmd- to adjust, Cmd+0 to reset
- **Light & dark mode** — follows system appearance
- **Status bar** — line count, file size, validation status
- **Open from Finder** — double-click `.json` or `.geojson` files to open in TinyJSON
- **On-device AI** — Cmd+K to ask questions about your data (CoreML, fully offline)

## Requirements

- macOS 26.0+
- Xcode 26+ (to build)

## Build

```bash
xcodebuild clean build \
  -project TinyJSON.xcodeproj \
  -scheme TinyJSON \
  -configuration Release \
  -derivedDataPath /tmp/tinybuild/tinyjson \
  CODE_SIGN_IDENTITY="-"

cp -R /tmp/tinybuild/tinyjson/Build/Products/Release/TinyJSON.app /Applications/
```

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+N | New file |
| Cmd+O | Open folder |
| Cmd+S | Save |
| Cmd+P | Quick open |
| Cmd+F | Find |
| Cmd+K | AI assistant |
| Opt+Z | Toggle word wrap |
| Opt+P | Toggle preview |
| Opt+L | Toggle line numbers |
| Cmd+= / Cmd+- | Font size |
| Cmd+0 | Reset font size |

## Tech

Built with SwiftUI, NSTextView, and TinyKit.

## Part of [TinySuite](https://tinysuite.app)

Native macOS micro-tools that each do one thing well.

| App | What it does |
|-----|-------------|
| [TinyMark](https://github.com/michellzappa/tinymark) | Markdown editor with live preview |
| [TinyTask](https://github.com/michellzappa/tinytask) | Plain-text task manager |
| **TinyJSON** | JSON viewer with collapsible tree |
| [TinyCSV](https://github.com/michellzappa/tinycsv) | Lightweight CSV/TSV table viewer |
| [TinyPDF](https://github.com/michellzappa/tinypdf) | PDF text extractor with OCR |
| [TinyLog](https://github.com/michellzappa/tinylog) | Log viewer with level filtering |
| [TinySQL](https://github.com/michellzappa/tinysql) | Native PostgreSQL browser |

## License

MIT
