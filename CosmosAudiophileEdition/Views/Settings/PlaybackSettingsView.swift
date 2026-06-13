// PlaybackSettingsView.swift — Cosmos Audiophile Edition
// Full settings page for the audio engine:
// gapless, crossfade, ReplayGain, output info, and advanced DAC options.

import SwiftUI

struct PlaybackSettingsView: View {

    @ObservedObject var engine:     GaplessPlaybackEngine
    @ObservedObject var dacManager: DACOutputManager

    var body: some View {
        List {
            gaplessSection
            crossfadeSection
            replayGainSection
            outputSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Gapless

    private var gaplessSection: some View {
        Section(
            header: Text("Gapless Playback"),
            footer: Text("Schedules the next track before the current one ends, eliminating silence between songs. Best for albums with continuous mixes (e.g. Pink Floyd, DJ sets).")
        ) {
            Toggle(isOn: $engine.gaplessEnabled) {
                Label("Gapless Playback", systemImage: "waveform")
            }
            .tint(.orange)
            .onChange(of: engine.gaplessEnabled) { _ in engine.saveSettings() }
        }
    }

    // MARK: - Crossfade

    private var crossfadeSection: some View {
        Section(
            header: Text("Crossfade"),
            footer: Text("Blends the end of one track into the beginning of the next. Disable if you prefer gapless-only transitions.")
        ) {
            Toggle(isOn: $engine.crossfadeEnabled) {
                Label("Enable Crossfade", systemImage: "shuffle.circle")
            }
            .tint(.orange)
            .onChange(of: engine.crossfadeEnabled) { _ in engine.saveSettings() }

            if engine.crossfadeEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(String(format: "%.1f s", engine.crossfadeDuration))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $engine.crossfadeDuration, in: 0.5...10, step: 0.5)
                        .tint(.orange)
                        .onChange(of: engine.crossfadeDuration) { _ in engine.saveSettings() }
                }
            }
        }
    }

    // MARK: - ReplayGain

    private var replayGainSection: some View {
        Section(
            header: Text("ReplayGain"),
            footer: Text("Reads embedded ReplayGain tags to normalise volume across tracks. Use Pre-amp to boost or cut the normalisation reference level.")
        ) {
            Toggle(isOn: $engine.replayGainEnabled) {
                Label("ReplayGain Normalisation", systemImage: "speaker.wave.3.fill")
            }
            .tint(.orange)
            .onChange(of: engine.replayGainEnabled) { _ in engine.saveSettings() }

            if engine.replayGainEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pre-amp")
                        Spacer()
                        Text(String(format: "%+.1f dB", engine.replayGainPreamp))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $engine.replayGainPreamp, in: -12...12, step: 0.5)
                        .tint(.orange)
                        .onChange(of: engine.replayGainPreamp) { _ in engine.saveSettings() }
                }
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        Section(header: Text("Audio Output")) {
            HStack {
                Label("Output Device", systemImage: dacManager.outputType.sfSymbol)
                Spacer()
                Text(dacManager.dacName)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Label("Sample Rate", systemImage: "waveform.path")
                Spacer()
                Text(formattedKHz(dacManager.outputSampleRate))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Label("Bit-Perfect", systemImage: "checkmark.seal.fill")
                Spacer()
                if dacManager.isBitPerfect {
                    Text("Yes")
                        .foregroundColor(.green)
                } else {
                    Text("No")
                        .foregroundColor(.secondary)
                }
            }

            Button(action: { dacManager.refresh() }) {
                Label("Refresh Output Info", systemImage: "arrow.clockwise")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(header: Text("About")) {
            infoRow("Engine", "AVAudioEngine + AVAudioUnitEQ")
            infoRow("Codecs",  "FLAC · WAV · ALAC · AIFF · DSD · MP3 · AAC")
            infoRow("EQ",     "10-band Parametric (32 Hz – 16 kHz)")
            infoRow("Shuffle", "Smart (Fisher-Yates + history weighting)")
            infoRow("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.footnote)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formattedKHz(_ hz: Double) -> String {
        let k = hz / 1000
        return k.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(k)) kHz"
            : String(format: "%.1f kHz", k)
    }
}
