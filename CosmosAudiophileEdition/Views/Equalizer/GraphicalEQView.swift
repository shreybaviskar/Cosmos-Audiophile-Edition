// GraphicalEQView.swift — Cosmos Audiophile Edition
// Apple Music-inspired 10-band graphical EQ with interactive sliders,
// a smooth frequency response curve, factory preset buttons, and
// a custom-preset save/load sheet.

import SwiftUI

// MARK: - Main EQ View

struct GraphicalEQView: View {

    @ObservedObject var eqManager: EqualizerManager
    @State private var showSaveSheet   = false
    @State private var customName      = ""
    @State private var showDeleteAlert = false
    @State private var deletingPreset: CustomEQPreset?

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        enableToggleRow
                        presetScrollRow
                        freqCurveCard
                        sliderGrid
                        customPresetsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save Preset") { showSaveSheet = true }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.orange)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") { eqManager.resetToFlat() }
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .sheet(isPresented: $showSaveSheet) { savePresetSheet }
            .alert("Delete Preset", isPresented: $showDeleteAlert, presenting: deletingPreset) { preset in
                Button("Delete", role: .destructive) { eqManager.deleteCustomPreset(id: preset.id) }
                Button("Cancel", role: .cancel) {}
            } message: { preset in
                Text("Delete \"\(preset.name)\"?")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Enable Toggle

    private var enableToggleRow: some View {
        HStack {
            Label("Equalizer", systemImage: "slider.horizontal.3")
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $eqManager.isEnabled)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Preset Scroll Row

    private var presetScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EQPreset.allCases.filter { $0 != .custom }) { preset in
                    presetChip(preset)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func presetChip(_ preset: EQPreset) -> some View {
        let isActive = eqManager.configuration.activePreset == preset
        return Button(action: { eqManager.apply(preset: preset) }) {
            Text(preset.rawValue)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundColor(isActive ? .black : .white)
                .background(isActive ? Color.orange : Color.white.opacity(0.1),
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Frequency Response Curve

    private var freqCurveCard: some View {
        ZStack {
            Color.white.opacity(0.05)
            FreqResponseCurveView(bands: eqManager.configuration.bands,
                                  isEnabled: eqManager.isEnabled)
                .padding(12)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Slider Grid

    private var sliderGrid: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(eqManager.configuration.bands) { band in
                BandSliderColumn(
                    band: band,
                    isEnabled: eqManager.isEnabled,
                    onGainChange: { gain in
                        eqManager.setGain(gain, atBandIndex: band.id)
                    }
                )
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Custom Presets Section

    private var customPresetsSection: some View {
        Group {
            if !eqManager.configuration.customPresets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Presets")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.gray)

                    ForEach(eqManager.configuration.customPresets) { preset in
                        customPresetRow(preset)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func customPresetRow(_ preset: CustomEQPreset) -> some View {
        HStack {
            Text(preset.name)
                .font(.body)
                .foregroundColor(.white)
            Spacer()
            Button("Apply") { eqManager.applyCustomPreset(preset) }
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)
                .padding(.trailing, 8)
            Button {
                deletingPreset  = preset
                showDeleteAlert = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
        }
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Save Current Settings")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)
                    TextField("Preset name", text: $customName)
                        .padding(14)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .foregroundColor(.white)
                    Button {
                        eqManager.saveCurrentAsCustomPreset(name: customName)
                        customName     = ""
                        showSaveSheet  = false
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color.orange)
                            .cornerRadius(12)
                            .foregroundColor(.black)
                            .font(.headline)
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showSaveSheet = false }
                        .foregroundColor(.gray)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Band Slider Column

private struct BandSliderColumn: View {
    let band: EQBand
    let isEnabled: Bool
    let onGainChange: (Float) -> Void

    @State private var sliderVal: Double

    init(band: EQBand, isEnabled: Bool, onGainChange: @escaping (Float) -> Void) {
        self.band         = band
        self.isEnabled    = isEnabled
        self.onGainChange = onGainChange
        _sliderVal        = State(initialValue: Double(band.gain))
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: "%.0f", band.gain > 0 ? band.gain : band.gain))
                .font(.system(size: 8))
                .foregroundColor(gain == 0 ? .gray : (gain > 0 ? .orange : .cyan))
                .frame(height: 12)

            SliderVertical(value: $sliderVal, range: -12...12) { newVal in
                onGainChange(Float(newVal))
            }
            .frame(width: 28, height: 140)
            .opacity(isEnabled ? 1 : 0.4)
            .disabled(!isEnabled)
            .onChange(of: band.gain) { sliderVal = Double(band.gain) }

            Text(band.frequencyLabel)
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private var gain: Double { Double(band.gain) }
}

// MARK: - Vertical Slider

struct SliderVertical: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let thumbY = valueToY(height: height)

            ZStack {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                // Fill above zero
                let zeroY = valueToY(value: 0, height: height)
                let fillTop    = min(thumbY, zeroY)
                let fillHeight = abs(thumbY - zeroY)
                Capsule()
                    .fill(value >= 0 ? Color.orange : Color.cyan)
                    .frame(width: 4, height: max(2, fillHeight))
                    .offset(y: fillTop - height / 2 + fillHeight / 2)

                // Zero line
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 8, height: 1)
                    .offset(y: zeroY - height / 2)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: thumbY - height / 2)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newVal = yToValue(y: gesture.location.y, height: height)
                        value = newVal
                        onChange(newVal)
                    }
            )
        }
    }

    private func valueToY(height: CGFloat) -> CGFloat {
        valueToY(value: value, height: height)
    }

    private func valueToY(value: Double, height: CGFloat) -> CGFloat {
        let pct = (value - range.upperBound) / (range.lowerBound - range.upperBound)
        return CGFloat(pct) * height
    }

    private func yToValue(y: CGFloat, height: CGFloat) -> Double {
        let pct = y / height
        let val = range.upperBound + pct * (range.lowerBound - range.upperBound)
        return min(range.upperBound, max(range.lowerBound, val))
    }
}

// MARK: - Frequency Response Curve

struct FreqResponseCurveView: View {
    let bands: [EQBand]
    let isEnabled: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Grid lines at ±6 dB and ±12 dB
                ForEach([-12, -6, 0, 6, 12], id: \.self) { db in
                    let y = gainToY(Float(db), height: h)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(db == 0 ? Color.white.opacity(0.2) : Color.white.opacity(0.07),
                            lineWidth: db == 0 ? 1 : 0.5)
                }

                // Response curve
                curvePath(width: w, height: h)
                    .stroke(
                        LinearGradient(
                            colors: [.orange, .yellow],
                            startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(isEnabled ? 1 : 0.3)
            }
        }
    }

    // Smooth Catmull-Rom-style curve through all band gain points
    private func curvePath(width: CGFloat, height: CGFloat) -> Path {
        let freqs = EQConfiguration.standardFrequencies
        let minF  = Float(20)
        let maxF  = Float(20_000)

        let points: [CGPoint] = freqs.enumerated().compactMap { i, freq in
            guard i < bands.count else { return nil }
            let x = CGFloat(log10(freq / minF) / log10(maxF / minF)) * width
            let y = gainToY(bands[i].gain, height: height)
            return CGPoint(x: x, y: y)
        }

        guard points.count >= 2 else { return Path() }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: gainToY(0, height: height)))
        path.addLine(to: points[0])

        for i in 0..<points.count - 1 {
            let p1 = points[i]
            let p2 = points[i + 1]
            let cp1 = CGPoint(x: p1.x + (p2.x - p1.x) / 3, y: p1.y)
            let cp2 = CGPoint(x: p2.x - (p2.x - p1.x) / 3, y: p2.y)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        path.addLine(to: CGPoint(x: width, y: gainToY(0, height: height)))
        return path
    }

    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let pct = CGFloat((gain + 12) / 24)
        return height * (1 - pct)
    }
}

// MARK: - Preview

#Preview {
    GraphicalEQView(eqManager: EqualizerManager())
}
