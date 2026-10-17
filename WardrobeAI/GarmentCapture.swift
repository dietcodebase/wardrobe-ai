import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

enum GarmentCaptureError: LocalizedError {
    case cameraUnavailable
    case cameraDenied
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: "This device does not have a camera available. Choose a photo instead."
        case .cameraDenied: "Camera access is off. Allow it in Settings, or choose a photo instead."
        case .unreadableImage: "That photo could not be read. Please try another one."
        }
    }
}

@MainActor
enum CameraAccess {
    static func request() async throws {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw GarmentCaptureError.cameraUnavailable
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { throw GarmentCaptureError.cameraDenied }
        case .denied, .restricted: throw GarmentCaptureError.cameraDenied
        @unknown default: throw GarmentCaptureError.cameraDenied
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { onCancel(); return }
            onImage(image)
        }
    }
}

struct GarmentPhotoSource: View {
    let onImage: (UIImage) -> Void
    @State private var selectedItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var error: GarmentCaptureError?

    var body: some View {
        HStack {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Choose photo", systemImage: "photo.on.rectangle")
            }
            .accessibilityLabel("Choose garment photo from library")
            Button { requestCamera() } label: { Label("Camera", systemImage: "camera") }
                .accessibilityLabel("Photograph garment")
        }
        .buttonStyle(.bordered)
        .task(id: selectedItem) { await loadSelectedPhoto() }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker(onImage: { image in isShowingCamera = false; onImage(image) }, onCancel: { isShowingCamera = false })
                .ignoresSafeArea()
        }
        .alert("Couldn’t use camera", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    private func requestCamera() {
        Task {
            do { try await CameraAccess.request(); isShowingCamera = true }
            catch let captureError as GarmentCaptureError { error = captureError }
            catch { error = .cameraDenied }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedItem else { return }
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                error = .unreadableImage
                return
            }
            onImage(image)
        } catch {
            error = .unreadableImage
        }
    }
}
