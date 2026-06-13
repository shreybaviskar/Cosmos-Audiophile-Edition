// SmartShuffleManager.swift — Cosmos Audiophile Edition
// Intelligent shuffle that avoids same-artist/album back-to-back
// and weights selection by play / skip history.

import Foundation
import Combine

// MARK: - Shuffle Mode

enum ShuffleMode: String, CaseIterable, Identifiable, Codable {
    case off         = "Off"
    case smart       = "Smart"
    case trueRandom  = "True Random"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .off:        return "arrow.right"
        case .smart:      return "shuffle"
        case .trueRandom: return "dice"
        }
    }

    var description: String {
        switch self {
        case .off:        return "Sequential play"
        case .smart:      return "Avoids back-to-back artist & album"
        case .trueRandom: return "Pure random — no constraints"
        }
    }
}

// MARK: - Smart Shuffle Manager

@MainActor
final class SmartShuffleManager: ObservableObject {

    // MARK: - Published Settings
    @Published var mode: ShuffleMode          = .smart
    @Published var avoidSameArtist: Bool      = true
    @Published var avoidSameAlbum: Bool       = true
    @Published var weightByPlayHistory: Bool  = true

    // MARK: - Private History

    private struct PlayRecord {
        let trackId: Int64
        let artistId: Int64?
        let albumId: Int64?
    }

    private var recentPlays: [PlayRecord]  = []   // newest first
    private var skipCounts: [Int64: Int]   = [:]  // trackId → #skips
    private let historyWindowSize          = 20

    // MARK: - Shuffle Entry Point

    /// Returns tracks shuffled according to the current mode.
    func shuffled(tracks: [TrackItem]) -> [TrackItem] {
        guard tracks.count > 1 else { return tracks }
        switch mode {
        case .off:        return tracks
        case .trueRandom: return trueRandom(tracks)
        case .smart:      return smartShuffle(tracks)
        }
    }

    // MARK: - True Random (Fisher-Yates)

    private func trueRandom(_ tracks: [TrackItem]) -> [TrackItem] {
        var arr = tracks
        for i in stride(from: arr.count - 1, through: 1, by: -1) {
            arr.swapAt(i, Int.random(in: 0...i))
        }
        return arr
    }

    // MARK: - Smart Shuffle

    private func smartShuffle(_ tracks: [TrackItem]) -> [TrackItem] {
        // Build (track, weight) pairs
        var pool: [(track: TrackItem, weight: Double)] = tracks.map { t in
            var w = 1.0
            if weightByPlayHistory {
                // Penalise recently played tracks
                for (i, rec) in recentPlays.prefix(historyWindowSize).enumerated() {
                    if rec.trackId == t.id {
                        let recencyFactor = 1.0 - Double(i) / Double(historyWindowSize)
                        w -= recencyFactor * 0.65
                    }
                }
                // Penalise frequently skipped
                let skips = min(skipCounts[t.id] ?? 0, 6)
                w -= Double(skips) * 0.12
            }
            return (t, max(0.05, w))
        }

        var result: [TrackItem] = []

        while !pool.isEmpty {
            // Weighted random pick
            let total = pool.reduce(0.0) { $0 + $1.weight }
            var rng   = Double.random(in: 0..<total)
            var idx   = pool.count - 1
            for (i, item) in pool.enumerated() {
                rng -= item.weight
                if rng <= 0 { idx = i; break }
            }

            let candidate = pool[idx].track

            // Apply artist / album constraints if there's a previous track
            if let prev = result.last {
                if avoidSameArtist,
                   candidate.artistId == prev.artistId,
                   pool.count > 1,
                   let altIdx = pool.indices.first(where: { pool[$0].track.artistId != prev.artistId }) {
                    result.append(pool[altIdx].track)
                    pool.remove(at: altIdx)
                    continue
                }
                if avoidSameAlbum,
                   candidate.albumId == prev.albumId,
                   pool.count > 1,
                   let altIdx = pool.indices.first(where: { pool[$0].track.albumId != prev.albumId }) {
                    result.append(pool[altIdx].track)
                    pool.remove(at: altIdx)
                    continue
                }
            }

            result.append(candidate)
            pool.remove(at: idx)
        }

        return result
    }

    // MARK: - History Recording

    func recordPlay(_ track: TrackItem) {
        recentPlays.insert(PlayRecord(trackId: track.id, artistId: track.artistId, albumId: track.albumId), at: 0)
        if recentPlays.count > historyWindowSize * 2 {
            recentPlays = Array(recentPlays.prefix(historyWindowSize * 2))
        }
        persistHistory()
    }

    func recordSkip(_ track: TrackItem) {
        skipCounts[track.id, default: 0] += 1
        persistHistory()
    }

    func clearHistory() {
        recentPlays.removeAll()
        skipCounts.removeAll()
        persistHistory()
    }

    // MARK: - Persistence

    private let defaults = UserDefaults.standard

    func saveSettings() {
        defaults.set(mode.rawValue,         forKey: "sm_mode")
        defaults.set(avoidSameArtist,       forKey: "sm_avoidArtist")
        defaults.set(avoidSameAlbum,        forKey: "sm_avoidAlbum")
        defaults.set(weightByPlayHistory,   forKey: "sm_weightHistory")
    }

    func loadSettings() {
        if let raw = defaults.string(forKey: "sm_mode"),
           let m   = ShuffleMode(rawValue: raw) { mode = m }
        avoidSameArtist     = defaults.object(forKey: "sm_avoidArtist")    as? Bool ?? true
        avoidSameAlbum      = defaults.object(forKey: "sm_avoidAlbum")     as? Bool ?? true
        weightByPlayHistory = defaults.object(forKey: "sm_weightHistory")  as? Bool ?? true
    }

    private func persistHistory() {
        // Persist skip counts (lightweight)
        if let data = try? JSONEncoder().encode(skipCounts) {
            defaults.set(data, forKey: "sm_skipCounts")
        }
    }

    func loadHistory() {
        if let data = defaults.data(forKey: "sm_skipCounts"),
           let counts = try? JSONDecoder().decode([Int64: Int].self, from: data) {
            skipCounts = counts
        }
    }
}

// MARK: - TrackItem  (lightweight shuffle payload — mirrors DB Track fields)

/// Minimal struct used by the shuffle engine.
/// Map your GRDB Track record to this before shuffling.
struct TrackItem: Identifiable {
    let id: Int64
    let stableId: String
    let title: String
    let artistId: Int64?
    let albumId: Int64?
    let durationMs: Int64?
    let sampleRate: Int?
    let bitDepth: Int?
    let path: String
}
