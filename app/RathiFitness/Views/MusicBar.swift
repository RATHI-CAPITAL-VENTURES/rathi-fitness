import SwiftUI
#if canImport(MusicKit)
import MusicKit
#endif

/// The music, as small as it can be and still be usable with one hand and a
/// barbell in the other.
///
/// It is deliberately not a player: no scrubber, no queue, no second screen.
/// What is here is the three things you reach for mid-workout — is this the
/// right track, stop it, skip it — plus the cover, which is doing more work
/// than it looks like it is.
///
/// **The first cut was a grey card and it was the worst-looking thing in the
/// app.** `RFDesign.surface` as a fill made the only opaque box in a system
/// whose entire surface treatment is a dark ground with a pool of light on it,
/// and it landed immediately under the primary button — two rounded rectangles
/// of similar width stacked, the second being the one you care about least. Its
/// three transport glyphs were identical 30×30 targets, under the 44pt minimum
/// and with no hierarchy between "pause" and "skip".
///
/// So: no card. A hairline, like every other division on that screen. One solid
/// control — play/pause, in the room's current colour — and one quiet one. And
/// the artwork, which is the only photograph anywhere in this app and is why
/// the row reads as something playing rather than something configured.
struct MusicBar: View {
    @EnvironmentObject private var music: MusicController
    @EnvironmentObject private var rest: RestTimer
    @State private var picking = false

    /// The room's colour right now — the same call the ring and the background
    /// make, so there is no second opinion about what "now" looks like.
    private var accent: Color {
        rest.isResting ? RFDesign.coolColor(rest.progress()) : RFDesign.ready
    }

