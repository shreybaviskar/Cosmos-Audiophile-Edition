// FolderScanManager.swift — Cosmos Audiophile Edition
// Handles folder-based library import with security-scoped URL bookmarks,
// recursive scanning for all supported audio formats, and progress reporting.

import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Scanned Folder Model

struct ScannedFolder: Identifiable, Codable, Equatable {
    var id: UUID              = UUID()
    var bookmarkData: Data
    var displayName: String
    var trackCount: Int       = 0
    var lastScannedAt: Date   = .distantPast

    // Resolve the URL from bookmark — call before accessing the file system
    var resolvedURL: URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    static func == (lhs: ScannedFolder, rhs: ScannedFolder) -> Bool { lhs.id == rhs.id }
}

// MARK: - Scan Result

struct FolderScanResult {
    let audioURLs: [URL]
    let folderCount: Int
    let scanDuration: TimeInterval
    let errors: [String]
}

// MARK: - Folder Scan Manager

@MainActor
final class FolderScanManager: ObservableObject {

    // MARK: - Published
    @Published var folders: [ScannedFolder]    = []
    @Published var isScanning: Bool            = false
    @Published var scanProgress: Double        = 0   // 0…1
    @Published var scanStatusMessage: String   = ""
    @Published var lastScanDate: Date?

    // MARK: - Supported Audio Extensions
    static let audioExtensions: Set<String> = [
        // Hi-res lossless
        "flac", "alac", "wav", "aiff", "aif", "caf", "w64",
        // DSD
        "dsf", "dff",
        // Lossy
        "mp3", "m4a", "aac",
        // Vorbis / Opus
        "ogg", "opus",
        // Other lossless
        "wv", "ape", "tak",
        // MIDI (metadata only)
        "mid", "midi"
    ]

    // MARK: - Storage Key
    private let storageKey = "cae_scannedFolders"

    // MARK: - Init
    init() { load() }

    // MARK: - Folder Management

    /// Registers a folder URL (already in security scope) as a monitored library source.
    func add(url: URL) throws {
        // Avoid duplicates by comparing standardised URL
        let standard = url.standardizedFileURL
        guard !folders.contains(where: { $0.resolvedURL?.standardizedFileURL == standard }) else {
            throw FolderError.alreadyAdded
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw FolderError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let folder = ScannedFolder(
            bookmarkData: bookmark,
            displayName: url.lastPathComponent
        )
        folders.append(folder)
        save()
    }

    func remove(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    func remove(atOffsets offsets: IndexSet) {
        folders.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Scanning

    /// Scans all registered folders and returns an aggregate result.
    @discardableResult
    func scanAll() async -> FolderScanResult {
        guard !isScanning else { return FolderScanResult(audioURLs: [], folderCount: 0, scanDuration: 0, errors: []) }
        isScanning = true
        scanProgress = 0
        scanStatusMessage = "Starting scan…"

        let start     = Date()
        var allURLs:  [URL]    = []
        var errors:   [String] = []

        for (idx, folder) in folders.enumerated() {
            scanStatusMessage = "Scanning \(folder.displayName)…"
            do {
                let urls = try await scanFolder(folder)
                allURLs.append(contentsOf: urls)

                // Update stats on the stored folder
                if let i = folders.firstIndex(where: { $0.id == folder.id }) {
                    folders[i].trackCount    = urls.count
                    folders[i].lastScannedAt = Date()
                }
            } catch {
                errors.append("\(folder.displayName): \(error.localizedDescription)")
            }
            scanProgress = Double(idx + 1) / Double(max(folders.count, 1))
        }

        // Deduplicate
        let unique = Array(Set(allURLs))
        lastScanDate   = Date()
        isScanning     = false
        scanStatusMessage = "Found \(unique.count) tracks"
        save()

        return FolderScanResult(
            audioURLs:    unique,
            folderCount:  folders.count,
            scanDuration: Date().timeIntervalSince(start),
            errors:       errors
        )
    }

    // MARK: - Per-Folder Scan

    private func scanFolder(_ folder: ScannedFolder) async throws -> [URL] {
        guard let url = folder.resolvedURL else { throw FolderError.bookmarkStale }

        guard url.startAccessingSecurityScopedResource() else { throw FolderError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }

        return try await Task.detached(priority: .userInitiated) { [exts = Self.audioExtensions] in
            try Self.recursiveScan(url: url, extensions: exts)
        }.value
    }

    private static func recursiveScan(url: URL, extensions: Set<String>) throws -> [URL] {
        let fm = FileManager.default
        var results: [URL] = []

        let keys: [URLResourceKey] = [.isDirectoryKey, .isReadableKey, .isSymbolicLinkKey]
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        for item in contents {
            guard let rv = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if rv.isSymbolicLink == true { continue } // avoid loops
            if rv.isDirectory == true {
                let sub = (try? recursiveScan(url: item, extensions: extensions)) ?? []
                results.append(contentsOf: sub)
            } else if rv.isReadable == true {
                if extensions.contains(item.pathExtension.lowercased()) {
                    results.append(item)
                }
            }
        }
        return results
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data    = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScannedFolder].self, from: data)
        else { return }
        // Filter out entries whose bookmarks can no longer be resolved
        folders = decoded.filter { $0.resolvedURL != nil }
    }

    // MARK: - Error Types

    enum FolderError: LocalizedError {
        case accessDenied
        case alreadyAdded
        case bookmarkStale

        var errorDescription: String? {
            switch self {
            case .accessDenied:    return "Permission denied. Try selecting the folder again."
            case .alreadyAdded:    return "This folder is already in your library."
            case .bookmarkStale:   return "Folder bookmark is stale — please re-add the folder."
            }
        }
    }
}
