// PlaylistsView.swift — Cosmos Audiophile Edition
// Full playlists tab: list all playlists, create manual/smart ones, view details.

import SwiftUI

// MARK: - Playlists Root View

struct PlaylistsView: View {

    @ObservedObject var playlistManager: PlaylistManager

    @State private var showCreateSheet   = false
    @State private var newPlaylistName   = ""
    @State private var createType:       PlaylistType = .manual
    @State private var showDeleteAlert   = false
    @State private var deletingPlaylist: Playlist?
    @State private var searchText        = ""

    var filteredPlaylists: [Playlist] {
        guard !searchText.isEmpty else { return playlistManager.playlists }
        return playlistManager.playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                if playlistManager.playlists.isEmpty {
                    emptyState
                } else {
                    playlistList
                }
            }
            .navigationTitle("Playlists")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            createType    = .manual
                            showCreateSheet = true
                        }) {
                            Label("New Playlist", systemImage: "plus")
                        }
                        Button(action: {
                            createType    = .smart
                            showCreateSheet = true
                        }) {
                            Label("New Smart Playlist", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showCreateSheet) { createPlaylistSheet }
            .alert("Delete Playlist", isPresented: $showDeleteAlert, presenting: deletingPlaylist) { pl in
                Button("Delete", role: .destructive) { playlistManager.delete(id: pl.id) }
                Button("Cancel", role: .cancel) {}
            } message: { pl in
                Text("Delete \"\(pl.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundColor(.orange.opacity(0.6))
            Text("No Playlists Yet")
                .font(.title2.weight(.semibold))
            Text("Create a playlist to organise your music your way.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: {
                createType      = .manual
                showCreateSheet = true
            }) {
                Label("New Playlist", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
    }

    // MARK: - Playlist List

    private var playlistList: some View {
        List {
            if !filteredPlaylists.filter({ $0.type == .smart }).isEmpty {
                Section(header: Text("Smart Playlists")) {
                    ForEach(filteredPlaylists.filter { $0.type == .smart }) { pl in
                        playlistRow(pl)
                    }
                    .onDelete { offsets in
                        let smart = filteredPlaylists.filter { $0.type == .smart }
                        offsets.forEach { playlistManager.delete(id: smart[$0].id) }
                    }
                }
            }

            Section(header: Text("My Playlists")) {
                ForEach(filteredPlaylists.filter { $0.type == .manual }) { pl in
                    playlistRow(pl)
                }
                .onDelete { offsets in
                    let manual = filteredPlaylists.filter { $0.type == .manual }
                    offsets.forEach { playlistManager.delete(id: manual[$0].id) }
                }
                .onMove { playlistManager.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func playlistRow(_ pl: Playlist) -> some View {
        NavigationLink(destination: PlaylistDetailView(playlist: pl, manager: playlistManager)) {
            HStack(spacing: 14) {
                // Cover icon / artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(pl.type == .smart
                              ? Color.purple.opacity(0.2)
                              : Color.orange.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: pl.type == .smart ? "wand.and.stars" : "music.note.list")
                        .font(.title3)
                        .foregroundColor(pl.type == .smart ? .purple : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(pl.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(pl.trackIds.count) songs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if pl.type == .smart {
                            Text("· Smart")
                                .font(.caption)
                                .foregroundColor(.purple.opacity(0.8))
                        }
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deletingPlaylist = pl
                showDeleteAlert  = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Create Playlist Sheet

    private var createPlaylistSheet: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 24) {
                    Image(systemName: createType == .smart ? "wand.and.stars" : "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(createType == .smart ? .purple : .orange)
                        .padding(.top, 30)

                    Text(createType == .smart ? "New Smart Playlist" : "New Playlist")
                        .font(.title2.weight(.semibold))

                    TextField("Playlist name", text: $newPlaylistName)
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal)

                    if createType == .smart {
                        Text("Smart playlist rules can be configured after creation.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }

                    Button {
                        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        if createType == .manual {
                            playlistManager.createManual(name: name)
                        } else {
                            playlistManager.createSmart(name: name, rules: [])
                        }
                        newPlaylistName = ""
                        showCreateSheet = false
                    } label: {
                        Text("Create")
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color.gray.opacity(0.3) : Color.orange)
                            .foregroundColor(newPlaylistName.isEmpty ? .secondary : .black)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        newPlaylistName = ""
                        showCreateSheet = false
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {

    let playlist: Playlist
    @ObservedObject var manager: PlaylistManager

    var body: some View {
        List {
            if playlist.type == .smart {
                Section("Rules") {
                    ForEach(playlist.rules) { rule in
                        HStack {
                            Text(rule.field.rawValue)
                                .font(.subheadline.weight(.medium))
                            Text(rule.op.rawValue)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(rule.value)
                                .font(.subheadline)
                        }
                    }
                    if playlist.rules.isEmpty {
                        Text("No rules configured yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Tracks (\(playlist.trackIds.count))") {
                if playlist.trackIds.isEmpty {
                    Text("No tracks yet. Add songs from the Library.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(playlist.trackIds, id: \.self) { id in
                        Text("Track ID: \(id)")   // Replace with a real TrackRowView
                            .font(.subheadline)
                    }
                    .onDelete { offsets in
                        offsets.forEach { i in
                            manager.removeTrack(id: playlist.trackIds[i], fromPlaylist: playlist.id)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {}) {
                    Image(systemName: "play.fill")
                }
                .foregroundColor(.orange)
            }
        }
    }
}

#Preview {
    PlaylistsView(playlistManager: PlaylistManager())
}
