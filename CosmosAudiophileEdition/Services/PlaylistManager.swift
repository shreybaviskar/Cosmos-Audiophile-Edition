// PlaylistManager.swift — Cosmos Audiophile Edition
// Manual and smart playlists, CRUD, reorder, export.
// Uses UserDefaults for lightweight storage (swap to GRDB if you have a large library).

import Foundation
import Combine

// MARK: - Playlist Types

enum PlaylistType: String, Codable, CaseIterable {
    case manual = "Manual"
    case smart  = "Smart"
}

// MARK: - Smart Playlist Rule

struct SmartPlaylistRule: Codable, Identifiable {
    var id: UUID = UUID()

    enum Field: String, Codable, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case genre = "Genre"
        case bitDepth = "Bit Depth"
        case sampleRate = "Sample Rate"
        case format = "Format"
        case playCount = "Play Count"
    }

    enum Operator: String, Codable, CaseIterable {
        case contains    = "contains"
        case notContains = "does not contain"
        case equals      = "is"
        case notEquals   = "is not"
        case greaterThan = "greater than"
        case lessThan    = "less than"
    }

    var field:    Field
    var op:       Operator
    var value:    String
}

// MARK: - Playlist Model

struct Playlist: Identifiable, Codable, Equatable {
    var id:          UUID         = UUID()
    var name:        String
    var type:        PlaylistType = .manual
    var trackIds:    [Int64]      = []     // ordered for manual playlists
    var rules:       [SmartPlaylistRule] = []  // for smart playlists
    var matchAll:    Bool         = true   // AND vs OR for smart rules
    var description: String       = ""
    var artwork:     Data?                 // optional custom cover art (PNG)
    var createdAt:   Date         = Date()
    var updatedAt:   Date         = Date()

    static func == (lhs: Playlist, rhs: Playlist) -> Bool { lhs.id == rhs.id }
}

// MARK: - Playlist Manager

@MainActor
final class PlaylistManager: ObservableObject {

    @Published private(set) var playlists: [Playlist] = []

    private let storageKey = "cae_playlists"

    // MARK: - Init
    init() { load() }

    // MARK: - CRUD

    @discardableResult
    func createManual(name: String) -> Playlist {
        var pl = Playlist(name: name, type: .manual)
        playlists.append(pl)
        save()
        return pl
    }

    @discardableResult
    func createSmart(name: String, rules: [SmartPlaylistRule], matchAll: Bool = true) -> Playlist {
        let pl = Playlist(name: name, type: .smart, rules: rules, matchAll: matchAll)
        playlists.append(pl)
        save()
        return pl
    }

    func rename(id: UUID, newName: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].name      = newName
        playlists[idx].updatedAt = Date()
        save()
    }

    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func delete(atOffsets offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        save()
    }

    func move(fromOffsets src: IndexSet, toOffset dst: Int) {
        playlists.move(fromOffsets: src, toOffset: dst)
        save()
    }

    // MARK: - Track Management

    func addTracks(_ ids: [Int64], toPlaylist playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }),
              playlists[idx].type == .manual else { return }
        let existing = Set(playlists[idx].trackIds)
        let new = ids.filter { !existing.contains($0) }
        playlists[idx].trackIds.append(contentsOf: new)
        playlists[idx].updatedAt = Date()
        save()
    }

    func removeTrack(id trackId: Int64, fromPlaylist playlistId: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].trackIds.removeAll { $0 == trackId }
        playlists[idx].updatedAt = Date()
        save()
    }

    func reorderTracks(inPlaylist playlistId: UUID, fromOffsets: IndexSet, toOffset: Int) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[idx].trackIds.move(fromOffsets: fromOffsets, toOffset: toOffset)
        playlists[idx].updatedAt = Date()
        save()
    }

    func containsTrack(id trackId: Int64, inPlaylist playlistId: UUID) -> Bool {
        guard let pl = playlists.first(where: { $0.id == playlistId }) else { return false }
        return pl.trackIds.contains(trackId)
    }

    // MARK: - Smart Playlist Matching

    /// Returns track IDs from the library that satisfy all (or any) smart rules.
    func matchingTracks(for playlist: Playlist, allTracks: [TrackItem]) -> [TrackItem] {
        guard playlist.type == .smart, !playlist.rules.isEmpty else { return [] }
        return allTracks.filter { track in
            let results = playlist.rules.map { rule in
                matches(track: track, rule: rule)
            }
            return playlist.matchAll ? results.allSatisfy { $0 } : results.contains(true)
        }
    }

    private func matches(track: TrackItem, rule: SmartPlaylistRule) -> Bool {
        switch rule.field {
        case .title:
            return stringMatch(track.title, op: rule.op, value: rule.value)
        case .bitDepth:
            guard let bd = track.bitDepth, let v = Int(rule.value) else { return false }
            return numericMatch(bd, op: rule.op, value: v)
        case .sampleRate:
            guard let sr = track.sampleRate, let v = Int(rule.value) else { return false }
            return numericMatch(sr, op: rule.op, value: v)
        default:
            return false // artist/album/genre need a full DB lookup — extend here
        }
    }

    private func stringMatch(_ str: String, op: SmartPlaylistRule.Operator, value: String) -> Bool {
        let lower = str.lowercased(); let v = value.lowercased()
        switch op {
        case .contains:    return lower.contains(v)
        case .notContains: return !lower.contains(v)
        case .equals:      return lower == v
        case .notEquals:   return lower != v
        default:           return false
        }
    }

    private func numericMatch<N: Comparable>(_ n: N, op: SmartPlaylistRule.Operator, value: N) -> Bool {
        switch op {
        case .equals:       return n == value
        case .notEquals:    return n != value
        case .greaterThan:  return n > value
        case .lessThan:     return n < value
        default:            return false
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Playlist].self, from: data)
        else { return }
        playlists = decoded
    }
}
