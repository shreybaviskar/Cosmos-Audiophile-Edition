// GaplessPlaybackEngine.swift — Cosmos Audiophile Edition
// AVAudioEngine-based playback engine with:
//   • Gapless back-to-back scheduling via AVAudioPlayerNode
//   • Crossfade (0–10 s, configurable)
//   • ReplayGain / normalisation
//   • 10-band EQ insertion
//   • Hi-res DAC session management
//   • Lock screen / Control Center integration (MPNowPlayingInfoCenter)

import Foundation
import AVFoundation
import MediaPlayer
import Combine

// MARK: - Playback State

enum PlaybackState: Equatable {
    case stopped
    case loading
    case playing
    case paused
    case error(String)
}

// MARK: - Repeat Mode (shared across engine)

extension RepeatMode {
    var next: RepeatMode {
        switch self { case .off: return .all; case .all: return .one; case .one: return .off }
    }
}

// MARK: - Gapless Playback Engine

@MainActor
final class GaplessPlaybackEngine: ObservableObject {

    // MARK: - Published
    @Published private(set) var state:       PlaybackState = .stopped
    @Published private(set) var progress:    Double        = 0    // 0…1
    @Published private(set) var elapsed:     Double        = 0    // seconds
    @Published private(set) var duration:    Double        = 0    // seconds
    @Published private(set) var repeatMode:  RepeatMode    = .off
    @Published private(set) var isShuffling: Bool          = false

    // Track being currently played
    @Published private(set) var currentTrack: TrackItem?

    // Current track audio metadata
    @Published private(set) var formatName:   String  = ""
    @Published private(set) var bitDepth:     Int?
    @Published private(set) var sampleRateHz: Double?
    @Published private(set) var currentArtwork: UIImage?
    @Published private(set) var currentTitle:   String = ""
    @Published private(set) var currentArtist:  String = ""
    @Published private(set) var currentAlbum:   String = ""

    // MARK: - Dependencies (inject at init)
    let eqManager:      EqualizerManager
    let dacManager:     DACOutputManager
    let shuffleManager: SmartShuffleManager

    // MARK: - Settings (published)
    @Published var crossfadeDuration:   Double = 3.0   // seconds
    @Published var crossfadeEnabled:    Bool   = true
    @Published var replayGainEnabled:   Bool   = true
    @Published var replayGainPreamp:    Float  = 0     // dB
    @Published var gaplessEnabled:      Bool   = true

    // MARK: - Private Audio Graph

    private let engine       = AVAudioEngine()
    private let playerNodeA  = AVAudioPlayerNode()  // ping-pong players
    private let playerNodeB  = AVAudioPlayerNode()
    private var activeNode:  AVAudioPlayerNode { useNodeA ? playerNodeA : playerNodeB }
    private var useNodeA     = true

    private let mixerNode    = AVAudioMixerNode()
    private var eqNode:      AVAudioUnitEQ { eqManager.audioUnit }

    private var crossfadeTimer: Timer?
    private var progressTimer:  AnyCancellable?
    private var isCrossfading   = false

    // MARK: - Queue

    private var queue: [TrackItem] = []
    private var queueIndex: Int    = 0

    // MARK: - Init

    init(eqManager: EqualizerManager,
         dacManager: DACOutputManager,
         shuffleManager: SmartShuffleManager) {
        self.eqManager      = eqManager
        self.dacManager     = dacManager
        self.shuffleManager = shuffleManager
        buildGraph()
        setupRemoteCommands()
        loadSettings()
    }

    deinit { engine.stop() }

    // MARK: - Audio Graph Construction

    private func buildGraph() {
        let nodes: [AVAudioNode] = [playerNodeA, playerNodeB, eqNode, mixerNode]
        nodes.forEach { engine.attach($0) }

        // PlayerA → EQ → Mixer → Output
        engine.connect(playerNodeA, to: eqNode,    format: nil)
        engine.connect(playerNodeB, to: mixerNode, format: nil) // B bypasses EQ for crossfade
        engine.connect(eqNode,      to: mixerNode, format: nil)
        engine.connect(mixerNode,   to: engine.outputNode, format: nil)

        // Start engine
        do {
            try engine.start()
        } catch {
            print("⚠️ AVAudioEngine start: \(error)")
        }
    }

