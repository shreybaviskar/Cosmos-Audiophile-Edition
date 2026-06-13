// AppEnvironment.swift — Cosmos Audiophile Edition
// Single source of truth for all service instances.
// Inject via @EnvironmentObject into every View.

import Foundation
import Combine

@MainActor
final class AppEnvironment: ObservableObject {

    // MARK: - Services
    let eqManager:      EqualizerManager
    let dacManager:     DACOutputManager
    let shuffleManager: SmartShuffleManager
    let folderManager:  FolderScanManager
    let playlistManager: PlaylistManager
    let engine:         GaplessPlaybackEngine

    // MARK: - Init
    init() {
        let eq      = EqualizerManager()
        let dac     = DACOutputManager.shared
        let shuffle = SmartShuffleManager()

        eqManager      = eq
        dacManager     = dac
        shuffleManager = shuffle
        folderManager  = FolderScanManager()
        playlistManager = PlaylistManager()
        engine         = GaplessPlaybackEngine(
            eqManager:      eq,
            dacManager:     dac,
            shuffleManager: shuffle
        )

        shuffle.loadSettings()
        shuffle.loadHistory()
    }
}
