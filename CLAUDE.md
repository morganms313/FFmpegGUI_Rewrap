# FFmpegGUI-Rewrap

A desktop GUI for rewrapping and editing metadata in video files (QuickTime `.mov` and MXF `.mxf`) using FFmpeg — without re-encoding unless strictly necessary.

---

## Project Goal

Provide a one-stop-shop for broadcast and post-production professionals to inspect, update, and rewrap video files. Operations should be as non-destructive as possible (stream copy by default), falling back to render/transcode only when the operation requires it.

---

## Tech Stack

- **Language**: Swift
- **UI Framework**: SwiftUI
- **FFmpeg**: Invoked as a subprocess via `Foundation.Process` + `Pipe`
- **FFprobe**: Same subprocess approach for file inspection
- **Platform**: macOS (minimum target TBD — recommend macOS 14 Sonoma for latest SwiftUI APIs)
- **Distribution**: Direct download (notarized .app) — App Store optional later

---

## Core Architecture

### Key Concepts

- **Rewrap** — change container format while stream-copying all essence (no re-encode). Fast and lossless.
- **Metadata patch** — inject or modify container/track-level metadata using FFmpeg `-metadata` flags or `bitstream filters` (e.g., `h264_metadata`, `hevc_metadata`). Some patches require a re-encode or a full decode/re-mux.
- **Render** — full transcode. Used only when a metadata change cannot be achieved via stream copy (e.g., changing color primaries embedded in the bitstream itself, not just the container tag).

### Operation Modes

1. **Stream Copy + Metadata** — fastest, no quality loss (most operations)
2. **Bitstream Filter** — modifies NAL/bitstream headers without full decode (e.g., `h264_metadata`, `hevc_metadata`, `av1_metadata`)
3. **Full Render** — full decode + re-encode (last resort, clearly labeled in UI)

---

## Feature Set

### Container / Rewrap
- Output format selection: `.mov` (QuickTime), `.mxf` (OP1a, OP-Atom), `.mp4`, `.ts`, `.mkv`
- MXF operational pattern selection (OP1a vs OP-Atom)
- Track layout: include/exclude specific video, audio, data, timecode tracks
- Timecode track: add, remove, modify start timecode value
- Timecode source: embedded vs. track-based

### Video Metadata (Container-Level Tags)
- **Color Primaries** — BT.709, BT.2020, BT.601-625, BT.601-525, P3-D65, P3-DCI, XYZ, custom
- **Transfer Characteristics** — BT.709, PQ (SMPTE ST 2084), HLG, BT.2020-10, BT.2020-12, linear, log, S-Log2, S-Log3, V-Log, C-Log, custom
- **Matrix Coefficients** — BT.709, BT.2020 NCL, BT.2020 CL, BT.601-625, BT.601-525, YCGCO, identity (RGB), custom
- **Color Range** — limited (broadcast/TV), full (PC/JPEG)
- **Chroma Sample Location** — left, center, topleft, top, bottomleft, bottom
- **Field order / interlace** — progressive, top-first, bottom-first, unknown
- **Display Aspect Ratio (DAR)** — override container DAR
- **Sample Aspect Ratio (SAR / PAR)** — pixel aspect ratio override
- **Frame rate** — override container-reported frame rate (e.g., 23.976 vs 24)
- **Resolution** — display width/height override (not re-encode)

### Active Format Description (AFD)
- Add AFD track or embedded AFD NAL
- Remove AFD
- Set AFD code: 0–15 (with visual diagram of each AFD value)
- Bar data: add/remove/modify horizontal and vertical bar data values
- SMPTE 2016-1 compliance mode

### HDR Metadata
- **HDR10 / SMPTE ST 2086 Mastering Display Metadata** — display primaries (R/G/B/W), min/max luminance
- **MaxCLL / MaxFALL** (Content Light Level — CEA-861.3)
- **HDR10+ dynamic metadata** — attach/strip SEI
- **Dolby Vision** — RPU metadata passthrough toggle (MXF/MOV)
- **HLG metadata** — system gamma, OOTF parameters

