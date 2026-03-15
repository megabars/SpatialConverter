# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpatialConverter is a macOS SwiftUI app that converts Apple Spatial Video (MV-HEVC from iPhone 15 Pro/16) into Side-by-Side (SBS) stereoscopic video (3840×1080) compatible with DeoVR, Skybox VR, and other VR players.

**Requirements**: macOS 14.0+, Xcode 15+, ffmpeg (optional fallback: `brew install ffmpeg`)

## Build & Run

Open `SpatialConverter.xcodeproj` in Xcode and press ⌘R. There is no CLI build system — this is a pure Xcode project with no test targets.

```bash
xcodebuild -project SpatialConverter.xcodeproj -scheme SpatialConverter -configuration Debug build
```

## Architecture

The conversion pipeline flows through these layers:

```
SwiftUI (UI/) → ConversionQueue (Services/) → ConversionPipeline (Pipeline/)
```

**ConversionPipeline** (actor) orchestrates:
1. **SpatialVideoValidator** — validates MV-HEVC via AVFoundation; checks for hvc1/hev1/dvh1/dvhe/mhvc codec; extracts `SpatialVideoInfo`
2. **SpatialVideoDecoder** (actor) — extracts left/right eye frames via `CMTaggedBufferGroup` (macOS 14 API); falls back to `CMSampleBuffer` attachments (`StereoscopicRightEyeBuffer`); throws `DecoderError.rightViewNotFound` on first frame if dual-view extraction fails
3. **FFmpegFallback** (actor) — invoked automatically when AVFoundation path fails; searches ffmpeg at `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`; uses ffmpeg filter graph (`split` → `hstack`); CRF encoding with `-preset slow`
4. **SBSCompositor** — GPU-accelerated SBS composition via Metal-backed `CIContext`; outputs 3840×1080 (1920×1080 per eye)
5. **SBSEncoder** (actor) — H.264/H.265 MP4 output via `AVAssetWriter`; audio passthrough runs concurrently with video encoding

**ConversionQueue** (`Services/`) is `@MainActor` and processes one file at a time (serial). Frame delivery is pull-based with backpressure — the encoder calls `nextFrame()` on the decoder, controlling pacing.

**Models** (`Models/`):
- `ConversionJob` — `@Observable` class; states: `pending/validating/converting/completed/failed/cancelled`; tracks `usedFallback` and `conversionMethod`
- `ConversionSettings` — codec (H.264/H.265), quality preset (high/balanced/compact), output directory; bitrates: High (35/20 Mbps), Balanced (20/12), Compact (10/6); ffmpeg CRF: 18/23/28
- `SpatialVideoInfo` — duration, frame rate, dimensions, audio track index

## Key Behaviors

- Output files are named `{originalName}_SBS_LR.mp4`; suffix chosen for VR player auto-detection
- Disk space check estimates 1.5× source file size before starting
- App sandbox is **disabled** (entitlements grant unrestricted file I/O)
- Accepted drop/open types: `.movie`, `.mpeg4Movie`, `.quickTimeMovie`, `public.hevc`
- Dock icon drag-and-drop is handled by `AppDelegate` via `NSApplication.open(urls:)` notification
- UI and error messages are localized in Russian
- `Pipeline/README.md` contains Russian-language documentation and architecture diagram
