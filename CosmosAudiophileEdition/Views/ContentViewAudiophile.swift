// ContentViewAudiophile.swift — Cosmos Audiophile Edition
// Root view — wraps the original Cosmos tabs and injects:
//   • Folders tab
//   • Playlists tab (enhanced)
//   • Mini player bar above tab bar
//   • Audiophile branding
//
// HOW TO USE:
//   Replace your existing CosmosApp @main's WindowGroup body with:
//     ContentViewAudiophile()
//         .environmentObject(AppEnvironment())

import SwiftUI

struct ContentViewAudiophile: View {

    @EnvironmentObject var env: AppEnvironment
    @State private var selectedTab: Tab = .library

    enum Tab: Int, Hashable {
        case library, playlists, folders, settings
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                // ─── Library ───────────────────────────────────────────
                LibraryTabView(env: env)
                    .tabItem {
                        Label("Library", systemImage: "music.note.house.fill")
                    }
                    .tag(Tab.library)

                // ─── Playlists ──────────────────────────────────────────
                PlaylistsView(playlistManager: env.playlistManager)
                    .tabItem {
                        Label("Playlists", systemImage: "music.note.list")
                    }
                    .tag(Tab.playlists)

                // ─── Folders ───────────────────────────────────────────
                FolderLibraryView(folderManager: env.folderManager) { result in
                    // After a scan, pass the found URLs back to your DB importer
                    print("Scan complete: \(result.audioURLs.count) tracks found in \(String(format: "%.1f", result.scanDuration))s")
                }
                .tabItem {
                    Label("Folders", systemImage: "folder.fill")
                }
                .tag(Tab.folders)

                // ─── Settings ──────────────────────────────────────────
                SettingsTabView(env: env)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)
            }
            .tint(.orange)

            // ─── Mini Player Bar ────────────────────────────────────────
            VStack(spacing: 0) {
                EngineAdaptedMiniPlayer(env: env)
                // Spacer the height of the system tab bar
                Color.clear.frame(height: 49)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Library Tab

struct LibraryTabView: View {
    let env: AppEnvironment

    // Maps to your existing library pages (Songs, Albums, Artists, Genres)
    // We keep the original Cosmos library view and just add the audiophile bar.
    var body: some View {
        // Replace the body of this with your existing LibraryView()
        // For now, placeholder:
        NavigationView {
            Text("Library — Keep your existing LibraryView here")
                .navigationTitle("Library")
        }
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    let env: AppEnvironment

    var body: some View {
        NavigationView {
            List {
                Section("Audio") {
                    NavigationLink("Playback") {
                        PlaybackSettingsView(
                            engine:     env.engine,
                            dacManager: env.dacManager
                        )
                    }
                    NavigationLink("Equalizer") {
                        GraphicalEQView(eqManager: env.eqManager)
                    }
                    NavigationLink("Shuffle") {
                        SmartShuffleSettingsView(shuffleManager: env.shuffleManager)
                    }
                }

                Section("Library") {
                    NavigationLink("Folders") {
                        FolderLibraryView(folderManager: env.folderManager)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: "Audiophile Edition")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Engine Adapted Mini Player
// Bridges GaplessPlaybackEngine to the NowPlayingDataSource protocol

struct EngineAdaptedMiniPlayer: View {
    let env: AppEnvironment

    var body: some View {
        if env.engine.currentTrack != nil {
            MiniPlayerBar(
                engine:     EngineNowPlayingAdapter(engine: env.engine),
                eqManager:  env.eqManager,
                dacManager: env.dacManager,
                shuffleMgr: env.shuffleManager
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - NowPlayingDataSource Adapter
// Wraps GaplessPlaybackEngine to satisfy the protocol.

final class EngineNowPlayingAdapter: NowPlayingDataSource {
    private let engine: GaplessPlaybackEngine

    init(engine: GaplessPlaybackEngine) {
        self.engine = engine
    }

    // Forward all published properties
    var currentTitle:    String   { engine.currentTitle  }
    var currentArtist:   String   { engine.currentArtist }
    var currentAlbum:    String   { engine.currentAlbum  }
    var currentArtwork:  UIImage? { engine.currentArtwork }
    var isPlaying:       Bool     { engine.state == .playing }
    var progress:        Double   { engine.progress }
    var duration:        Double   { engine.duration }
    var elapsed:         Double   { engine.elapsed  }
    var formatName:      String   { engine.formatName   }
    var bitDepth:        Int?     { engine.bitDepth     }
    var sampleRateHz:    Double?  { engine.sampleRateHz }
    var isShuffling:     Bool     { engine.isShuffling  }
    var repeatMode:      RepeatMode { engine.repeatMode }

    // Passthrough actions
    func togglePlayPause() { engine.togglePlayPause() }
    func skipNext()        { engine.skipNext()        }
    func skipPrevious()    { engine.skipPrevious()    }
    func seek(to f: Double){ engine.seek(to: f)       }
    func toggleShuffle()   { engine.toggleShuffle()   }
    func toggleRepeat()    { engine.toggleRepeat()    }

    // Required by ObservableObject
    var objectWillChange: ObservableObjectPublisher { engine.objectWillChange }
}

// MARK: - Preview

#Preview {
    ContentViewAudiophile()
        .environmentObject(AppEnvironment())
}
