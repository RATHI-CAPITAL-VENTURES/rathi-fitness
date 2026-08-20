import SwiftUI
import AVFoundation
import PhotosUI

/// Add or change a stored pass. Every field a real card carries.
struct PassEditor: View {
    struct Draft {
        var existing: GymPass?
        var name = ""
        var location = ""
        var code = ""
        var symbology: GymPass.Symbology = .qr
        var memberID = ""
        var isPrimary = false
        var hasExpiry = false
        var expires = Date.now
        var usesLeft = 0
        var punches = 0
        var punchesNeeded = 0
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Draft
    @State private var scanning = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var reading = false
    @State private var importError: String?
    private let onSave: (Draft) -> Void
    private let onDelete: (() -> Void)?

    init(pass: GymPass?, onSave: @escaping (Draft) -> Void, onDelete: (() -> Void)? = nil) {
        var d = Draft(existing: pass)
        if let pass {
            d.name = pass.name; d.location = pass.location; d.code = pass.code
            d.symbology = pass.format; d.memberID = pass.memberID
            d.isPrimary = pass.isPrimary
            d.hasExpiry = pass.expires != nil
            d.expires = pass.expires ?? .now
            d.usesLeft = pass.usesLeft
            d.punches = pass.punches; d.punchesNeeded = pass.punchesNeeded
        }
        _draft = State(initialValue: d)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The gym") {
                    TextField("Blink Fitness", text: $draft.name)
                    TextField("Union Square", text: $draft.location)
                    Toggle("Hold this one up at the door", isOn: $draft.isPrimary)
                }

                Section {
                    HStack(spacing: 14) {
                        TextField("Scan, import or type the code", text: $draft.code)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button { scanning = true } label: {
                            Image(systemName: "camera.viewfinder")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(RFDesign.ready)
                        .accessibilityLabel("Scan the code with the camera")

                        // The card is usually in a drawer at home; the code is
                        // usually already a screenshot in the camera roll.
                        PhotosPicker(selection: $pickedPhoto, matching: .images) {
                            Image(systemName: reading ? "hourglass" : "photo.on.rectangle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(RFDesign.ready)
                        .disabled(reading)
                        .accessibilityLabel("Find the code in a picture")
                    }
                    if let importError {
                        Text(importError)
                            .font(RFDesign.ui(12.5))
                            .foregroundStyle(RFDesign.ember)
                    }
                    Picker("Format", selection: $draft.symbology) {
                        ForEach(GymPass.Symbology.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    TextField("Member number (optional)", text: $draft.memberID)
                } header: {
                    Text("The code")
                } footer: {
                    Text("Point the camera at the card, or pull the code out of a screenshot "
                         + "you already have — either way the format fills itself in. "
                         + "The code stays on your devices; it is never written to the "
                         + "snapshot RIA reads.")
                }

                Section("What it's good for") {
                    Toggle("Expires", isOn: $draft.hasExpiry)
                    if draft.hasExpiry {
                        DatePicker("On", selection: $draft.expires, displayedComponents: .date)
                    }
                    Stepper("Uses left: \(draft.usesLeft == 0 ? "unlimited" : String(draft.usesLeft))",
                            value: $draft.usesLeft, in: 0...99)
                    Stepper("Punch card: \(draft.punchesNeeded == 0 ? "no" : "\(draft.punches) of \(draft.punchesNeeded)")",
                            value: $draft.punchesNeeded, in: 0...50)
                    if draft.punchesNeeded > 0 {
                        Stepper("Punched: \(draft.punches)", value: $draft.punches,
                                in: 0...draft.punchesNeeded)
                    }
                }

                if let onDelete {
                    Section {
                        Button("Delete this pass", role: .destructive) {
                            onDelete(); dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFDesign.ground.ignoresSafeArea())
            .navigationTitle(draft.existing == nil ? "Add a pass" : "Edit pass")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft); dismiss() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await readCode(from: item) }
            }
            .sheet(isPresented: $scanning) {
                CodeScanner { value, symbology in
                    draft.code = value
                    if let symbology { draft.symbology = symbology }
                    scanning = false
                }
            }
        }
    }

    private func readCode(from item: PhotosPickerItem) async {
        reading = true
        importError = nil
        defer { reading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw CodeDetector.Failure.noImage
            }
            let found = try await CodeDetector.detect(in: image)
            draft.code = found.value
            draft.symbology = found.symbology
        } catch {
            importError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

/// Reads a code off a physical membership card.
///
/// Accepts every symbology the app can draw, so what you scan is what you can
/// show — a scanner that reads formats the renderer cannot produce would store a
/// code you can never display.
struct CodeScanner: UIViewControllerRepresentable {
    var onFound: (String, GymPass.Symbology?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onFound: (String, GymPass.Symbology?) -> Void
        private var handled = false

        init(onFound: @escaping (String, GymPass.Symbology?) -> Void) { self.onFound = onFound }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput objects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !handled,
                  let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue, !value.isEmpty else { return }
            handled = true
            DispatchQueue.main.async {
                self.onFound(value, ScannerController.symbology(for: object.type))
            }
        }
    }

    final class ScannerController: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?

        /// The scanner's vocabulary, mapped to what the renderer can draw back.
        static let supported: [(AVMetadataObject.ObjectType, GymPass.Symbology)] = [
            (.qr, .qr), (.code128, .code128), (.pdf417, .pdf417), (.aztec, .aztec),
        ]

        static func symbology(for type: AVMetadataObject.ObjectType) -> GymPass.Symbology? {
            supported.first { $0.0 == type }?.1
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
            output.metadataObjectTypes = Self.supported.map(\.0)

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !session.isRunning else { return }
            // Starting the session blocks; the docs are explicit about this.
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }
    }
}
