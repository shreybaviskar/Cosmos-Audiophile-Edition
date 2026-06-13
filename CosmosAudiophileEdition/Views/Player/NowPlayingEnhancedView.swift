// NowPlayingEnhancedView.swift — Cosmos Audiophile Edition
// Apple Music-inspired full-screen Now Playing view.
// Drop-in replacement / supplement for the existing NowPlayingView.
//
// Requires:
//   - PlayerEngine (existing) — provides currentTrack, isPlaying, progress, etc.
//   - EqualizerManager (new)
//   - DACOutputManager (new)
//   - SmartShuffleManager (new)
//   - WaveformProgressView (new)
//   - FormatBadgeView (new)
//   - AudiophileDashboardView (new)
//   - GraphicalEQView (new)

import SwiftUI

// MARK: - Now Playing View Model (adapt to your PlayerEngine API)

// This protocol defines the minimal surface area NowPlayingEnhancedView
// needs from your PlayerEngine. Conform your existing PlayerEngine to it.
protocol NowPlayingDataSource: ObservableObject {
    var currentTitle:    String   { get }
    var currentArtist:   String   { get }
    var currentAlbum:    String   { get }
    var currentArtwork:  UIImage? { get }
    var isPlaying:       Bool     { get }
    var progress:        Double   { get }   // 0…1
    var duration:        Double   { get }   // seconds
    var elapsed:         Double   { get }   // seconds
    var formatName:      String   { get }   // "FLAC", "WAV", …
    var bitDepth:        Int?     { get }
    var sampleRateHz:    Double?  { get }
    var isShuffling:     Bool     { get }
    var repeatMode:      RepeatMode { get }

    func togglePlayPause()
    func skipNext()
    func skipPrevious()
    func seek(to fraction: Double)
    func toggleShuffle()
    func toggleRepeat()
}

enum RepeatMode { case off, one, all }

// MARK: - Now Playing Enhanced View

struct NowPlayingEnhancedView<Engine: NowPlayingDataSource>: View {

    @ObservedObject var engine:         Engine
    @ObservedObject var eqManager:      EqualizerManager
    @ObservedObject var dacManager:     DACOutputManager
    @ObservedObject var shuffleManager: SmartShuffleManager

    @State private var showEQ           = false
    @State private var showDashboard    = false
    @State private var showQueue        = false
    @State private var artworkScale: CGFloat = 1.0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1 — Blurred artwork background
                artworkBackground(geo: geo)

                // 2 — Dark scrim
                LinearGradient(
                    colors: [.black.opacity(0.3), .black.opacity(0.8)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                // 3 — Content
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    artworkHero
                    Spacer(minLength: 16)
                    trackInfo
                    Spacer(minLength: 20)
                    scrubber
                    Spacer(minLength: 20)
                    transportControls
                    Spacer(minLength: 20)
                    secondaryControls
                    Spacer(minLength: 12)
                    formatBar
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 28)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showEQ)       { GraphicalEQView(eqManager: eqManager) }
        .sheet(isPresented: $showDashboard) { dashboardSheet }
    }

    // MARK: - Background

    @ViewBuilder
    private func artworkBackground(geo: GeometryProxy) -> some View {
        if let img = engine.currentArtwork {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .blur(radius: 60)
                .scaleEffect(1.3)
                .clipped()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
            Text("Now Playing")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(1)
            Spacer()
            Button(action: { showQueue = true }) {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Artwork Hero

    private var artworkHero: some View {
        ZStack {
            if let img = engine.currentArtwork {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
                    .scaleEffect(engine.isPlaying ? 1.0 : 0.88)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: engine.isPlaying)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                    )
            }
        }
        .frame(maxWidth: 330)
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(engine.currentTitle)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(engine.currentArtist)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: {}) {      // Add to Favourites
                Image(systemName: "heart")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 8) {
            WaveformProgressView(
                progress: Binding(get: { engine.progress }, set: { _ in }),
                isPlaying: engine.isPlaying,
                onSeek: { engine.seek(to: $0) }
            )
            .frame(height: 38)

            HStack {
                Text(timeString(engine.elapsed))
                Spacer()
                Text("-\(timeString(engine.duration - engine.elapsed))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            Spacer()
            Button(action: { engine.skipPrevious() }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            Spacer()
            Button(action: { engine.togglePlayPause() }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.black)
                }
            }
            Spacer()
            Button(action: { engine.skipNext() }) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }

    // MARK: - Secondary Controls

    private var secondaryControls: some View {
        HStack(spacing: 0) {
            Spacer()
            // Shuffle
            Button(action: { engine.toggleShuffle() }) {
                Image(systemName: shuffleManager.mode == .off ? "shuffle" : "shuffle")
                    .font(.title3)
                    .foregroundColor(shuffleManager.mode == .off ? .white.opacity(0.4) : .orange)
                    .overlay(
                        Text(shuffleManager.mode == .smart ? "S" : "")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.orange)
                            .offset(x: 10, y: -8)
                    )
            }
            Spacer()
            // EQ
            Button(action: { showEQ = true }) {
                Image(systemName: eqManager.isEnabled ? "slider.horizontal.3" : "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(eqManager.isEnabled ? .orange : .white.opacity(0.4))
            }
            Spacer()
            // Repeat
            Button(action: { engine.toggleRepeat() }) {
                Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundColor(engine.repeatMode == .off ? .white.opacity(0.4) : .orange)
            }
            Spacer()
            // DAC / Info
            Button(action: { showDashboard = true }) {
                Image(systemName: "hifispeaker.2")
                    .font(.title3)
                    .foregroundColor(dacManager.isExternalDAC ? .green : .white.opacity(0.4))
            }
            Spacer()
        }
    }

    // MARK: - Format Bar

    private var formatBar: some View {
        HStack(spacing: 10) {
            FormatBadgeView(format: engine.formatName, bitDepth: engine.bitDepth, compact: true)

            if let sr = engine.sampleRateHz {
                Text(formattedKHz(sr))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.5))
            }

            if dacManager.isBitPerfect {
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("Bit-Perfect")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Dashboard Sheet

    private var dashboardSheet: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    AudiophileDashboardView(
                        dacManager:   dacManager,
                        formatName:   engine.formatName,
                        bitDepth:     engine.bitDepth,
                        sampleRateHz: engine.sampleRateHz
                    )
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Playback Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showDashboard = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func timeString(_ seconds: Double) -> String {
        guard !seconds.isNaN, !seconds.isInfinite else { return "0:00" }
        let s = Int(max(0, seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private func formattedKHz(_ hz: Double) -> String {
        let k = hz / 1000
        return k.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(k)) kHz"
            : String(format: "%.1f kHz", k)
    }
}
