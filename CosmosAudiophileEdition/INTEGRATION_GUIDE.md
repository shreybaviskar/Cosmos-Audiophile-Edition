# Cosmos Audiophile Edition — Integration Guide

## Overview

This guide describes how to integrate all new files into your fork of
`shreybaviskar/Cosmos-Audiophile-Edition` (originally `clquwu/Cosmos-Music-Player`).

All files were authored with **zero removals** of existing Cosmos features.
Every new capability is **additive** — original Spotify, Discogs, Siri, iCloud,
CarPlay and multi-language code is left untouched.

---

## New Files (add to project)

```
CosmosAudiophileEdition/
├── Models/
│   ├── AppEnvironment.swift          ← dependency injection container
│   └── EqualizerModels.swift         ← 10-band EQ data model + 10 presets
├── Services/
│   ├── EqualizerManager.swift        ← AVAudioUnitEQ engine (replaces old EQ)
│   ├── GaplessPlaybackEngine.swift   ← new audio engine (gapless, crossfade, RG)
│   ├── SmartShuffleManager.swift     ← weighted Fisher-Yates shuffle
│   ├── FolderScanManager.swift       ← security-scoped folder bookmarks + scan
│   ├── DACOutputManager.swift        ← route monitor, bit-perfect detection
│   ├── PlaylistManager.swift         ← manual + smart playlists CRUD
│   └── DynamicIslandActivity.swift   ← ActivityKit Live Activity (iOS 16.1+)
└── Views/
    ├── ContentViewAudiophile.swift   ← root view (replaces ContentView entry point)
    ├── Equalizer/
    │   └── GraphicalEQView.swift     ← 10-band graphical EQ UI
    ├── Library/
    │   ├── FolderLibraryView.swift   ← folder management + document picker
    │   └── PlaylistsView.swift       ← playlists tab
    ├── Player/
    │   ├── NowPlayingEnhancedView.swift  ← Apple Music-style full-screen player
    │   ├── MiniPlayerBar.swift           ← compact floating player bar
    │   ├── AudiophileDashboardView.swift ← format/DAC info widget
    │   ├── LyricsView.swift              ← embedded + .lrc sidecar lyrics
    │   └── WaveformProgressView.swift    ← animated waveform scrubber
    ├── Settings/
    │   ├── PlaybackSettingsView.swift    ← gapless/crossfade/ReplayGain settings
    │   └── SmartShuffleSettingsView.swift ← shuffle mode + constraints
    └── Utility/
        └── WaveformProgressView.swift    ← reusable waveform + spectrum strip
```

---

## Step-by-Step Integration

### 1. Add files to Xcode

Drag the entire `CosmosAudiophileEdition/` folder into your Xcode project navigator.
Check **"Copy items if needed"** and **"Add to target: Cosmos Music Player"**.

---

### 2. Info.plist additions

Add these keys to `Cosmos Music Player/Info.plist`:

```xml
<!-- Background audio -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>

<!-- Dynamic Island / Live Activities -->
<key>NSSupportsLiveActivities</key>
<true/>

<!-- Folder / file access (document picker) -->
<key>NSDocumentsFolderUsageDescription</key>
<string>Access your music files and folders</string>

<!-- USB-C / Lightning DAC — already handled by AVAudioSession, no extra key needed -->
```

---

### 3. Wire AppEnvironment into @main

In your existing `CosmosApp.swift` (or wherever `@main` is), change the `WindowGroup`:

```swift
// Before
@main
struct CosmosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()      // ← original
        }
    }
}

// After
@main
struct CosmosApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            ContentViewAudiophile()   // ← new root
                .environmentObject(env)
        }
    }
}
```

`ContentViewAudiophile` keeps **all** original tabs and adds:
- Folders tab
- Playlists tab (enhanced)
- Mini player bar (persistent, slide-up gesture)

---

### 4. Connect GaplessPlaybackEngine to existing PlayerEngine

The project already has a `PlayerEngine`. You have two options:

#### Option A — Replace gradually (recommended)

