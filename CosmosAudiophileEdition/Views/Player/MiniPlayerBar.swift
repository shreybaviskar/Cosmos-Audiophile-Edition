// MiniPlayerBar.swift — Cosmos Audiophile Edition
// Compact always-visible player bar shown above the tab bar.
// Tapping expands to NowPlayingEnhancedView.

import SwiftUI

struct MiniPlayerBar<Engine: NowPlayingDataSource>: View {

    @ObservedObject var engine:     Engine
    @ObservedObject var eqManager:  EqualizerManager
    @ObservedObject var dacManager: DACOutputManager
    @ObservedObject var shuffleMgr: SmartShuffleManager

    @State private var showNowPlaying = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                artworkThumbnail
                trackDetails
                Spacer(minLength: 0)
                controlButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .onTapGesture { showNowPlaying = true }
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        dragOffset = min(0, drag.translation.height)
                    }
                    .onEnded { drag in
                        if drag.translation.height < -40 { showNowPlaying = true }
                        withAnimation(.spring()) { dragOffset = 0 }
                    }
            )
            .offset(y: dragOffset)
        }
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingEnhancedView(
                engine:         engine,
                eqManager:      eqManager,
                dacManager:     dacManager,
                shuffleManager: shuffleMgr
            )
        }
    }

    // MARK: - Artwork

    private var artworkThumbnail: some View {
        Group {
            if let img = engine.currentArtwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    )
            }
        }
    }

    // MARK: - Track Details

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(engine.currentTitle.isEmpty ? "Not Playing" : engine.currentTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(engine.currentArtist.isEmpty ? "—" : engine.currentArtist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !engine.formatName.isEmpty {
                    FormatBadgeView(format: engine.formatName, compact: true)
                }
                if dacManager.isBitPerfect {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                }
            }
        }
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 20) {
            Button(action: { engine.togglePlayPause() }) {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            Button(action: { engine.skipNext() }) {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
    }
}

// MARK: - Progress Bar Underline (thin strip at bottom of bar)

struct MiniProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * max(0, min(1, progress)))
            }
        }
        .frame(height: 2)
    }
}
