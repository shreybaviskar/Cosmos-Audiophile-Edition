// AudiophileDashboardView.swift — Cosmos Audiophile Edition
// Shows the current track's hi-res specs plus the active output device,
// sample rate, and bit-perfect status — inspired by audiophile app dashboards.

import SwiftUI

// MARK: - Audiophile Dashboard View

struct AudiophileDashboardView: View {

    @ObservedObject var dacManager: DACOutputManager

    // Track metadata to display
    var formatName:   String   // e.g. "FLAC", "DSD256", "WAV", "ALAC"
    var bitDepth:     Int?     // e.g. 24
    var sampleRateHz: Double?  // e.g. 96000

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.1))
            statsGrid
            if dacManager.isExternalDAC {
                Divider().background(Color.white.opacity(0.1))
                dacRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            Text("Audiophile Info")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)

            Spacer()

            if dacManager.isBitPerfect {
                bitPerfectBadge
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statCell(
                label: "Format",
                value: formatName,
                color: formatColor
            )
            dividerV
            statCell(
                label: "Bit Depth",
                value: bitDepth.map { "\($0)-bit" } ?? "—",
                color: .cyan
            )
            dividerV
            statCell(
                label: "Sample Rate",
                value: sampleRateHz.map { formattedSampleRate($0) } ?? "—",
                color: .purple
            )
        }
        .padding(.vertical, 16)
    }

    private func statCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerV: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    // MARK: - DAC Row

    private var dacRow: some View {
        HStack(spacing: 10) {
            Image(systemName: dacManager.outputType.sfSymbol)
                .font(.footnote)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(dacManager.dacName)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(dacManager.isBitPerfect
                     ? "Bit-perfect @ \(formattedSampleRate(dacManager.outputSampleRate))"
                     : "Output @ \(formattedSampleRate(dacManager.outputSampleRate))")
                    .font(.caption2)
                    .foregroundColor(dacManager.isBitPerfect ? .green : .gray)
            }

            Spacer()

            Image(systemName: "cable.connector")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Bit Perfect Badge

    private var bitPerfectBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("Bit-Perfect")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func formattedSampleRate(_ hz: Double) -> String {
        let khz = hz / 1000
        if khz.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(khz)) kHz"
        } else {
            return String(format: "%.1f kHz", khz)
        }
    }

    private var formatColor: Color {
        switch formatName.uppercased() {
        case "FLAC":           return .orange
        case "DSD256", "DSD64","DSD128", "DSF", "DFF": return .yellow
        case "ALAC":           return .mint
        case "WAV", "AIFF":    return .cyan
        case "MP3", "AAC":     return .gray
        default:               return .white
        }
    }
}

// MARK: - Format Badge (standalone small widget)

struct FormatBadgeView: View {
    let format: String
    var bitDepth: Int?
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            Text(format.uppercased())
                .font(compact ? .system(size: 9, weight: .black) : .caption2.weight(.black))
                .foregroundColor(.black)
                .padding(.horizontal, compact ? 5 : 7)
                .padding(.vertical, compact ? 2 : 3)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 4))

            if let bd = bitDepth, !compact {
                Text("\(bd)-bit")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var badgeColor: Color {
        switch format.uppercased() {
        case "FLAC":                         return .orange
        case "DSD256","DSD128","DSD64","DFF","DSF": return .yellow
        case "ALAC":                         return .mint
        case "WAV", "AIFF":                  return .cyan
        default:                             return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            AudiophileDashboardView(
                dacManager: DACOutputManager.shared,
                formatName:   "FLAC",
                bitDepth:     24,
                sampleRateHz: 96_000
            )
            HStack(spacing: 10) {
                FormatBadgeView(format: "FLAC", bitDepth: 24)
                FormatBadgeView(format: "DSD256")
                FormatBadgeView(format: "WAV", bitDepth: 32)
                FormatBadgeView(format: "MP3")
            }
        }
    }
    .preferredColorScheme(.dark)
}