    // MARK: - Queue Management

    func setQueue(_ tracks: [TrackItem], startIndex: Int = 0) {
        queue      = tracks
        queueIndex = max(0, min(startIndex, tracks.count - 1))
        play(track: queue[queueIndex])
    }

    func appendToQueue(_ tracks: [TrackItem]) {
        queue.append(contentsOf: tracks)
    }

    func skipNext() {
        guard !queue.isEmpty else { return }
        switch repeatMode {
        case .one:
            play(track: queue[queueIndex])
        case .all:
            queueIndex = (queueIndex + 1) % queue.count
            play(track: queue[queueIndex])
        case .off:
            guard queueIndex + 1 < queue.count else { stop(); return }
            queueIndex += 1
            play(track: queue[queueIndex])
        }
        shuffleManager.recordPlay(queue[queueIndex])
    }

    func skipPrevious() {
        guard !queue.isEmpty else { return }
        if elapsed > 3 {
            seek(to: 0); return
        }
        queueIndex = max(0, queueIndex - 1)
        play(track: queue[queueIndex])
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused:  resume()
        default:       break
        }
    }

    func pause() {
        activeNode.pause()
        state = .paused
        stopProgressTimer()
        updateNowPlaying()
    }

    func resume() {
        dacManager.setupSession()
        activeNode.play()
        state = .playing
        startProgressTimer()
        updateNowPlaying()
    }

    func stop() {
        playerNodeA.stop()
        playerNodeB.stop()
        state = .stopped
        progress = 0; elapsed = 0
        stopProgressTimer()
        updateNowPlaying()
    }

    func seek(to fraction: Double) {
        guard let track = currentTrack,
              let file  = audioFile(for: track),
              duration > 0 else { return }

        let targetFrame = AVAudioFramePosition(fraction * Double(file.length))
        let remaining   = AVAudioFrameCount(file.length - targetFrame)
        guard remaining > 0 else { return }

        activeNode.stop()
        activeNode.scheduleSegment(file,
            startingFrame: targetFrame, frameCount: remaining,
            at: nil,
            completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in self?.trackFinished() }
        }
        activeNode.play()
        elapsed  = fraction * duration
        progress = fraction
    }

    func toggleShuffle() {
        isShuffling.toggle()
        if isShuffling {
            // Re-order the queue from current position onward
            let remaining = Array(queue.dropFirst(queueIndex + 1))
            let shuffled  = shuffleManager.shuffled(tracks: remaining)
            queue.replaceSubrange((queueIndex + 1)..., with: shuffled)
        }
        saveSettings()
    }

    func toggleRepeat() {
        repeatMode = repeatMode.next
        saveSettings()
    }

    // MARK: - Core Play

    private func play(track: TrackItem) {
        guard let file = audioFile(for: track) else {
            state = .error("Cannot open: \(track.path)")
            return
        }

        currentTrack = track
        state        = .loading

        // Session sample rate matching
        if let sr = sampleRateHz {
            dacManager.configure(forSourceSampleRate: sr)
        }

        // Extract metadata
        loadMetadata(from: file, track: track)

        // Crossfade or hard switch
        if crossfadeEnabled && crossfadeDuration > 0 && state != .stopped {
            crossfade(to: file, track: track)
        } else {
            hardSwitch(to: file, track: track)
        }

        // Schedule gapless next track
        if gaplessEnabled {
            scheduleNextGapless()
        }

        startProgressTimer()
        updateNowPlaying()
        shuffleManager.recordPlay(track)
    }

    private func hardSwitch(to file: AVAudioFile, track: TrackItem) {
        playerNodeA.stop()
        playerNodeB.stop()
        useNodeA = true
        activeNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in self?.trackFinished() }
        }
        dacManager.setupSession()
        activeNode.play()
        state = .playing
    }

    private func crossfade(to file: AVAudioFile, track: TrackItem) {
        guard !isCrossfading else { hardSwitch(to: file, track: track); return }
        isCrossfading = true

        let fadeOut    = useNodeA ? playerNodeA : playerNodeB
        let fadeInNode = useNodeA ? playerNodeB : playerNodeA
        useNodeA = !useNodeA

        // Schedule new track
        fadeInNode.volume = 0
        fadeInNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor [weak self] in self?.trackFinished() }
        }
        fadeInNode.play()
        state = .playing

        // Volume ramp
        let steps    = 60
        let interval = crossfadeDuration / Double(steps)
        var step     = 0

        crossfadeTimer?.invalidate()
        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            step += 1
            let fraction = Float(step) / Float(steps)
            fadeInNode.volume = fraction
            fadeOut.volume    = 1 - fraction
            if step >= steps {
                t.invalidate()
                fadeOut.stop()
                fadeOut.volume    = 1
                self.isCrossfading = false
            }
        }
    }

    private func scheduleNextGapless() {
        guard gaplessEnabled,
              queueIndex + 1 < queue.count,
              repeatMode != .one else { return }
        let nextTrack = queue[queueIndex + 1]
        guard let nextFile = audioFile(for: nextTrack) else { return }

        activeNode.scheduleFile(nextFile, at: nil) {
            // The completion of this second file will fire trackFinished
        }
    }

    private func trackFinished() {
        if repeatMode == .one {
            play(track: queue[queueIndex])
        } else {
            skipNext()
        }
    }

    // MARK: - Audio File Helper

    private func audioFile(for track: TrackItem) -> AVAudioFile? {
        let url = URL(fileURLWithPath: track.path)
        return try? AVAudioFile(forReading: url)
    }

    // MARK: - Metadata Extraction

    private func loadMetadata(from file: AVAudioFile, track: TrackItem) {
        let url   = file.url
        let asset = AVURLAsset(url: url)

        duration     = Double(file.length) / file.fileFormat.sampleRate
        sampleRateHz = file.fileFormat.sampleRate
        bitDepth     = file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int

        // Format name from extension
        let ext = url.pathExtension.uppercased()
        let dsdExts: Set<String> = ["DSF", "DFF"]
        if dsdExts.contains(ext) {
            let br = file.fileFormat.sampleRate
            formatName = br >= 256 * 44100 ? "DSD256"
                       : br >= 128 * 44100 ? "DSD128"
                       : "DSD64"
        } else {
            formatName = ext.isEmpty ? "PCM" : ext
        }

        // Title / artist / album from track item (already parsed from DB)
        currentTitle  = track.title
        currentArtist = ""   // fill from your DB lookup if available
        currentAlbum  = ""

        // Artwork via AVAsset metadata
        Task {
            let metaItems = try? await asset.loadMetadata(for: .iTunes)
            for item in metaItems ?? [] {
                if item.commonKey == .commonKeyArtwork,
                   let data = try? await item.load(.dataValue),
                   let img  = UIImage(data: data) {
                    await MainActor.run { currentArtwork = img }
                }
                if item.commonKey == .commonKeyArtist,
                   let v = try? await item.load(.stringValue) {
                    await MainActor.run { currentArtist = v }
                }
                if item.commonKey == .commonKeyAlbumName,
                   let v = try? await item.load(.stringValue) {
                    await MainActor.run { currentAlbum = v }
                }
                if item.commonKey == .commonKeyTitle,
                   let v = try? await item.load(.stringValue) {
                    await MainActor.run { currentTitle = v }
                }
            }
            await MainActor.run { self.updateNowPlaying() }
        }

        applyReplayGain(asset: asset)
    }

    // MARK: - ReplayGain

    private func applyReplayGain(asset: AVURLAsset) {
        guard replayGainEnabled else {
            mixerNode.outputVolume = 1.0; return
        }
        Task {
            let metaItems = (try? await asset.loadMetadata(for: .id3Metadata)) ?? []
            var gainDB: Float?
            for item in metaItems {
                if let id = item.identifier?.rawValue,
                   id.lowercased().contains("replaygain_track_gain"),
                   let strVal = try? await item.load(.stringValue) {
                    let cleaned = strVal.replacingOccurrences(of: " dB", with: "",
                                  options: .caseInsensitive)
                    gainDB = Float(cleaned)
                    break
                }
            }
            await MainActor.run {
                if let g = gainDB {
                    let linear = pow(10, (g + self.replayGainPreamp) / 20)
                    self.mixerNode.outputVolume = min(1.5, max(0.1, linear))
                } else {
                    self.mixerNode.outputVolume = 1.0
                }
            }
        }
    }

    // MARK: - Progress Timer

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let node = self.currentNode(), self.duration > 0 else { return }
                if let time = node.playerTime(forNodeTime: node.lastRenderTime ?? AVAudioTime()) {
                    let t       = Double(time.sampleTime) / time.sampleRate
                    self.elapsed  = min(t, self.duration)
                    self.progress = self.elapsed / self.duration
                }
            }
    }

    private func stopProgressTimer() { progressTimer?.cancel(); progressTimer = nil }

    private func currentNode() -> AVAudioPlayerNode? { useNodeA ? playerNodeA : playerNodeB }

    // MARK: - Lock Screen / Control Center

    private func setupRemoteCommands() {
        let rc = MPRemoteCommandCenter.shared()
        rc.playCommand.addTarget   { [weak self] _ in self?.resume();      return .success }
        rc.pauseCommand.addTarget  { [weak self] _ in self?.pause();       return .success }
        rc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        rc.nextTrackCommand.addTarget { [weak self] _ in self?.skipNext(); return .success }
        rc.previousTrackCommand.addTarget { [weak self] _ in self?.skipPrevious(); return .success }
        rc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent,
                  let self else { return .commandFailed }
            self.seek(to: e.positionTime / self.duration)
            return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:             currentTitle,
            MPMediaItemPropertyArtist:            currentArtist,
            MPMediaItemPropertyAlbumTitle:        currentAlbum,
            MPMediaItemPropertyPlaybackDuration:  duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType:    MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let img = currentArtwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Settings Persistence

    private let defaults = UserDefaults.standard

    func saveSettings() {
        defaults.set(crossfadeEnabled,   forKey: "gpe_crossfade")
        defaults.set(crossfadeDuration,  forKey: "gpe_crossfadeSecs")
        defaults.set(replayGainEnabled,  forKey: "gpe_replayGain")
        defaults.set(replayGainPreamp,   forKey: "gpe_replayPreamp")
        defaults.set(gaplessEnabled,     forKey: "gpe_gapless")
        defaults.set(repeatMode.rawValue, forKey: "gpe_repeat")
        defaults.set(isShuffling,        forKey: "gpe_shuffle")
    }

    func loadSettings() {
        crossfadeEnabled  = defaults.bool(forKey: "gpe_crossfade")
        crossfadeDuration = defaults.double(forKey: "gpe_crossfadeSecs").nonZero ?? 3
        replayGainEnabled = defaults.bool(forKey: "gpe_replayGain")
        replayGainPreamp  = defaults.float(forKey: "gpe_replayPreamp")
        gaplessEnabled    = defaults.bool(forKey: "gpe_gapless")
        if let raw = defaults.string(forKey: "gpe_repeat"),
           let r   = RepeatMode(rawValue: raw) { repeatMode = r }
        isShuffling = defaults.bool(forKey: "gpe_shuffle")
    }

    // raw value shim for RepeatMode
    private var repeatModeRaw: String {
        switch repeatMode { case .off: return "off"; case .one: return "one"; case .all: return "all" }
    }
}

// MARK: - RepeatMode String Coding

extension RepeatMode {
    var rawValue: String {
        switch self { case .off: return "off"; case .one: return "one"; case .all: return "all" }
    }
    init?(rawValue: String) {
        switch rawValue { case "off": self = .off; case "one": self = .one; case "all": self = .all; default: return nil }
    }
}

// MARK: - Helpers

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
