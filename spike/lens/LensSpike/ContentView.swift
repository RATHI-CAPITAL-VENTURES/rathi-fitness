import SwiftUI

// SwiftUI only — nothing from Meta is imported here, so `Text` and `Button`
// mean what they always mean.

/// The phone side. A bench tool, not a face: it has to be operable with chalk
/// on your hands and readable at a glance, and that is the whole brief.
struct ContentView: View {
    @ObservedObject var log: SpikeLog
    @ObservedObject var audio: SilentAudio
    @ObservedObject var glasses: Glasses
    @ObservedObject var experiments: Experiments

    @State private var note = ""

    /// The things only a person can see. The phone has no idea whether the lens
    /// is lit, so half the evidence for questions 4, 5 and 7 is one of these.
    private let sightings = [
        "lens is showing it", "lens is dim", "lens is dark",
        "woke on its own", "stayed dark after a send",
        "a notification covered it", "came back by itself", "did not come back",
        "middle-tap left the app", "middle-tap did nothing",
        "first button was lit", "nothing was lit", "list scrolled", "list was cut off",
    ]

    var body: some View {
        NavigationStack {
            List {
                status
                setup
                questions
                sightingsSection
                logSection
            }
            .navigationTitle("Lens spike")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Sections

    private var status: some View {
        Section("Now") {
            row("Registration", glasses.registration)
            if glasses.devices.isEmpty {
                row("Glasses", "none seen")
            } else {
                ForEach(glasses.devices, id: \.self) { Text($0).font(.footnote.monospaced()) }
            }
            HStack {
                Text("Link")
                Spacer()
                Text(glasses.link)
                    .foregroundStyle(glasses.link == "connected" ? .green : .orange)
                    .font(.callout.monospaced())
            }
            if glasses.registration == "registered", glasses.link != "connected" {
                Text("The glasses are not connected to this app. Put them on, unfolded and awake, and wait for this to turn green — nothing below can work until it does.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            row("Firmware", glasses.compatibility)
            row("Session", glasses.sessionState)
            row("Lens", glasses.displayState)
            if let error = glasses.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Toggle("Hold the app open with silent audio", isOn: Binding(
                get: { audio.isOn }, set: { audio.set($0) }))
        }
    }

    private var setup: some View {
        Section("Setup") {
            // Registering twice is an error, not a no-op — Meta AI answers "User
            // is already registered" — so the button goes away once it is done.
            if glasses.registration != "registered" {
                Button("Register with Meta AI") { Task { await glasses.register() } }
            }
            Button("Connect") { Task { await glasses.connect() } }
                .disabled(!glasses.canConnect)
            Button("Disconnect") { glasses.disconnect() }
            if glasses.needsGlassesAppUpdate {
                Button("Update the app on the glasses") { Task { await glasses.openGlassesAppUpdate() } }
                    .foregroundStyle(.orange)
            }
            if glasses.needsFirmwareUpdate {
                Button("Update the glasses firmware") { Task { await glasses.openFirmwareUpdate() } }
                    .foregroundStyle(.orange)
            }
            Button("Unregister", role: .destructive) { Task { await glasses.unregister() } }
        }
    }

    private var questions: some View {
        Section {
            if let running = experiments.running {
                HStack {
                    ProgressView()
                    Text(running).font(.footnote)
                    Spacer()
                    Button("Stop") { experiments.stop() }.buttonStyle(.bordered)
                }
            }
            Group {
                Button("1 · Does anything appear?") { experiments.hello() }
                Button("2 · Pocket test — 10 min, text clock") { experiments.countdown(minutes: 10, asImage: false) }
                Button("2 · Pocket test — 10 min, image clock") { experiments.countdown(minutes: 10, asImage: true) }
                Button("2 · Short run — 2 min, text clock") { experiments.countdown(minutes: 2, asImage: false) }
                Button("3 · What does one send cost?") { experiments.benchmark() }
                Button("4 · Does the lens sleep through a rest?") { experiments.quietRest() }
                Button("4b · How long can it stay quiet?") { experiments.gapLadder() }
                Button("6 · Does a tall list scroll?") { experiments.tallList() }
                Button("7 · Which button is lit, and what does back do?") { experiments.focusProbe() }
            }
            .disabled(experiments.running != nil || !glasses.canConnect)
        } header: {
            Text("Questions")
        } footer: {
            Text("Question 5 has no button: start a pocket test and text yourself. Pinches heard so far: \(experiments.pinches).")
        }
    }

    private var sightingsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(sightings, id: \.self) { sighting in
                        Button(sighting) { log.add("SAW", sighting) }
                            .buttonStyle(.bordered)
                            .font(.footnote)
                    }
                }
            }
            HStack {
                TextField("Anything else you saw", text: $note)
                Button("Note") {
                    guard !note.isEmpty else { return }
                    log.add("SAW", note)
                    note = ""
                }
            }
        } header: {
            Text("What you saw")
        } footer: {
            Text("The phone cannot see the lens. Tap what happened and it is stamped into the log with the time.")
        }
    }

    private var logSection: some View {
        Section {
            ShareLink("Send the log", item: log.fileURL)
            Button("Clear the log", role: .destructive) { log.clear() }
            ForEach(Array(log.lines.suffix(60).reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10, design: .monospaced))
            }
        } header: {
            Text("Log — newest first")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).font(.callout.monospaced())
        }
    }
}
