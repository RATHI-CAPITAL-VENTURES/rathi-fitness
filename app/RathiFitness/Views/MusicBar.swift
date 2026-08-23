import SwiftUI

/// The music, as small as it can be and still be usable with one hand and a
/// barbell in the other.
///
/// It is deliberately not a player. There is no scrubber, no artwork, no queue —
/// the screen it sits on is about the next set, and a 60pt album cover competing
/// with the cooldown ring would be the app forgetting what it is for. What is
/// here is the three things you reach for mid-workout: is this the right track,
/// stop it, skip it.
struct MusicBar: View {
    @EnvironmentObject private var music: MusicController
    @State private var picking = false

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
        HStack(spacing: 12) {
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: music.isPlaying ? "waveform" : "music.note.list")
                        .font(.system(size: 12))
                        .foregroundStyle(music.isPlaying ? RFDesign.ready : RFDesign.labelDim)
                        .symbolEffect(.variableColor, isActive: music.isPlaying)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.now?.title ?? (music.favouritePlaylist ?? "Choose a playlist"))
                            .font(RFDesign.uiMedium(13))
                            .foregroundStyle(RFDesign.speech)
                            .lineLimit(1)
                        if let artist = music.now?.artist {
                            Text(artist)
                                .font(RFDesign.ui(11.5))
                                .foregroundStyle(RFDesign.labelDim)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 14) {
                transport("backward.fill") { await music.previous() }
                transport(music.isPlaying ? "pause.fill" : "play.fill") {
                    if music.now == nil {
                        await music.startFavourite()
                    } else {
                        await music.togglePlayPause()
                    }
                }
                transport("forward.fill") { await music.next() }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RFDesign.surface, in: RoundedRectangle(cornerRadius: RFDesign.radiusSmall))
    }

    private func transport(_ symbol: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(RFDesign.speech)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.contains("backward") ? "Previous track"
                            : symbol.contains("forward") ? "Next track" : "Play or pause")
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