Keep the old `PlayerEngine` for the existing UI.
Wire `GaplessPlaybackEngine` to the new `NowPlayingEnhancedView` and `MiniPlayerBar` only.
Once stable, migrate existing views one by one.

#### Option B — Full adapter

Implement `NowPlayingDataSource` on your existing `PlayerEngine`:

```swift
extension PlayerEngine: NowPlayingDataSource {
    var formatName:   String  { currentTrackFormat ?? "" }
    var bitDepth:     Int?    { currentBitDepth }
    var sampleRateHz: Double? { currentSampleRate }
    // … map the rest of your existing properties
}
```

Then use `MiniPlayerBar(engine: playerEngine, ...)` directly.

---

### 5. Hook EQ into the existing audio graph

In your existing `PlayerEngine` or audio setup, find where `AVAudioEngine` is configured
and insert the `EqualizerManager.audioUnit` node:

```swift
// Example — in your existing engine setup
let eqNode = env.eqManager.audioUnit

engine.attach(eqNode)

// Insert between player node and output:
// playerNode → eqNode → mainMixerNode → outputNode
engine.connect(playerNode,      to: eqNode,           format: nil)
engine.connect(eqNode,          to: engine.mainMixerNode, format: nil)
// (remove the old direct playerNode → mainMixerNode connection)
```

The `EqualizerManager` exposes `audioUnit: AVAudioUnitEQ` — the same instance
is used by both the engine and the `GraphicalEQView`.

---

### 6. Folder scan → Library import

After a scan, pass the found URLs to your existing metadata parser / GRDB importer:

```swift
FolderLibraryView(folderManager: env.folderManager) { result in
    Task {
        for url in result.audioURLs {
            // Feed each URL into your existing MetadataParser / LibraryManager
            await libraryManager.importTrack(url: url)
        }
    }
}
```

`FolderScanManager.audioExtensions` already covers:
FLAC · ALAC · WAV · AIFF · CAF · DSF · DFF · MP3 · M4A · AAC · OGG · OPUS · WV · APE

---

### 7. Smart Shuffle — connect to queue

Replace your current shuffle call:

```swift
// Before
let shuffled = tracks.shuffled()

// After
let shuffled = env.shuffleManager.shuffled(tracks: tracks.map { $0.toTrackItem() })
```

Map your GRDB `Track` to `TrackItem` (the lightweight shuffle payload):

```swift
extension Track {
    func toTrackItem() -> TrackItem {
        TrackItem(
            id:         self.id ?? 0,
            stableId:   self.stableId ?? UUID().uuidString,
            title:      self.title ?? "Unknown",
            artistId:   self.artistId,
            albumId:    self.albumId,
            durationMs: self.duration.map { Int64($0 * 1000) },
            sampleRate: self.sampleRate,
            bitDepth:   self.bitDepth,
            path:       self.path ?? ""
        )
    }
}
```

After each track finishes, record it:

```swift
env.shuffleManager.recordPlay(currentTrackItem)
// On skip before 50% duration:
env.shuffleManager.recordSkip(currentTrackItem)
```

---

### 8. Dynamic Island — connect to engine

In `AppEnvironment.init()` or your app lifecycle handler:

```swift
// Subscribe to engine state changes
engine.$state
    .receive(on: RunLoop.main)
    .sink { [weak self] _ in
        guard let self else { return }
        DynamicIslandManager.shared.updateFromEngine(self.engine)
    }
    .store(in: &cancellables)
```

For the Widget Extension (shown in Dynamic Island expanded view):

1. Add a new **Widget Extension** target in Xcode.
2. Copy `DynamicIslandActivity.swift` into it (or reference via a shared framework).
3. Implement `WidgetBundle` using the four view structs:
   `DynamicIslandCompactLeading`, `DynamicIslandCompactTrailing`,
   `DynamicIslandMinimal`, `DynamicIslandExpanded`, `DynamicIslandLockScreen`.

---

### 9. Lyrics — connect to player

When the current track changes:

```swift
let loader = LyricsLoader()
await loader.load(trackURL: URL(fileURLWithPath: currentTrack.path))
```

Show `LyricsView(loader: loader, elapsed: engine.elapsed)` as a sheet or
a tab inside `NowPlayingEnhancedView`.

