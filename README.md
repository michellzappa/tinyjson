# TinyJSON

A minimal, fast JSON editor for macOS.

![macOS](https://img.shields.io/badge/macOS-26%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

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

## License

MIT
