// DACOutputManager.swift — Cosmos Audiophile Edition
// Monitors the AVAudioSession output route, detects external DACs,
// configures the audio session for maximum fidelity, and reports
// bit-perfect status to the UI.

import Foundation
import AVFoundation
import Combine

// MARK: - Audio Output Type

enum AudioOutputType: Equatable {
    case builtInSpeaker
    case wiredHeadphones
    case externalDAC(name: String)
    case bluetooth(name: String)
    case carPlay
    case airPlay(name: String)
    case unknown(name: String)

    var displayName: String {
        switch self {
        case .builtInSpeaker:         return "Built-in Speaker"
        case .wiredHeadphones:        return "Headphones"
        case .externalDAC(let n):     return n
        case .bluetooth(let n):       return n
        case .carPlay:                return "CarPlay"
        case .airPlay(let n):         return n
        case .unknown(let n):         return n
        }
    }

    var isHiResCable: Bool {
        switch self {
        case .externalDAC:      return true
        case .wiredHeadphones:  return true
        default:                return false
        }
    }

    var sfSymbol: String {
        switch self {
        case .builtInSpeaker:   return "iphone"
        case .wiredHeadphones:  return "headphones"
        case .externalDAC:      return "hifispeaker.2.fill"
        case .bluetooth:        return "airpodspro"
        case .carPlay:          return "car.fill"
        case .airPlay:          return "airplayvideo"
        case .unknown:          return "cable.connector"
        }
    }
}

// MARK: - DAC Output Manager

@MainActor
final class DACOutputManager: ObservableObject {

    static let shared = DACOutputManager()

    // MARK: Published
    @Published private(set) var outputType:         AudioOutputType = .builtInSpeaker
    @Published private(set) var outputSampleRate:   Double          = 44_100
    @Published private(set) var isBitPerfect:       Bool            = false
    @Published private(set) var preferredSampleRate: Double         = 44_100

    var dacName: String { outputType.displayName }
    var isExternalDAC: Bool {
        if case .externalDAC = outputType { return true }
        return false
    }

    // MARK: Private
    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    private init() {
        setupSession()
        setupObservers()
        refresh()
    }

    deinit {
        [routeObserver, interruptionObserver].forEach {
            if let obs = $0 { NotificationCenter.default.removeObserver(obs) }
        }
    }

    // MARK: - Session Setup

    func setupSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .default,
                              options: [.allowBluetoothA2DP, .allowAirPlay])
            try s.setActive(true)
        } catch {
            print("⚠️ AVAudioSession setup: \(error)")
        }
    }

    // MARK: - Hi-Res Configuration

    /// Call when starting playback of a new track to match the hardware sample rate.
    func configure(forSourceSampleRate sourceSR: Double) {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setPreferredSampleRate(sourceSR)
            try s.setPreferredIOBufferDuration(0.005) // 5 ms latency
        } catch {
            // Non-fatal: hardware may not support the exact rate
        }
        preferredSampleRate  = sourceSR
        outputSampleRate     = s.sampleRate
        isBitPerfect         = abs(s.sampleRate - sourceSR) < 1.0
    }

    // MARK: - Route Refresh

    func refresh() {
        let s     = AVAudioSession.sharedInstance()
        let route = s.currentRoute
        outputSampleRate = s.sampleRate

        guard let output = route.outputs.first else {
            outputType = .builtInSpeaker
            isBitPerfect = false
            return
        }

        outputType = classify(port: output)
        isBitPerfect = isExternalDAC
            ? abs(s.sampleRate - preferredSampleRate) < 1.0
            : false
    }

    // MARK: - Classification

    private func classify(port: AVAudioSessionPortDescription) -> AudioOutputType {
        switch port.portType {
        case .builtInSpeaker:
            return .builtInSpeaker
        case .headphones, .headsetMic:
            return .wiredHeadphones
        case .usbAudio:
            return .externalDAC(name: port.portName)
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth(name: port.portName)
        case .carAudio:
            return .carPlay
        case .airPlay:
            return .airPlay(name: port.portName)
        default:
            // Lightning/USB-C DACs sometimes appear as "Unknown"
            let name = port.portName
            let lc   = name.lowercased()
            if lc.contains("usb") || lc.contains("dac") || lc.contains("audio") {
                return .externalDAC(name: name)
            }
            return .unknown(name: name)
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] note in
            guard
                let info = note.userInfo,
                let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: typeVal)
            else { return }

            if type == .ended {
                Task { @MainActor [weak self] in
                    self?.setupSession()
                    self?.refresh()
                }
            }
        }
    }
}
