// WaveformProgressView.swift — Cosmos Audiophile Edition
// An animated waveform-style progress bar (scrubber) for the Now Playing screen.
// Includes a sine-composite animation that pulses with playback.

import SwiftUI

// MARK: - Waveform Progress Scrubber

struct WaveformProgressView: View {

    /// 0 … 1  progress
    @Binding var progress: Double
    /// Whether playback is currently active
    var isPlaying: Bool
    /// Seek callback — passes new 0…1 position
    var onSeek: ((Double) -> Void)?

    @State private var animPhase: Double = 0
    @State private var isDragging       = false
    @State private var dragProgress: Double = 0

    private let barCount = 40
    private let animSpeed = 1.8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .leading) {
                // Background bars
                barStack(width: w, height: h, filled: false)

                // Filled bars (progress indicator)
                barStack(width: w, height: h, filled: true)
                    .mask(
                        Rectangle()
                            .frame(width: w * (isDragging ? dragProgress : progress))
                            .offset(x: -(w * (1 - (isDragging ? dragProgress : progress))) / 2)
                    )

                // Playhead thumb
                let thumbX = w * (isDragging ? dragProgress : progress)
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(x: thumbX, y: h / 2)
                    .scaleEffect(isDragging ? 1.3 : 1.0)
                    .animation(.spring(response: 0.2), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        isDragging = true
                        dragProgress = max(0, min(1, val.location.x / w))
                    }
                    .onEnded { val in
                        let pos = max(0, min(1, val.location.x / w))
                        dragProgress = pos
                        onSeek?(pos)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDragging = false
                        }
                    }
            )
        }
        .onReceive(
            Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()
        ) { _ in
            if isPlaying {
                animPhase += animSpeed / 30
            }
        }
    }

    // MARK: - Bar Stack

    @ViewBuilder
    private func barStack(width: CGFloat, height: CGFloat, filled: Bool) -> some View {
        let barW    = (width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)
        let spacing = (width - barW * CGFloat(barCount)) / CGFloat(barCount - 1)

        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                let h = barHeight(index: i, totalHeight: height)
                RoundedRectangle(cornerRadius: 2)
                    .fill(filled ? activeBarGradient : Color.white.opacity(0.15))
                    .frame(width: barW, height: h)
                    .animation(.easeInOut(duration: 0.12), value: animPhase)
            }
        }
    }

    private func barHeight(index: Int, totalHeight: CGFloat) -> CGFloat {
        let baseH   = totalHeight * 0.35
        let phase   = animPhase + Double(index) * 0.35
        let wave1   = sin(phase * 1.3)
        let wave2   = sin(phase * 0.7 + 1.5)
        let wave    = (wave1 + wave2) / 2.0
        let animated = isPlaying ? wave * totalHeight * 0.28 : 0
        return max(4, baseH + CGFloat(animated))
    }

    private var activeBarGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .yellow],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Mini Spectrum Strip (decorative)
// Shown in the NowPlaying header — a compact bouncing bars animation.

struct SpectrumStripView: View {
    var isPlaying: Bool
    var barCount  = 8
    var color: Color = .orange

    @State private var phases: [Double] = []

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: barH(i))
            }
        }
        .onAppear {
            phases = (0..<barCount).map { Double($0) * 0.5 }
            if isPlaying { startAnimation() }
        }
        .onChange(of: isPlaying) { _ in
            if isPlaying { startAnimation() }
        }
    }

    private func barH(_ i: Int) -> CGFloat {
        guard isPlaying else { return 3 }
        let h = 4.0 + abs(sin(phases[i])) * 12.0
        return CGFloat(h)
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { timer in
            if !isPlaying { timer.invalidate(); return }
            for i in 0..<phases.count {
                phases[i] += Double.random(in: 0.15...0.45)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            WaveformProgressView(progress: .constant(0.42), isPlaying: true)
                .frame(height: 40)
                .padding(.horizontal, 30)

            SpectrumStripView(isPlaying: true)
        }
    }
}
