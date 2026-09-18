<div align="center">
  <a href="https://github.com/iTsawaysu/XTools">
    <img src="Assets/AppIcon/XToolsIconPreview.png" width="128" height="128" alt="XTools Icon" />
  </a>
  <h1>XTools</h1>
  <p><em>A quiet, native macOS developer toolbox. Fast, local-first, and keyboard-driven.</em></p>

  <p>
    <a href="https://github.com/iTsawaysu/XTools/releases"><img src="https://img.shields.io/github/v/release/iTsawaysu/XTools?style=flat-square&color=black" alt="Release"></a>
    <a href="https://github.com/iTsawaysu/XTools/stargazers"><img src="https://img.shields.io/github/stars/iTsawaysu/XTools?style=flat-square&color=orange" alt="Stars"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
    <img src="https://img.shields.io/badge/macOS-13.0%2B-orange?style=flat-square" alt="macOS 13+">
    <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  </p>
</div>

## Why

Developers constantly run into small, recurring tasks: formatting JSON, converting timestamps, decoding Base64, testing regexes, generating UUIDs, or inspecting HTTP status codes.

Opening browser tabs for routine transformations is tedious and can expose sensitive data (tokens, configs, keys) to third-party services. XTools keeps those transformations on the Mac and uses native macOS controls instead of a browser-based shell.

XTools packs 46 developer utilities into a single native macOS application. Most tools work entirely offline. Network access is limited to actions you initiate from HTML → Markdown: fetching an HTTP(S) URL that passes the host safety policy or explicitly allowing remote images in the current preview. Use `Cmd + K` in the app to open any tool quickly.

## Quick Start

### 1. Download DMG (Recommended)

Download the latest DMG from [GitHub Releases](https://github.com/iTsawaysu/XTools/releases/latest), open it, and drag XTools into `Applications`. Supports macOS 13.0+ on Apple Silicon and Intel.

### 2. Build from Source

Requires macOS 13+ and Xcode 16+.

```bash
git clone https://github.com/iTsawaysu/XTools.git
cd XTools
./build.sh           # Incremental debug build, package, and open the app
./build.sh build     # Incremental debug build and package without opening
./build.sh release   # Incremental release build and package without opening
swift test           # Run the complete automated test suite
```

Packaged builds are written to `build/XTools.app`.

## Features

- **Swift 6 Native**: Built with SwiftUI and AppKit, with core algorithms separated into the `XToolsCore` package.
- **Local-First**: Cryptography, hashing, formatting, diffing, regex evaluation, and image processing execute on-device. XTools includes no telemetry or cloud tracking. HTML URL fetching and remote preview images require an explicit user action; the host policy blocks local or private address literals and known metadata hosts.
- **Keyboard-First**: Press `Cmd + K` in the app for fuzzy search across all tools. Use `Cmd + 1` through `Cmd + 7` to switch categories, and `Cmd + Return` to run primary actions.
- **Clay Design System**: Shared workbench components provide consistent panels, controls, diagnostics, keyboard focus, and accessibility behavior.
- **46 Built-in Utilities**: Curated essentials across conversions, cryptography, developer tools, Web debugging, image handling, time math, and system inspectors.
- **Automated Coverage**: Core logic and UI contracts are backed by over 1,900 automated tests.

## Tool Catalog

| Category | Tools |
| :--- | :--- |
| **Converters (8)** | Base64 File, Base64 String, URL Encoder/Decoder, ASCII & Binary, Unicode Converter, Base Converter, Roman Numerals, Case Converter |
| **Crypto & Generators (6)** | Hash Text (MD5, SHA-1/256/512), AES Text Encryption, String Obfuscator, Token Generator, UUID Generator, Password Generator |
| **Development (12)** | JSON Formatter, SQL Prettifier, XML Formatter, YAML Formatter, JSON Diff, Text Diff, Regex Tester, Docker Run ↔ Compose, HTML → Markdown, Crontab Generator, Random Port, Chmod Calculator |
| **Web (5)** | JWT Parser & Signer, Basic Auth Generator, HTTP Status Codes, User-Agent Parser, Keycode Inspector |
| **Image & Color (6)** | Image Format Converter (PNG, JPEG, WebP), Smart Compressor, Watermark, Grayscale Generator, Favicon Suite Generator, Color Converter (HEX, RGB, HSL) |
| **Time & Date (4)** | Unix Timestamp Converter (s/ms), Timezone Viewer, Date Calculator, Chronometer & Stopwatch |
| **Utilities (5)** | Device & Hardware Info, MIME File Type Detector, Math Evaluator, Text Statistics, Emoji & Symbol Catalog |

## Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `Cmd + K` | **Command Palette** | Global search across all 46 tools and commands |
| `Cmd + 0` | **Workbench** | Return to dashboard with recent and favorite tools |
| `Cmd + 1` – `Cmd + 7` | **Switch Category** | Jump directly to any tool category |
| `Cmd + F` | **Filter Sidebar** | Focus the sidebar search filter |
| `Cmd + B` | **Toggle Sidebar** | Expand to full-width distraction-free workspace |
| `Cmd + Return` | **Primary Action** | Run format, generate, encrypt, or convert |
| `Cmd + ,` | **Preferences** | Toggle appearance, workbench cards, and settings |
| `Esc` | **Dismiss** | Close command palette or reset current focus |

## Contributing

Contributions, bug reports, and tool suggestions are welcome!

1. Fork the repository and create your feature branch.
2. Follow the established code style and keep core algorithms inside `XToolsCore`.
3. Run `swift test` before submitting to ensure all tests pass.

## License

[XTools](https://github.com/iTsawaysu/XTools) is released under the [MIT License](LICENSE).
