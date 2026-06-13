// FolderLibraryView.swift — Cosmos Audiophile Edition
// Shows all watched library folders, lets the user add folders via
// UIDocumentPickerViewController, remove them, and trigger a re-scan.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Folder Library View

struct FolderLibraryView: View {

    @ObservedObject var folderManager: FolderScanManager
    var onScanComplete: ((FolderScanResult) -> Void)? = nil

    @State private var showPicker     = false
    @State private var errorMessage:  String?
    @State private var showError      = false
    @State private var scanResult:    FolderScanResult?
    @State private var showScanSheet  = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if folderManager.folders.isEmpty && !folderManager.isScanning {
                    emptyState
                } else {
                    folderList
                }

                // Scan progress overlay
                if folderManager.isScanning {
                    scanProgressOverlay
                }
            }
            .navigationTitle("Music Folders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    addButton
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if !folderManager.folders.isEmpty {
                        rescanButton
                        Spacer()
                        lastScanLabel
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                FolderPickerRepresentable { url in
                    do {
                        try folderManager.add(url: url)
                    } catch {
                        errorMessage = error.localizedDescription
                        showError    = true
                    }
                }
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { msg in
                Text(msg)
            }
        }
    }

    // MARK: - Sub-views

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.7))
            Text("No Music Folders")
                .font(.title2.weight(.semibold))
            Text("Tap + to add a folder.\nThe app will scan it recursively for FLAC, WAV, DSD and other audio files.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showPicker = true }) {
                Label("Add Folder", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
    }

    private var folderList: some View {
        List {
            Section("Watched Folders") {
                ForEach(folderManager.folders) { folder in
                    FolderRowView(folder: folder)
                }
                .onDelete { offsets in
                    folderManager.remove(atOffsets: offsets)
                }
            }

            Section {
                Button(action: { showPicker = true }) {
                    Label("Add Another Folder", systemImage: "folder.badge.plus")
                        .foregroundColor(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addButton: some View {
        Button(action: { showPicker = true }) {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
        }
    }

    private var rescanButton: some View {
        Button(action: triggerScan) {
            Label("Rescan All", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.medium))
        }
        .disabled(folderManager.isScanning)
    }

    private var lastScanLabel: some View {
        Group {
            if let date = folderManager.lastScanDate {
                Text("Last scan: \(date, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scanProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: folderManager.scanProgress)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(width: 240)
                Text(folderManager.scanStatusMessage)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Actions

    private func triggerScan() {
        Task {
            let result = await folderManager.scanAll()
            onScanComplete?(result)
        }
    }
}

// MARK: - Folder Row

private struct FolderRowView: View {
    let folder: ScannedFolder

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("\(folder.trackCount) tracks")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if folder.lastScannedAt > .distantPast {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(folder.lastScannedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.tertiaryLabel)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Folder Picker (UIDocumentPickerViewController Wrapper)

struct FolderPickerRepresentable: UIViewControllerRepresentable {

    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

// MARK: - File Picker (for individual audio files)

struct FilePicker: UIViewControllerRepresentable {

    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept any audio type the system recognises, plus explicit UTTypes
        let types: [UTType] = [.audio, .mp3, .wav, .aiff,
                               UTType("public.flac")!, UTType("public.dsf")!]
            .compactMap { $0 }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection  = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Preview

#Preview {
    FolderLibraryView(folderManager: FolderScanManager())
}
