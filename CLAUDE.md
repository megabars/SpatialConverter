# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SpatialConverter is a macOS SwiftUI app that converts Apple Spatial Video (MV-HEVC from iPhone 15 Pro/16) into Side-by-Side (SBS) stereoscopic video (3840×1080) compatible with DeoVR, Skybox VR, and other VR players.

**Requirements**: macOS 14.0+, Xcode 15+, ffmpeg (optional, for fallback decoding: `brew install ffmpeg`)

## Build & Run

Open `SpatialConverter.xcodeproj` in Xcode and press ⌘R. There is no CLI build system — this is a pure Xcode project.

To build from command line:
```bash
xcodebuild -project SpatialConverter.xcodeproj -scheme SpatialConverter -configuration Debug build
```

## Architecture

The conversion pipeline flows through these layers:

```
SwiftUI (UI/) → ConversionQueue (Services/) → ConversionPipeline (Pipeline/)
```

**ConversionPipeline** orchestrates four pipeline stages:
1. **SpatialVideoValidator** — verifies input is MV-HEVC spatial video via AVFoundation
2. **SpatialVideoDecoder** — extracts left/right eye frames via AVFoundation (primary path)
3. **FFmpegFallback** — alternative decoder invoked when AVFoundation cannot extract stereo views
4. **SBSCompositor** — GPU-accelerated side-by-side compositing using Metal-backed `CIContext`
5. **SBSEncoder** — H.264/H.265 encoding to MP4 via AVAssetWriter with audio passthrough

**ConversionQueue** (in `Services/`) is a `@MainActor` serial queue that processes one file at a time.

**Models** (`Models/`):
- `ConversionJob` — represents a single file conversion task with status/progress
- `ConversionSettings` — codec (H.264/H.265), quality preset (high/balanced/compact), output directory
- `SpatialVideoInfo` — metadata extracted from input file (dimensions, frame rate, stereo layout)

## Key Behaviors

- Output files are named `{originalName}_SBS_LR.mp4`
- Quality presets map to bitrates: High (35/20 Mbps H.264/H.265), Balanced (20/12), Compact (10/6)
- AVFoundation is tried first; ffmpeg fallback is triggered automatically on failure
- The app requires macOS 14 for MV-HEVC spatial video APIs
