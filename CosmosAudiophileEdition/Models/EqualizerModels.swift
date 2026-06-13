// EqualizerModels.swift — Cosmos Audiophile Edition
// Replaces the original EqualizerModels.swift
// 10-band graphical EQ with 10 factory presets and custom preset storage

import Foundation

// MARK: - EQ Band

struct EQBand: Identifiable, Codable, Equatable {
    let id: Int
    let frequency: Float   // Hz
    var gain: Float        // dB  –12 … +12
    var bandwidth: Float   // Q  0.5 … 2.0

    /// Human-readable label: "32", "1k", "16k"
    var frequencyLabel: String {
        frequency >= 1000
            ? (frequency.truncatingRemainder(dividingBy: 1000) == 0
               ? "\(Int(frequency / 1000))k"
               : String(format: "%.1fk", frequency / 1000))
            : "\(Int(frequency))"
    }

    /// Gain clamped to ±12 dB
    var clampedGain: Float { min(12, max(-12, gain)) }
}

// MARK: - Factory Presets

enum EQPreset: String, CaseIterable, Identifiable, Codable {
    case flat         = "Flat"
    case bassBoost    = "Bass Boost"
    case trebleBoost  = "Treble Boost"
    case vocal        = "Vocal"
    case classical    = "Classical"
    case rock         = "Rock"
    case jazz         = "Jazz"
    case electronic   = "Electronic"
    case hipHop       = "Hip-Hop"
    case podcast      = "Podcast"
    case custom       = "Custom"

    var id: String { rawValue }

    /// Gains (dB) for bands: 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k
    var gains: [Float] {
        switch self {
        case .flat:
            return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost:
            return [6, 5, 4, 2, 1, 0, 0, 0, -1, -1]
        case .trebleBoost:
            return [-1, 0, 0, 0, 0, 1, 2, 3, 4, 5]
        case .vocal:
            return [-2, -1, 0, 2, 4, 5, 4, 2, 1, -1]
        case .classical:
            return [4, 3, 2, 0, -1, 0, 0, 2, 3, 4]
        case .rock:
            return [5, 4, 3, 1, -1, 0, 1, 3, 4, 4]
        case .jazz:
            return [3, 2, 1, 2, -1, -1, 0, 1, 2, 3]
        case .electronic:
            return [5, 4, 1, 0, -2, -1, 1, 3, 4, 4]
        case .hipHop:
            return [5, 4, 4, 2, 1, -1, -1, 1, 2, 2]
        case .podcast:
            return [-2, -2, 0, 2, 4, 4, 3, 2, 1, 0]
        case .custom:
            return Array(repeating: 0, count: 10)
        }
    }
}

// MARK: - Custom Preset

struct CustomEQPreset: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bands: [EQBand]
    var createdAt: Date = Date()
}

// MARK: - EQ Configuration

struct EQConfiguration: Codable, Equatable {

    var isEnabled: Bool = false
    var activePreset: EQPreset = .flat
    var bands: [EQBand]
    var customPresets: [CustomEQPreset] = []

    // Ten audiophile-standard ISO frequencies
    static let standardFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000
    ]

    static let defaultBands: [EQBand] = standardFrequencies
        .enumerated()
        .map { EQBand(id: $0.offset, frequency: $0.element, gain: 0, bandwidth: 1.0) }

    static let `default` = EQConfiguration(bands: defaultBands)

    // Apply a factory preset, returning a new configuration
    func applying(preset: EQPreset) -> EQConfiguration {
        var copy = self
        copy.activePreset = preset
        copy.bands = bands.enumerated().map { idx, band in
            EQBand(id: band.id, frequency: band.frequency,
                   gain: preset.gains[idx], bandwidth: band.bandwidth)
        }
        return copy
    }
}
