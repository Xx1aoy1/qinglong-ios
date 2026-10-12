<div align="center">

<img src="docs/icon.png" width="96" alt="QingLong iOS icon" />

# QingLong for iOS

**A third-party iOS client for the [QingLong](https://github.com/whyour/qinglong) panel · Native SwiftUI · Unsigned IPA ready for TrollStore**

[![Build Unsigned IPA](https://github.com/Xx1aoy1/qinglong-ios/actions/workflows/build-ipa.yml/badge.svg)](../../actions/workflows/build-ipa.yml)
![iOS](https://img.shields.io/badge/iOS-15.0%2B-0FA894)
![Swift](https://img.shields.io/badge/Swift-5.5%2B-F05138)
![License](https://img.shields.io/badge/License-MIT-2BD4BC)
![Dependencies](https://img.shields.io/badge/third--party%20deps-0-12B7A8)

[中文文档](README.md) · **English**

</div>

---

## Overview

QingLong for iOS is an open-source iOS client written from scratch for managing your self-hosted [QingLong](https://github.com/whyour/qinglong) panel from an iPhone or iPad.

- **Zero third-party dependencies** — built entirely on system frameworks (SwiftUI, Security, UIKit), no package manager involved
- **iOS 15.0 and later** — universal for iPhone and iPad, with automatic dark mode support
- **Unsigned IPA** — CI produces a `.ipa` directly; install it with [TrollStore](https://github.com/opa334/TrollStore), **no developer certificate required**
- **Direct connection** — every byte comes from the panel you deployed yourself; the client never routes through an intermediary server

## Features

| Module | Capabilities |
| --- | --- |
| 🏠 Dashboard | Panel status, task / environment / subscription / dependency counts, recent runs, quick actions |
| ⏰ Scheduled tasks | List filters (running / enabled / disabled / pinned / from subscription), run and stop, enable, disable and pin, create and edit (cron / `@once` / `@boot`, labels, pre- and post-commands, multiple instances, working directory), live log tailing, historical logs, running instance management |
| 📦 Environment variables | Full CRUD, enable and disable, labels, pinning, ordering, batch operations, JSON and `name=value` import/export, masked value display |
| 🔄 Subscriptions | Create (public repo / private repo / single file), crontab and fixed-interval schedules, whitelist and blacklist, manual pull and stop, pull logs |
| 📜 Scripts | Directory tree browsing, in-app editing and saving, run scripts directly and inspect output, create files and folders, rename, upload, download, delete |
| 🧩 Dependencies | Install, reinstall, uninstall and cancel for NodeJS / Python3 / Linux dependencies, with live install-log tracking |
| 🗂 Log browser | Browse every log file on the panel by directory, copy / share / export |
| ⚙️ Panel settings | Panel title, language, time zone, log retention, task concurrency, dependency proxy, Node / Python / Linux mirror sources (streamed output), SSH private key, dependency-cache cleanup, panel reload, update check |
| 🔔 Notifications | Complete field configuration for **22 notification channels** (ServerChan, Bark, PushDeer, Telegram, DingTalk, WeCom, Feishu, gotify, ntfy, pushplus, and more) — save and test in one step |
| 🔐 Account security | Change username and password, two-factor authentication (TOTP setup / activation / unbinding), login history, IP blocklist |
| 🔗 Open API | Open-app and credential management (client_id / client_secret / scopes / key reset) |
| 🛠 Operations toolkit | Command debugging (streamed output + command history), data backup and restore (tgz import/export), panel system logs |
| 🖥 Multiple servers | Store several panel addresses at once, switch with a single tap; credentials are kept separately in the system keychain |

## Installation

### Prerequisites

Your device must already have **TrollStore** installed. This app ships as an unsigned IPA; TrollStore signs it during installation. Do **not** use certificate-based tools such as AltStore or Sideloadly.

### Getting the IPA

Download the latest `QingLong-<version>.ipa` from the [Releases](../../releases) page.

### Steps

1. Transfer the IPA to your device (AirDrop, the Files app, iMazing, Filza — anything works)
2. Open **TrollStore** → tap `+` → pick the IPA → **Install**
3. Launch QingLong for iOS, add your panel address (for example `http://192.168.1.10:5700`) and sign in
4. If iOS asks for local network permission on first launch, allow it (required to reach a panel on your LAN)

> ATS restrictions are lifted by default, so plain HTTP addresses and panels using self-signed certificates both connect directly.

## Building from Source

### Local build on macOS

```bash
# Dependencies
brew install xcodegen ldid

# Build (unsigned / arm64)
./Scripts/build_ipa.sh
# Or pin a version
VERSION=1.0.0 ./Scripts/build_ipa.sh

# Output
# dist/QingLong-1.0.0.ipa
```

### Automatic builds with GitHub Actions

The repository ships with [.github/workflows/build-ipa.yml](.github/workflows/build-ipa.yml):

| Trigger | Behaviour |
| --- | --- |
| Push to `main` / `master` | Builds the unsigned IPA and uploads it as an artifact (kept for 90 days) |
| Push a `v*` tag (e.g. `v1.0.0`) | Build → verify the bundle structure → create a GitHub Release with the IPA attached |
| Manual run (`workflow_dispatch`) | Supply a `release_tag` to publish a Release, or leave it empty to only produce an artifact |
| Pull request | Build and verify only, no publishing |

> The project is managed with [XcodeGen](https://github.com/yonaskolb/XcodeGen). `project.yml` is the single source of truth; `.xcodeproj` is listed in `.gitignore`, so never edit or commit it by hand.

### Regenerating the app icon

```bash
pip install pillow
python Scripts/generate_assets.py
```

## Releasing

Push a `v*` tag and the release happens automatically — no certificate or extra configuration needed:

```bash
git tag -a v1.0.0 -m "QingLong iOS 1.0.0"
git push origin v1.0.0
```

CI then builds the app, verifies the bundle structure, and creates a GitHub Release with `QingLong-<version>.ipa` attached.

## Project Structure

```
.
├── project.yml                     # XcodeGen project definition (single source of truth)
├── Support/
│   ├── Info.plist
│   └── QingLong.entitlements
├── QingLong/
│   ├── App/                        # Entry point and global session
│   │   ├── QingLongApp.swift
│   │   ├── RootView.swift
│   │   └── AppSession.swift        # Auth state / multi-server / toast
│   ├── Core/
│   │   ├── App/                    # AppInfo, DateFormatting, ListCache
│   │   ├── Auth/                   # KeychainStore / ServerConfig
│   │   ├── Models/                 # All data models (fault-tolerant decoding)
│   │   ├── Network/                # APIClient / Endpoint / QLResponse / Multipart
│   │   └── Services/               # Seven feature services (mapping 146 panel routes)
│   ├── Components/                 # Status pills / empty states / loading / toast / prompt sheets
│   ├── Design/                     # Design tokens: Theme / colours / view modifiers
│   ├── Features/
│   │   ├── Server/                 # Server list and editor
│   │   ├── Login/                  # Sign-in / two-factor / panel initialisation
│   │   ├── Main/                   # Root TabView
│   │   ├── Dashboard/              # Overview
│   │   ├── Crons/                  # Task list / detail / editor
│   │   ├── Envs/                   # Variable list / editor / detail / import
│   │   ├── Subscriptions/          # Subscription list / editor / detail
│   │   ├── Scripts/                # Script browser / in-app editor
│   │   ├── Dependencies/           # Dependency management
│   │   ├── Logs/                   # Log console / log browser
│   │   └── Settings/               # Panel settings / notifications / security / open API / command runner / backup / system logs / about
│   └── Resources/
│       └── Assets.xcassets         # AppIcon / AccentColor / LaunchBackground
├── Scripts/
│   ├── build_ipa.sh                # One-shot macOS build
│   └── generate_assets.py          # Icon generation
├── .github/workflows/build-ipa.yml # CI: build / verify / release
└── LICENSE                         # MIT
```

## Implementation Notes

- **Authentication** — `POST /api/user/login` returns a JWT, sent back as `Authorization: Bearer`. Credentials live in the `kSecClassGenericPassword` keychain.
- **Platform slots** — the panel separates `mobile` and `desktop` token slots by User-Agent (ten tokens each). The client always sends an `iOS` User-Agent so tokens land in the mobile slot.
- **Unified response envelope** — `{ code, message?, data? }`, where `code == 200` means success. Log endpoints additionally return `logStatus / offset / nextOffset / total / truncated` at the top level, handled by a dedicated `sendRaw` path.
- **Streaming output** — endpoints such as `/api/system/command-run` are consumed as an `AsyncThrowingStream` and rendered line by line.
- **Fault-tolerant decoding** — every panel entity implements a hand-written `init(from:)` that decodes each field with `try?`, so a missing backend field can never take down a whole screen.
- **Incremental log tailing** — logs are fetched by increasing `nextOffset`; a `truncated` response resets the buffer, and anything beyond 2 MB is trimmed to the most recent 1 MB to bound memory usage.
- **iOS 15 compatibility** — `FlowLayout` sits behind an `@available(iOS 16)` branch, and every `alert` + `TextField` combination uses a purpose-built `PromptSheet` component instead.

## Performance Notes

QingLong panels can hold hundreds of tasks, and a few of the panel's own endpoints are genuinely expensive. A few deliberate choices keep the UI responsive:

- **List caching, in memory *and* on disk** (`ListCache`) — list view models prime themselves from the previous result, so revisiting a tab is instant and a cold launch shows content immediately instead of a blank screen. Switching servers or signing out clears it.
- **Decoding off the main thread** — `GET /api/dependencies` returns each dependency's *entire* install log (`DependenceModel.findAll()` includes the `log` JSON column), and the panel additionally shells out to probe each installed dependency on every request (`refreshInstalledStatuses`). The resulting multi-megabyte response is decoded on a background queue, never on the main thread.
- **Derived data computed once** — filters, label sets and per-chip counts are computed in a single pass and cached, instead of being recomputed on every SwiftUI render.
- **Debounced search** — text input is debounced by 180 ms so that typing does not trigger a full re-sort per keystroke.
- **Stale-while-revalidate** — entering a screen reuses cached data and refreshes silently in the background, which also avoids hammering expensive endpoints such as `/api/dependencies`.
- **Cheap rows** — tag chips render as a single-line `HStack` with a `+N` overflow indicator rather than a wrapping flow layout, removing one measurement pass per row while scrolling.

## Relationship to the Upstream Project

This is a **third-party client** for the QingLong panel. It is not affiliated with, partnered with, or endorsed by [whyour/qinglong](https://github.com/whyour/qinglong) or its author. All data displayed in the app comes from the panel service you deploy yourself; the client collects and uploads no account information.

## License

[MIT](LICENSE)