    var body: some View {
        Group {
            switch music.status {
            case .ready:
                ready
            case .unknown:
                connect
            case .denied, .unavailable:
                // Not an error banner. If music is not available this is simply
                // an app without music in it, and it says so once, quietly.
                Text(music.status.message)
                    .font(RFDesign.ui(12))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .sheet(isPresented: $picking) { MusicSheet() }
        .task { await music.refreshQuietly() }
    }

    private var connect: some View {
        Button { Task { await music.connect() } } label: {
            HStack(spacing: 7) {
                Image(systemName: "music.note")
                Text("Play your music here")
            }
            .font(RFDesign.ui(13))
            .foregroundStyle(RFDesign.label)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var ready: some View {
        VStack(spacing: 0) {
            Divider().overlay(RFDesign.hairline)
            HStack(spacing: 12) {
                // The cover and the words are one target: mid-set you are not
                // aiming at a 12pt caption.
                Button { picking = true } label: {
                    HStack(spacing: 12) {
                        Cover(accent: accent, playing: music.isPlaying)
                            .environmentObject(music)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(music.now?.title
                                 ?? music.favouritePlaylist
                                 ?? "Choose a playlist")
                                .font(RFDesign.uiMedium(14))
                                .foregroundStyle(RFDesign.speech)
                                .lineLimit(1)
                            Text(music.now?.artist ?? "Tap to pick a playlist")
                                .font(RFDesign.ui(12))
                                .foregroundStyle(RFDesign.labelDim)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(music.now.map { "Playing \($0.title)" } ?? "Choose a playlist")

                // One solid control, one quiet one. Skipping backwards lives in
                // the sheet: on this screen it is the least-wanted of the three
                // and it was taking the same weight as pause.
                PlayButton(accent: accent, playing: music.isPlaying) {
                    if music.now == nil { await music.startFavourite() }
                    else { await music.togglePlayPause() }
                }
                Glyph(symbol: "forward.fill", label: "Next track",
                      tint: RFDesign.label) { await music.next() }
            }
            .padding(.top, 12)
        }
    }
}

/// The cover, at the size a thumb can hit.
///
/// Falls back to a lit tile rather than a grey square — a placeholder that is
/// merely absent looks like a failed download, and this one takes the room's
/// colour so the row still says something while a track has no art.
private struct Cover: View {
    @EnvironmentObject private var music: MusicController
    var accent: Color
    var playing: Bool

    private let side: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(RFDesign.surfaceHigh)
                .overlay {
                    RadialGradient(colors: [accent.opacity(playing ? 0.34 : 0.16), .clear],
                                   center: .topLeading, startRadius: 2, endRadius: side)
                }
            #if canImport(MusicKit)
            if let artwork = music.artwork {
                ArtworkImage(artwork, width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .id(music.artworkToken)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(accent.opacity(0.85))
            }
            #else
            Image(systemName: "music.note")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent.opacity(0.85))
            #endif
        }
        .frame(width: side, height: side)
        .overlay {
            // A hairline, so a dark cover does not dissolve into the ground.
            RoundedRectangle(cornerRadius: 9).stroke(RFDesign.hairline, lineWidth: 1)
        }
        .animation(RFDesign.quick, value: music.artworkToken)
    }
}

/// The one filled control on the row, in the room's current colour.
private struct PlayButton: View {
    var accent: Color
    var playing: Bool
    var action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(RFDesign.ground)
                .frame(width: 38, height: 38)
                .background(Circle().fill(accent))
                .frame(width: 44, height: 44)      // the target, not the disc
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "Pause" : "Play")
        .animation(RFDesign.quick, value: playing)
    }
}

private struct Glyph: View {
    var symbol: String
    var label: String
    var tint: Color
    var action: () async -> Void

    var body: some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Pick what plays. Your playlists, in the order you made them, and a star for
/// the one a workout starts with by default.
struct MusicSheet: View {
    @EnvironmentObject private var music: MusicController
    @EnvironmentObject private var remote: RemoteControls
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $music.shuffle) {
                        Text("Shuffle").font(RFDesign.ui(15))
                    }
                    .tint(RFDesign.ready)
                } header: {
                    Text("How").rfEyebrow()
                }

                Section {
                    if music.playlistNames.isEmpty {
                        Text("No playlists in your library yet.")
                            .font(RFDesign.ui(13.5))
                            .foregroundStyle(RFDesign.labelDim)
                    }
                    ForEach(music.playlistNames, id: \.self) { name in
                        Button {
                            Task {
                                await music.play(playlistNamed: name)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(name)
                                    .font(RFDesign.ui(15))
                                    .foregroundStyle(RFDesign.speech)
                                Spacer()
                                Button {
                                    music.favouritePlaylist =
                                        music.favouritePlaylist == name ? nil : name
                                } label: {
                                    Image(systemName: music.favouritePlaylist == name
                                          ? "star.fill" : "star")
                                        .foregroundStyle(music.favouritePlaylist == name
                                                         ? RFDesign.ready : RFDesign.labelDim)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Playlists").rfEyebrow()
                } footer: {
                    Text("The starred one starts when you tap play with nothing queued. "
                         + "Apple Music's catalogue isn't searchable here on purpose — "
                         + "a gym app plays the list you already made.")
                        .font(RFDesign.ui(12))
                        .foregroundStyle(RFDesign.labelDim)
                }

                Section {
                    HandsFreeSummary()
                } header: {
                    Text("AirPods").rfEyebrow()
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle("Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The three gestures and what they currently do, in three lines. Shown wherever
/// someone might be about to squeeze something and wonder.
struct HandsFreeSummary: View {
    @EnvironmentObject private var remote: RemoteControls

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if remote.enabled {
                ForEach(RemoteControls.Gesture.allCases) { gesture in
                    HStack(alignment: .top, spacing: 8) {
                        Text(gesture.label)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.labelDim)
                            .frame(width: 96, alignment: .leading)
                        Text(gesture.action.label)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.speech)
                    }
                }
            } else {
                Text("Hands-free is off. The AirPods control your music the way they always did.")
                    .font(RFDesign.ui(12.5))
                    .foregroundStyle(RFDesign.labelDim)
            }
        }
        .padding(.vertical, 2)
    }
}
