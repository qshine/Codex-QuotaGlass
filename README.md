# QuotaGlass

[English](README.md) · [简体中文](README.zh-CN.md)

QuotaGlass is a lightweight native macOS desktop hourglass that keeps your remaining Codex quota visible at a glance.

![QuotaGlass displayed on the macOS desktop](docs/images/quotaglass-desktop.png)

## Download

Download the latest Apple Silicon DMG from [GitHub Releases](https://github.com/qshine/Codex-QuotaGlass/releases/latest).

## Features

- Displays the most constrained Codex quota window as an animated hourglass.
- Updates after live rate-limit notifications, with a 45-second fallback refresh.
- Shows the remaining percentage, quota window, and reset countdown.
- Lets you drag the entire card and restores its position across launches.
- Keeps a single desktop widget across all Spaces.
- Provides refresh, launch-at-login, open-client, and quit actions from the right-click menu.
- Marks old data as stale instead of presenting it as live.

## Requirements

- Apple Silicon Mac
- macOS 14 or newer
- The official ChatGPT/Codex desktop app installed and signed in

## How quota is selected

QuotaGlass reads quota information from the locally installed official Codex App Server. When several quota windows are available, it displays the one with the lowest remaining percentage. Ties prefer the window with the later reset time, then the primary window.

## Privacy

QuotaGlass has no analytics and no cloud service. It does not read browser cookies, ChatGPT databases, or authentication tokens. Only normalized quota values, reset times, widget position, and the launch-at-login preference are stored locally.

## Distribution note

Version 0.0.1 is an Apple Silicon preview distributed with an ad-hoc signature. It has not yet been notarized with an Apple Developer ID.