### Audio Metadata
- Audio channel layout — mono, stereo, 5.1, 7.1, LtRt, custom channel map
- Audio language tags — ISO 639-2 language code per track
- Audio track labels / names
- Sample rate override (container tag, not resample)
- Bit depth tag override
- Dialnorm / audio program loudness (Dolby-E, atmos passthrough flags)
- Loudness metadata (LKFS target, true peak) — informational tags

### Timecode
- Start timecode override
- Drop frame vs. non-drop frame flag
- Timecode track: add / remove / replace
- Embedded timecode vs. track timecode

### General File Metadata
- Title, comment, description, copyright, encoder, artist, album, date, genre
- Custom key/value metadata pairs (arbitrary FFmpeg `-metadata key=value`)
- Remove all metadata option
- Preserve original metadata with selective overrides

### Track-Level Metadata
- Per-track: title, language, handler name, disposition flags (default, forced, hearing-impaired, visual-impaired, original, comment, lyrics, karaoke, attached-pic)
- Reorder tracks
- Enable / disable tracks
- Stream disposition: default audio/video/subtitle selection

### MXF-Specific
- Material Package UID (UMID) — preserve or regenerate
- Source Package UID — preserve or regenerate
- OP pattern: OP1a, OP-Atom
- Audio layout: mono tracks vs. multi-channel pairs
- Clip name / reel name
- KLV metadata preservation
- Timecode track (VITC / LTC) mapping

### QuickTime-Specific
- Reel name (QuickTime `com.apple.proapps.clipname`)
- `tmcd` track management
- Spatial video metadata (Apple VR / stereoscopic flags)
- ProRes profile tag (not re-encode, just container tag) — Proxy, LT, 422, 422 HQ, 4444, 4444 XQ
- Camera metadata passthrough (e.g., RED, ARRI, Sony metadata atoms)
- `uuid` atom insertion / removal

### Batch Processing
- Add multiple files to queue
- Apply same metadata settings to all files in batch
- Per-file overrides within a batch
- Output directory selection
- Filename template: `{source_name}_rewrap`, `{source_name}_{date}`, custom
- Conflict resolution: overwrite / skip / rename
- Background queue processing with progress per file

### Inspection / Probe
- FFprobe-based file inspector
- Display all streams with codec, dimensions, frame rate, bit depth, color metadata, language, etc.
- Display container-level metadata
- Display track-level metadata
- Hex/raw KLV inspection mode (MXF)
- Side-by-side diff view: source vs. output after processing

### Presets
- Save named presets for common metadata configurations
- Load / apply preset to current job or batch
- Export / import preset as JSON
- Built-in presets: "Strip all metadata", "BT.709 broadcast safe", "BT.2020 HDR10", "AFD remove", etc.

---

## FFmpeg Command Construction Rules

- Always build the full `ffmpeg` command and display it to the user before executing (transparency)
- Use `-c copy` (stream copy) by default
- Use bitstream filters (`-bsf:v`) where possible before falling back to full render
- Render mode must be explicitly confirmed by the user with a warning dialog
- Never overwrite the source file — always write to a new output path
- Log full FFmpeg stdout/stderr to a session log file

## FFprobe Integration

- Use `ffprobe -v quiet -print_format json -show_streams -show_format` for inspection
- Parse and display all fields with human-readable labels
- Highlight fields that the user has modified (visual diff)

---

## UI/UX Principles

- Two-panel layout: **Source Info** (left) | **Output Settings** (right)
- Clearly distinguish between:
  - Container/tag-level metadata (fast, stream copy)
  - Bitstream-level metadata (fast, BSF)
  - Render-required operations (slow, re-encode) — marked with a warning icon
- Show estimated processing time and operation mode for each setting
- Live FFmpeg command preview updates as settings change
- Progress bar with ETA during processing
- Error handling: surface FFmpeg stderr in a readable way

---

## File & Directory Layout

Swift Package Manager project. Build and run with `make run` (no Xcode required).