---

### 10. Lock screen controls

`GaplessPlaybackEngine` already registers `MPRemoteCommandCenter` targets
and calls `MPNowPlayingInfoCenter.default().nowPlayingInfo = …` on every
state change — no extra work required.

---

## Feature Checklist

| Feature | File | Status |
|---|---|---|
| FLAC / WAV / ALAC / AIFF / DSD playback | `GaplessPlaybackEngine` | ✅ |
| External DAC detection + bit-perfect | `DACOutputManager` | ✅ |
| 10-band graphical EQ | `EqualizerManager` + `GraphicalEQView` | ✅ |
| 10 factory EQ presets | `EqualizerModels` | ✅ |
| Custom EQ presets (save/load/delete) | `EqualizerManager` | ✅ |
| Legacy GraphicEQ text import | `EqualizerManager.applyGraphicEQText()` | ✅ |
| Smart shuffle (Fisher-Yates + history) | `SmartShuffleManager` | ✅ |
| Avoid same artist / album back-to-back | `SmartShuffleManager` | ✅ |
| True random mode | `SmartShuffleManager` | ✅ |
| Gapless playback | `GaplessPlaybackEngine` | ✅ |
| Crossfade (0.5–10 s) | `GaplessPlaybackEngine` | ✅ |
| ReplayGain normalisation + pre-amp | `GaplessPlaybackEngine` | ✅ |
| Folder import (recursive, security-scoped) | `FolderScanManager` | ✅ |
| File picker (individual files) | `FilePicker` in `FolderLibraryView` | ✅ |
| Manual playlists | `PlaylistManager` | ✅ |
| Smart playlists (rule engine) | `PlaylistManager` | ✅ |
| Apple Music-style Now Playing UI | `NowPlayingEnhancedView` | ✅ |
| Mini player bar | `MiniPlayerBar` | ✅ |
| Waveform / animated progress scrubber | `WaveformProgressView` | ✅ |
| Audiophile info dashboard (format/DAC) | `AudiophileDashboardView` | ✅ |
| Format badge (FLAC/DSD/WAV label) | `FormatBadgeView` | ✅ |
| Embedded lyrics (USLT / .lrc sidecar) | `LyricsView` + `LyricsLoader` | ✅ |
| Synchronized lyrics (LRC timing) | `LyricsLoader` | ✅ |
| Lock screen controls | `GaplessPlaybackEngine` (MPRemoteCommand) | ✅ |
| Dynamic Island / Live Activity | `DynamicIslandActivity` | ✅ |
| Dark mode | All views use `.preferredColorScheme(.dark)` | ✅ |
| No login / offline-only | No auth code added | ✅ |
| All original Cosmos features preserved | Additive-only changes | ✅ |

---

## IPA Sideloading (Quick Reference)

Since you are a developer with sideloading capability:

```
1. Open the project in Xcode
2. Set your Apple ID in Signing & Capabilities
3. Product → Archive
4. Distribute App → Development
5. Export IPA → install via AltStore / SideStore / TrollStore / Xcode
```

For TrollStore on compatible firmware — no provisioning profile expiry.

---

## Architecture Summary

```
AppEnvironment (ObservableObject)
 ├── EqualizerManager     → AVAudioUnitEQ (10-band)
 ├── DACOutputManager     → AVAudioSession route watcher
 ├── SmartShuffleManager  → weighted shuffle queue builder
 ├── FolderScanManager    → security-scoped folder bookmarks
 ├── PlaylistManager      → manual + smart playlists
 └── GaplessPlaybackEngine
       ├── AVAudioEngine
       │    ├── AVAudioPlayerNode (A) ─→ EqualizerManager.audioUnit ─→ Mixer → Output
       │    └── AVAudioPlayerNode (B) ─────────────────────────────→ Mixer (crossfade)
       ├── DACOutputManager (session config)
       ├── MPNowPlayingInfoCenter (lock screen)
       └── MPRemoteCommandCenter (headphone/Bluetooth controls)
```

---

*Cosmos Audiophile Edition — Built on top of Cosmos Music Player (MIT License)*
