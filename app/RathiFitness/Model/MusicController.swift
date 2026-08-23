import Foundation
import Combine
#if canImport(MusicKit)
import MusicKit
#endif

/// Music, played by this app.
///
/// There are two ways to put music in a gym app and they are not close:
///
///  - **Remote-control the Music app** (`MPMusicPlayerController.systemMusicPlayer`).
///    Trivial to write. But the Music app stays the now-playing app, so every
///    AirPods squeeze goes there and this app can never hear one.
///  - **Play it ourselves** (`ApplicationMusicPlayer`, below). The app becomes
///    the now-playing app, which is the *only* way `RemoteControls` gets to see
///    a triple-press and turn it into a logged set.
///
/// The second was chosen because hands-free logging is the point. The cost is
/// real and worth stating: the queue lives here, not in Music, and the app needs
/// the MusicKit service enabled on the App ID. Without it — and on the
/// local-only build — `status` reports `.unavailable` and the player is hidden
/// rather than failing at a button.
///
/// **What is deliberately not here:** the Apple Music *catalogue* (search,
/// recommendations, radio). Those need a developer token and a subscription
/// check, and a gym app does not browse — it plays the playlist you already
/// made. Your library's playlists, albums and songs are all reachable.
@MainActor
final class MusicController: ObservableObject {

    enum Status: Equatable {
        case unknown
        /// The device or build cannot do this — no MusicKit service on the App ID.
        case unavailable
        case denied
        case ready

        var isReady: Bool { self == .ready }

        var message: String {
            switch self {
            case .unknown: return "Not connected yet."
            case .unavailable: return "Music isn't available in this build."
            case .denied: return "Music access was declined. Settings → Privacy → Media & Apple Music."
            case .ready: return "Connected."
            }
        }
    }

    /// What is on right now, flattened out of MusicKit so the views do not have
    /// to import it.
    struct NowPlaying: Equatable {
        var title: String
        var artist: String?
        var isPlaying: Bool
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var now: NowPlaying?
    /// Library playlists, newest first. Empty until `connect()`.
    @Published private(set) var playlistNames: [String] = []
    @Published var shuffle: Bool = UserDefaults.standard.bool(forKey: "music.shuffle") {
        didSet {
            UserDefaults.standard.set(shuffle, forKey: "music.shuffle")
            applyShuffle()
        }
    }

    /// The playlist the workout starts with, remembered between sessions so
    /// "start my music" is one tap on the day you cannot be bothered.
    @Published var favouritePlaylist: String? =
        UserDefaults.standard.string(forKey: "music.favourite") {
        didSet { UserDefaults.standard.set(favouritePlaylist, forKey: "music.favourite") }
    }

    #if canImport(MusicKit)
    private var playlists: [Playlist] = []
    private var watchers: Set<AnyCancellable> = []
    private var player: ApplicationMusicPlayer { .shared }
    #endif

    var isPlaying: Bool { now?.isPlaying ?? false }

    // MARK: - Connecting

    /// Ask once, then load the library. Called from Settings and from the first
    /// tap on the player — never at launch, for the same reason the notification
    /// permission is not asked at launch.
    func connect() async {
        #if canImport(MusicKit)
        switch await MusicAuthorization.request() {
        case .authorized:
            status = .ready
            await loadPlaylists()
            watch()
            refreshNowPlaying()
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            status = .unknown
        @unknown default:
            status = .unknown
        }
        #else
        status = .unavailable
        #endif
    }

    /// Pick up an already-granted authorization without prompting, so a
    /// returning user sees the player rather than a connect button.
    func refreshQuietly() async {
        #if canImport(MusicKit)
        switch MusicAuthorization.currentStatus {
        case .authorized:
            status = .ready
            await loadPlaylists()
            watch()
            refreshNowPlaying()
        case .denied, .restricted:
            status = .denied
        default:
            status = .unknown
        }
        #else
        status = .unavailable
        #endif
    }

    #if canImport(MusicKit)
    private func loadPlaylists() async {
        var request = MusicLibraryRequest<Playlist>()
        request.sort(by: \.libraryAddedDate, ascending: false)
        guard let response = try? await request.response() else { return }
        playlists = Array(response.items)
        playlistNames = playlists.map(\.name)
    }

    /// MusicKit publishes changes on the player's state and queue; without
    /// these the transport buttons would go stale the moment a track ended.
    private func watch() {
        guard watchers.isEmpty else { return }
        player.state.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in self?.refreshNowPlaying() }
            }
            .store(in: &watchers)
        player.queue.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in self?.refreshNowPlaying() }
            }
            .store(in: &watchers)
    }

    private func refreshNowPlaying() {
        guard status.isReady else { return }
        guard let entry = player.queue.currentEntry else {
            now = nil
            return
        }
        now = NowPlaying(title: entry.title,
                         artist: entry.subtitle,
                         isPlaying: player.state.playbackStatus == .playing)
    }
    #else
    private func refreshNowPlaying() {}
    #endif

    // MARK: - Transport
    //
    // Every one of these is also reachable from an AirPods squeeze; see
    // `RemoteControls`. They are `async` because MusicKit's are, and they
    // swallow their errors because a failed skip is not worth a dialog while
    // someone is under a bar.

    func togglePlayPause() async {
        #if canImport(MusicKit)
        guard status.isReady else { return }
        if player.state.playbackStatus == .playing {
            player.pause()
        } else {
            try? await player.play()
        }
        refreshNowPlaying()
        #endif
    }

    func next() async {
        #if canImport(MusicKit)
        guard status.isReady else { return }
        try? await player.skipToNextEntry()
        refreshNowPlaying()
        #endif
    }

    func previous() async {
        #if canImport(MusicKit)
        guard status.isReady else { return }
        // Matches every other player: part-way into a track, "back" restarts it.
        if player.playbackTime > 3 {
            player.playbackTime = 0
        } else {
            try? await player.skipToPreviousEntry()
        }
        refreshNowPlaying()
        #endif
    }

    /// Nudge the whole session's loudness. The system volume is not ours to
    /// set — `MPVolumeView` is the only sanctioned control and it is a slider,
    /// so the player screen shows one rather than pretending buttons exist.
    func play(playlistNamed name: String) async {
        #if canImport(MusicKit)
        guard status.isReady, let playlist = playlists.first(where: { $0.name == name })
        else { return }
        player.queue = ApplicationMusicPlayer.Queue(for: [playlist])
        applyShuffle()
        try? await player.prepareToPlay()
        try? await player.play()
        refreshNowPlaying()
        #endif
    }

    /// The one-tap start: the remembered playlist, or the newest one you made.
    func startFavourite() async {
        guard let name = favouritePlaylist ?? playlistNames.first else { return }
        await play(playlistNamed: name)
    }

    private func applyShuffle() {
        #if canImport(MusicKit)
        guard status.isReady else { return }
        player.state.shuffleMode = shuffle ? .songs : .off
        #endif
    }
}