```
FFmpegGUI-Rewrap/
├── CLAUDE.md
├── Package.swift
├── Makefile                            # make, make run, make release, make fetch-ffmpeg
├── Info.plist
├── .gitignore
└── Sources/FFmpegGUIRewrap/
    ├── App/
    │   └── FFmpegGUIApp.swift          # @main App entry point + Settings scene
    ├── Models/
    │   ├── AppState.swift              # @Observable root state; uses FFmpegLocator for binary URLs
    │   ├── JobSettings.swift           # All metadata enums + JobSettings struct
    │   ├── MediaFile.swift             # Source file + ProbeData / StreamInfo / FormatInfo
    │   ├── ProcessingJob.swift         # Queue entry with JobStatus
    │   └── Preset.swift                # Preset struct + PresetManager (@Observable)
    ├── Services/
    │   ├── FFmpegLocator.swift         # Priority-ordered binary search (App Support → bundle → Homebrew → which)
    │   └── FFmpegUpdater.swift         # In-app updater; checks/installs from evermeet.cx
    ├── FFmpeg/
    │   ├── FFmpegRunner.swift          # AsyncStream-based subprocess runner
    │   ├── FFprobeParser.swift         # Runs ffprobe, decodes JSON → ProbeData
    │   └── CommandBuilder.swift        # JobSettings → [String] argv + BuildResult
    ├── Views/
    │   ├── ContentView.swift           # NavigationSplitView root (sidebar + detail)
    │   ├── JobDetailView.swift         # Tab view: Settings / Inspector + Process button
    │   ├── QueueView.swift             # Sidebar file queue list
    │   ├── InspectorView.swift         # FFprobe data display
    │   ├── MetadataFormView.swift      # Grouped Form wrapping all section views
    │   ├── CommandPreviewView.swift    # Live FFmpeg command + log output
    │   └── Sections/
    │       ├── ContainerSectionView.swift
    │       ├── ColorMetadataSectionView.swift
    │       ├── AFDSectionView.swift
    │       ├── HDRSectionView.swift
    │       ├── AudioSectionView.swift
    │       ├── TimecodeSectionView.swift
    │       ├── MXFSectionView.swift
    │       ├── QuickTimeSectionView.swift
    │       └── GeneralMetadataSectionView.swift
    ├── Presets/
    │   └── BuiltinPresets.swift        # Six built-in preset constants
    ├── Utils/
    │   └── Extensions.swift            # OptionalPicker, OptionalTextField, IntegerField,
    │                                   # DecimalField, SettingsView (with update UI)
    └── Resources/
        └── bin/                        # FFmpeg binaries (git-ignored; run `make fetch-ffmpeg`)
            ├── ffmpeg
            └── ffprobe
```

---

## FFmpeg Binary Management

Two-location strategy so user updates don't break the signed app bundle:

| Location | Purpose | Writable |
|----------|---------|---------|
| `<app bundle>/Contents/Resources/bin/` | Factory default, shipped with app, code-signed | No |
| `~/Library/Application Support/FFmpegGUI-Rewrap/bin/` | User-updated via in-app updater | Yes |

`FFmpegLocator` searches App Support first, then bundle, then common Homebrew paths, then `which`.

### Bootstrapping binaries for development

```sh
make fetch-ffmpeg   # downloads ffmpeg + ffprobe from evermeet.cx into Sources/.../Resources/bin/
make                # builds .app and copies binaries into Contents/Resources/bin/
make run            # builds + launches immediately
```

Binaries are ~80 MB total and are excluded from git via `.gitignore`.

### In-app updater

`FFmpegUpdater` checks `https://evermeet.cx/ffmpeg/info/<tool>/release` for the latest version,
compares it to the running binary, and streams the download with progress. Updated binaries are
installed into App Support (not the signed bundle) so no re-signing is required.

---

## Development Notes

- Run `make fetch-ffmpeg` once after cloning to get the bundled binaries
- Target FFmpeg 6.x+ for full HDR metadata and MXF support
- MXF output requires `libavformat` with MXF muxer enabled (verify at startup)
- For Dolby Vision / HDR10+ passthrough, ffmpeg must be built with appropriate support
- Distribution: requires Apple Developer ID signing + notarization for sharing with non-technical users
