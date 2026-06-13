// EqualizerManager.swift — Cosmos Audiophile Edition
// Replaces the original EqualizerManager.swift.
// Uses AVAudioUnitEQ (10 parametric bands) for real-time processing.
// Supports factory presets, custom user presets, and the legacy
// GraphicEQ text format (for backward compatibility).

import Foundation
import AVFoundation
import Combine

@MainActor
final class EqualizerManager: ObservableObject {

    // MARK: - Published
    @Published var configuration: EQConfiguration = .default {
        didSet { applyToAudioUnit() }
    }
    @Published var isEnabled: Bool = false {
        didSet {
            configuration.isEnabled = isEnabled
            applyToAudioUnit()
        }
    }

    // MARK: - Audio Node (connect to AVAudioEngine)
    let audioUnit: AVAudioUnitEQ

    // MARK: - Init
    init() {
        audioUnit = AVAudioUnitEQ(numberOfBands: 10)
        initBands()
        loadFromDisk()
    }

    // MARK: - Band Initialisation
    private func initBands() {
        let freqs: [Float] = EQConfiguration.standardFrequencies
        for (i, band) in audioUnit.bands.enumerated() {
            band.filterType = i == 0 ? .lowShelf
                            : i == 9 ? .highShelf
                            : .parametric
            band.frequency  = freqs[i]
            band.bandwidth  = 1.0
            band.gain       = 0.0
            band.bypass     = true   // start bypassed
        }
        audioUnit.globalGain = 0
    }

    // MARK: - Preset Application

    func apply(preset: EQPreset) {
        var newConfig = configuration.applying(preset: preset)
        newConfig.isEnabled = isEnabled
        configuration = newConfig
        saveToDisk()
    }

    func applyCustomPreset(_ preset: CustomEQPreset) {
        var updated = configuration
        updated.bands        = preset.bands
        updated.activePreset = .custom
        configuration        = updated
        saveToDisk()
    }

    func resetToFlat() { apply(preset: .flat) }

    // MARK: - Band Editing

    func setGain(_ gain: Float, atBandIndex index: Int) {
        guard index < configuration.bands.count else { return }
        var bands             = configuration.bands
        var band              = bands[index]
        band.gain             = min(12, max(-12, gain))
        bands[index]          = band
        var updated           = configuration
        updated.bands         = bands
        updated.activePreset  = .custom
        configuration         = updated
        saveToDisk()
    }

    // MARK: - Enable / Disable

    func toggle() {
        isEnabled.toggle()
        saveToDisk()
    }

    // MARK: - Custom Preset CRUD

    func saveCurrentAsCustomPreset(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let preset = CustomEQPreset(name: name, bands: configuration.bands)
        var updated = configuration
        updated.customPresets.append(preset)
        configuration = updated
        saveToDisk()
    }

    func deleteCustomPreset(id: UUID) {
        var updated = configuration
        updated.customPresets.removeAll { $0.id == id }
        configuration = updated
        saveToDisk()
    }

    func renameCustomPreset(id: UUID, newName: String) {
        guard let idx = configuration.customPresets.firstIndex(where: { $0.id == id }) else { return }
        var updated = configuration
        updated.customPresets[idx].name = newName
        configuration = updated
        saveToDisk()
    }

    // MARK: - AVAudioUnit Application

    private func applyToAudioUnit() {
        let bypass = !configuration.isEnabled
        for (i, band) in audioUnit.bands.enumerated() {
            if bypass {
                band.bypass = true
            } else {
                band.gain      = configuration.bands[i].clampedGain
                band.bandwidth = configuration.bands[i].bandwidth
                band.bypass    = false
            }
        }
    }

    // MARK: - Legacy GraphicEQ Text Parser
    //   Parses strings like:
    //     "Preamp: -2 dB\n32 Hz 4 dB\n64 Hz 3 dB…"
    //   or semicolon-separated:
    //     "32 Hz 4 dB; 64 Hz 3 dB; …"
    //   Useful for importing EQ settings from EqualizerAPO / AutoEQ.

    func applyGraphicEQText(_ text: String) {
        let separators = CharacterSet.newlines.union(CharacterSet(charactersIn: ";"))
        let lines      = text.components(separatedBy: separators)

        for line in lines {
            let parts = line
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            // "Preamp: X dB"
            if parts.first?.lowercased() == "preamp:" {
                if let val = parts.dropFirst().first.flatMap({ Float($0.replacingOccurrences(of: "dB", with: "")) }) {
                    audioUnit.globalGain = min(12, max(-12, val))
                }
                continue
            }

            // "FREQ [Hz] GAIN [dB]"
            guard parts.count >= 2 else { continue }
            let freqStr = parts[0].replacingOccurrences(of: "Hz", with: "")
            let gainStr = parts.last!.replacingOccurrences(of: "dB", with: "")
            guard let freq = Float(freqStr), let gain = Float(gainStr) else { continue }

            // Find nearest band
            let freqs = EQConfiguration.standardFrequencies
            if let nearestIdx = freqs.indices.min(by: {
                abs(freqs[$0] - freq) < abs(freqs[$1] - freq)
            }) {
                setGain(gain, atBandIndex: nearestIdx)
            }
        }
    }

    // MARK: - Persistence

    private let storageKey = "cae_equalizerConfig"

    func saveToDisk() {
        if let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func loadFromDisk() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let cfg  = try? JSONDecoder().decode(EQConfiguration.self, from: data)
        else { return }
        configuration = cfg
        isEnabled     = cfg.isEnabled
        applyToAudioUnit()
    }
}
