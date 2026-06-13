// SmartShuffleSettingsView.swift — Cosmos Audiophile Edition
// Settings sheet for the smart shuffle engine.

import SwiftUI

struct SmartShuffleSettingsView: View {

    @ObservedObject var shuffleManager: SmartShuffleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                List {
                    modeSection
                    constraintsSection
                    historySection
                    infoSection
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Shuffle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        shuffleManager.saveSettings()
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        Section(header: Text("Shuffle Mode")) {
            ForEach(ShuffleMode.allCases) { mode in
                Button(action: { shuffleManager.mode = mode }) {
                    HStack(spacing: 14) {
                        Image(systemName: mode.systemImage)
                            .font(.title3)
                            .foregroundColor(shuffleManager.mode == mode ? .orange : .secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.rawValue)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if shuffleManager.mode == mode {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Constraints Section

    private var constraintsSection: some View {
        Section(
            header: Text("Smart Constraints"),
            footer: Text("These options only apply in Smart mode.")
        ) {
            Toggle(isOn: $shuffleManager.avoidSameArtist) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid Same Artist")
                        Text("No two consecutive tracks from the same artist")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.fill")
                        .foregroundColor(.orange)
                }
            }
            .tint(.orange)
            .disabled(shuffleManager.mode != .smart)

            Toggle(isOn: $shuffleManager.avoidSameAlbum) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid Same Album")
                        Text("Spreads album tracks across the queue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.stack.fill")
                        .foregroundColor(.orange)
                }
            }
            .tint(.orange)
            .disabled(shuffleManager.mode != .smart)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section(
            header: Text("Play History Weighting"),
            footer: Text("Recently played and frequently skipped tracks appear less often.")
        ) {
            Toggle(isOn: $shuffleManager.weightByPlayHistory) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weight by History")
                        Text("Favourites surface more; often-skipped tracks less")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                }
            }
            .tint(.orange)
            .disabled(shuffleManager.mode != .smart)

            Button(role: .destructive) {
                shuffleManager.clearHistory()
            } label: {
                Label("Clear Play History", systemImage: "trash")
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Smart shuffle uses a weighted algorithm inspired by Poweramp's advanced shuffle, ensuring a varied listening experience without pure randomness.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    SmartShuffleSettingsView(shuffleManager: SmartShuffleManager())
}
