import AVFoundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct QualificationApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @State private var mode: ProbeMode = .text
    @State private var mtp = false
    @State private var e4b = false
    @State private var importing = false
    @State private var running = false
    @State private var status = "Choose a capability and a folder containing verified models and synthetic fixtures."
    @State private var report: URL?
    @State private var captureProbe: RuntimeProbe?
    @State private var captureFolder: URL?
    @State private var captureCount = 0
    @State private var isShowingCamera = false
    @State private var pendingCapture: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Capability", selection: $mode) {
                    ForEach(ProbeMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(captureProbe != nil)
                Toggle("MTP (separate on/off runs)", isOn: $mtp).disabled(captureProbe != nil)
                Toggle("E4B (optional, after E2B)", isOn: $e4b)
                    .disabled(captureProbe != nil || mode == .capture)
                if captureProbe == nil {
                    Button(runButtonTitle) { importing = true }
                } else {
                    Button("Capture photo \(captureCount + 1) of 10") { requestCamera() }
                        .disabled(running || captureCount >= 10)
                    Button("End camera run") { finishCameraRun(completed: false) }
                        .disabled(running)
                }
                Text(status)
                if let report { ShareLink("Export measurements", item: report) }
            }
            .disabled(running && captureProbe == nil)
            .navigationTitle("M01 Qualification")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { selection in
                switch selection {
                case .failure(let error): status = error.localizedDescription
                case .success(let folder):
                    if mode == .capture { startCameraRun(folder: folder) }
                    else { runFixtureProbe(folder: folder) }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera, onDismiss: processPendingCapture) {
                ProbeCameraPicker(onImage: { image in
                    pendingCapture = image
                    isShowingCamera = false
                }, onCancel: { isShowingCamera = false })
                .ignoresSafeArea()
            }
        }
    }

    private var runButtonTitle: String {
        switch mode {
        case .capture: "Select model folder for camera run"
        case .switching: "Select folder and run 10 switching cycles"
        default: "Select folder and run 20 operations"
        }
    }

    private func runFixtureProbe(folder: URL) {
        running = true
        status = "Running. Keep the app foreground. Capture peak memory with Instruments."
        let selectedMode = mode, selectedMTP = mtp, selectedE4B = e4b
        Task {
            guard folder.startAccessingSecurityScopedResource() else {
                status = "Folder access denied."; running = false; return
            }
            defer { folder.stopAccessingSecurityScopedResource(); running = false }
            let id = UUID().uuidString
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let output = documents.appendingPathComponent("probe-\(id).json")
            let cache = FileManager.default.temporaryDirectory.appendingPathComponent("probe-\(id)")
            let probe = RuntimeProbe(output: output, cache: cache)
            do {
                try await probe.run(folder: folder, mode: selectedMode, e4b: selectedE4B, mtp: selectedMTP)
                status = "Run finished. Inspect outputs and Instruments before assigning a pass."
            } catch { status = "Run stopped: \(error). Completed samples are preserved." }
            report = FileManager.default.fileExists(atPath: output.path) ? output : nil
            try? FileManager.default.removeItem(at: cache)
        }
    }

    private func startCameraRun(folder: URL) {
        guard folder.startAccessingSecurityScopedResource() else {
            status = "Folder access denied."
            return
        }
        running = true
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let id = UUID().uuidString
        let output = documents.appendingPathComponent("camera-probe-\(id).json")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("camera-probe-\(id)")
        let probe = RuntimeProbe(output: output, cache: cache)
        Task {
            do {
                try await probe.startCaptureSession(folder: folder, mtp: mtp)
                captureProbe = probe
                captureFolder = folder
                captureCount = 0
                report = output
                status = "Ready. Take ten separate camera photos; the camera closes before each inference."
            } catch {
                folder.stopAccessingSecurityScopedResource()
                status = "Camera run could not start: \(error)"
                try? FileManager.default.removeItem(at: cache)
            }
            running = false
        }
    }

    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            status = "No camera is available on this device."
            return
        }
        Task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: isShowingCamera = true
            case .notDetermined:
                isShowingCamera = await AVCaptureDevice.requestAccess(for: .video)
                if !isShowingCamera { status = "Camera access was denied." }
            default: status = "Camera access is unavailable. Enable it in Settings."
            }
        }
    }

    private func processPendingCapture() {
        guard let image = pendingCapture, let probe = captureProbe else { return }
        pendingCapture = nil
        running = true
        let iteration = captureCount + 1
        status = "Processing camera photo \(iteration) of 10…"
        Task {
            do {
                try await probe.inferCapturedPhoto(image, iteration: iteration)
                captureCount = iteration
                status = "Photo \(iteration) recorded. Inspect the exported response and Instruments trace."
                running = false
                if captureCount == 10 { finishCameraRun(completed: true) }
            } catch {
                status = "Photo \(iteration) failed: \(error). Retry that number; the failure is in the report."
                running = false
            }
        }
    }

    private func finishCameraRun(completed: Bool) {
        guard let probe = captureProbe else { return }
        running = true
        Task {
            do {
                try await probe.finishCaptureSession(completed: completed)
                status = completed ? "Ten camera operations recorded. Review outputs and memory trace." :
                    "Camera run ended before ten successful operations; report is incomplete."
            } catch { status = "Couldn’t finish report: \(error)" }
            captureFolder?.stopAccessingSecurityScopedResource()
            captureFolder = nil
            captureProbe = nil
            running = false
        }
    }
}

private struct ProbeCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { onCancel(); return }
            onImage(image)
        }
    }
}
