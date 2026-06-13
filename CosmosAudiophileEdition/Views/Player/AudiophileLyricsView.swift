// AudiophileLyricsView.swift — Cosmos Audiophile Edition
// Reads embedded ID3 USLT/SYLT lyrics from the current track's audio file
// OR loads a sidecar .lrc/.txt file with the same name.
// Shows synchronized line highlighting when timing data is available.

import SwiftUI
import AVFoundation

// MARK: - LRC Line

struct LRCLine: Identifiable {
    let id:       UUID    = UUID()
    let timeCode: Double  // seconds (nil = static)
    let text:     String
}

// MARK: - Lyrics Loader

@MainActor
final class LyricsLoader: ObservableObject {

    @Published var lines:     [LRCLine] = []
    @Published var isLoaded:  Bool      = false
    @Published var hasTiming: Bool      = false

    func load(trackURL: URL) async {
        // 1. Try sidecar .lrc
        let lrcURL = trackURL.deletingPathExtension().appendingPathExtension("lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path) {
            if let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
                let parsed = parseLRC(content)
                if !parsed.isEmpty {
                    lines = parsed; hasTiming = parsed.allSatisfy { $0.timeCode > 0 }
                    isLoaded = true; return
                }
            }
        }

        // 2. Try sidecar .txt
        let txtURL = trackURL.deletingPathExtension().appendingPathExtension("txt")
        if FileManager.default.fileExists(atPath: txtURL.path),
           let content = try? String(contentsOf: txtURL, encoding: .utf8) {
            lines = content.components(separatedBy: .newlines)
                .map { LRCLine(timeCode: -1, text: $0) }
            hasTiming = false; isLoaded = !lines.isEmpty; return
        }

        // 3. AVAsset embedded USLT
        let asset = AVURLAsset(url: trackURL)
        do {
            let id3Meta = try await asset.loadMetadata(for: .id3Metadata)
            for item in id3Meta {
                if let id = item.identifier?.rawValue,
                   (id.contains("USLT") || id.contains("lyrics")),
                   let str = try? await item.load(.stringValue), !str.isEmpty {
                    lines = str.components(separatedBy: .newlines)
                        .map { LRCLine(timeCode: -1, text: $0) }
                    hasTiming = false; isLoaded = !lines.isEmpty; return
                }
            }
        } catch {}

        lines    = []
        isLoaded = false
    }

    func clear() { lines = []; isLoaded = false; hasTiming = false }

    // MARK: - LRC Parser
    // Format: [mm:ss.xx] Lyric line
    private func parseLRC(_ content: String) -> [LRCLine] {
        var result: [LRCLine] = []
        let regex  = try? NSRegularExpression(pattern: #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.+)"#)
        let lines  = content.components(separatedBy: .newlines)

        for line in lines {
            let nsLine = line as NSString
            let range  = NSRange(location: 0, length: nsLine.length)
            guard let match = regex?.firstMatch(in: line, range: range), match.numberOfRanges == 5 else {
                continue
            }
            let m  = nsLine.substring(with: match.range(at: 1))
            let s  = nsLine.substring(with: match.range(at: 2))
            let ms = nsLine.substring(with: match.range(at: 3))
            let t  = nsLine.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

            guard let minutes = Double(m), let seconds = Double(s),
                  let milli   = Double(ms) else { continue }

            let time = minutes * 60 + seconds + milli / 1000
            result.append(LRCLine(timeCode: time, text: t))
        }
        return result.sorted { $0.timeCode < $1.timeCode }
    }

    // MARK: - Sync Helper
    func activeLine(at elapsed: Double) -> UUID? {
        guard hasTiming else { return nil }
        var active: LRCLine?
        for line in lines where line.timeCode <= elapsed {
            active = line
        }
        return active?.id
    }
}

// MARK: - Lyrics View

struct AudiophileLyricsView: View {

    @ObservedObject var loader:  LyricsLoader
    var elapsed: Double           // current playback position

    var body: some View {
        ZStack {
            if loader.isLoaded && !loader.lines.isEmpty {
                lyricsList
            } else if !loader.isLoaded {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No lyrics available")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                }
            } else {
                ProgressView()
                    .tint(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
        .preferredColorScheme(.dark)
    }

    private var lyricsList: some View {
        let activeID = loader.activeLine(at: elapsed)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .center, spacing: 20) {
                    ForEach(loader.lines) { line in
                        let isActive = line.id == activeID
                        Text(line.text.isEmpty ? " " : line.text)
                            .id(line.id)
                            .font(isActive
                                  ? .title3.weight(.bold)
                                  : .body.weight(.regular))
                            .foregroundColor(isActive ? .white : .white.opacity(0.35))
                            .multilineTextAlignment(.center)
                            .scaleEffect(isActive ? 1.05 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 60)
            }
            .onChange(of: elapsed) { _ in
                if let id = activeID {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let loader = LyricsLoader()
    loader.lines = [
        LRCLine(timeCode: 0,  text: "Hello, it's me"),
        LRCLine(timeCode: 5,  text: "I was wondering if after all these years"),
        LRCLine(timeCode: 10, text: "You'd like to meet to go over everything"),
        LRCLine(timeCode: 15, text: "They say that time's supposed to heal ya"),
        LRCLine(timeCode: 20, text: "But I ain't done much healing")
    ]
    loader.isLoaded  = true
    loader.hasTiming = true
    return AudiophileLyricsView(loader: loader, elapsed: 10)
}
