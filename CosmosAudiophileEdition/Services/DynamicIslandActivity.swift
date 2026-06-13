// DynamicIslandActivity.swift — Cosmos Audiophile Edition
// ActivityKit Live Activity + Dynamic Island for Now Playing.
// Requires: Info.plist key NSSupportsLiveActivities = YES
//           Target iOS 16.1+

import Foundation
import ActivityKit
import SwiftUI

// MARK: - Activity Attributes

struct CosmosActivityAttributes: ActivityAttributes {
    public typealias ContentState = CosmosActivityState

    // Static data (set once at launch)
    var appName: String = "Cosmos"
}

public struct CosmosActivityState: Codable, Hashable {
    var title:     String
    var artist:    String
    var album:     String
    var format:    String
    var bitDepth:  Int?
    var srKHz:     Double?
    var isPlaying: Bool
    var progress:  Double   // 0…1
    var duration:  Double   // seconds
    // artworkData not included — ActivityKit payload limit is 4 KB
}

// MARK: - Dynamic Island Manager

@MainActor
final class DynamicIslandManager: ObservableObject {

    static let shared = DynamicIslandManager()
    private var currentActivity: Activity<CosmosActivityAttributes>?
    private init() {}

    // MARK: - Start

    func startActivity(state: CosmosActivityState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let attrs    = CosmosActivityAttributes()
            let content  = ActivityContent(state: state, staleDate: nil)
            currentActivity = try Activity<CosmosActivityAttributes>.request(
                attributes:  attrs,
                content:     content,
                pushType:    nil
            )
        } catch {
            print("⚠️ Live Activity start: \(error)")
        }
    }

    // MARK: - Update

    func update(state: CosmosActivityState) {
        Task {
            await currentActivity?.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    // MARK: - End

    func end() {
        Task {
            await currentActivity?.end(ActivityContent(
                state: CosmosActivityState(
                    title: "", artist: "", album: "", format: "",
                    isPlaying: false, progress: 0, duration: 0
                ),
                staleDate: nil
            ), dismissalPolicy: .immediate)
            currentActivity = nil
        }
    }

    // MARK: - Convenience

    func updateFromEngine(_ engine: GaplessPlaybackEngine) {
        let state = CosmosActivityState(
            title:     engine.currentTitle,
            artist:    engine.currentArtist,
            album:     engine.currentAlbum,
            format:    engine.formatName,
            bitDepth:  engine.bitDepth,
            srKHz:     (engine.sampleRateHz ?? 0) / 1000,
            isPlaying: engine.state == .playing,
            progress:  engine.progress,
            duration:  engine.duration
        )

        if currentActivity == nil {
            startActivity(state: state)
        } else {
            update(state: state)
        }
    }
}

// MARK: - Widget Views (used in the Widget Extension target)
// Create a new "Widget Extension" target in Xcode and reference these views.

// Compact Leading — small album icon + format badge
struct DynamicIslandCompactLeading: View {
    let state: CosmosActivityState
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.caption2.weight(.bold))
                .foregroundColor(.orange)
            Text(state.format)
                .font(.caption2.weight(.black))
                .foregroundColor(.orange)
        }
    }
}

// Compact Trailing — play state + progress
struct DynamicIslandCompactTrailing: View {
    let state: CosmosActivityState
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.caption2)
            Text(String(format: "%.0f%%", state.progress * 100))
                .font(.system(size: 9).monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

// Minimal — just the waveform symbol
struct DynamicIslandMinimal: View {
    let state: CosmosActivityState
    var body: some View {
        Image(systemName: state.isPlaying ? "waveform" : "pause.circle.fill")
            .font(.caption)
            .foregroundColor(.orange)
    }
}

// Expanded — full now playing card
struct DynamicIslandExpanded: View {
    let state: CosmosActivityState
    var body: some View {
        HStack(spacing: 16) {
            // Left: waveform / format badge
            VStack(spacing: 4) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                Text(state.format)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.orange)
            }
            .frame(width: 44)

            // Center: title + artist
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(state.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3)).frame(height: 3)
                        Capsule().fill(Color.orange)
                            .frame(width: geo.size.width * state.progress, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.top, 4)
            }

            // Right: play state + hi-res label
            VStack(spacing: 4) {
                Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                if let kHz = state.srKHz {
                    Text(kHz.truncatingRemainder(dividingBy: 1) == 0
                         ? "\(Int(kHz))k"
                         : String(format: "%.1fk", kHz))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.purple)
                }
            }
            .frame(width: 44)
        }
        .padding(.horizontal, 16)
    }
}

// Lock Screen notification view
struct DynamicIslandLockScreen: View {
    let state: CosmosActivityState
    var body: some View {
        HStack(spacing: 14) {
            // Album art placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.orange.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(state.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(state.format)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.orange)
                    if let kHz = state.srKHz {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(kHz.truncatingRemainder(dividingBy: 1) == 0
                             ? "\(Int(kHz)) kHz"
                             : String(format: "%.1f kHz", kHz))
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundColor(.white)
        }
        .padding(12)
    }
}
