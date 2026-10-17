import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

struct AverageSwatch: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var color: Color { Color(red: red, green: green, blue: blue) }
}

struct GarmentCaptureCandidate: Identifiable, @unchecked Sendable {
    enum Kind: String { case original, foreground }

    let id = UUID()
    let kind: Kind
    let image: UIImage
    let data: Data
    let swatch: AverageSwatch
}

private struct ImagePreparationInput: @unchecked Sendable {
    let image: UIImage
}

enum GarmentImagePreparation {
    static func originalCandidate(from image: UIImage, maximumDimension: CGFloat = 1_600) throws -> GarmentCaptureCandidate {
        let normalized = normalizedImage(from: image, maximumDimension: maximumDimension)
        guard let data = normalized.jpegData(compressionQuality: 0.9) else { throw GarmentCaptureError.unreadableImage }
        return GarmentCaptureCandidate(kind: .original, image: normalized, data: data, swatch: averageSwatch(for: normalized))
    }

    static func foregroundCandidates(from original: GarmentCaptureCandidate) throws -> [GarmentCaptureCandidate] {
        guard let cgImage = original.image.cgImage else { return [] }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return [] }

        let source = CIImage(cgImage: cgImage)
        let clearBackground = CIImage(color: .clear).cropped(to: source.extent)
        let context = CIContext(options: nil)
        return try observation.allInstances.compactMap { instance in
            let maskBuffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
            let cutout = source.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: clearBackground,
                    kCIInputMaskImageKey: CIImage(cvPixelBuffer: maskBuffer)
                ]
            )
            guard let output = context.createCGImage(cutout, from: source.extent) else { return nil }
            let image = UIImage(cgImage: output)
            guard let data = image.pngData() else { return nil }
            return GarmentCaptureCandidate(kind: .foreground, image: image, data: data, swatch: averageSwatch(for: image))
        }
    }

    static func averageSwatch(for image: UIImage) -> AverageSwatch {
        guard let cgImage = image.cgImage else { return AverageSwatch(red: 0.5, green: 0.5, blue: 0.5) }
        var pixels = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixels, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return AverageSwatch(red: 0.5, green: 0.5, blue: 0.5) }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let alpha = CGFloat(pixels[3]) / 255
        guard alpha > 0 else { return AverageSwatch(red: 0.5, green: 0.5, blue: 0.5) }
        return AverageSwatch(
            red: min(1, CGFloat(pixels[0]) / 255 / alpha),
            green: min(1, CGFloat(pixels[1]) / 255 / alpha),
            blue: min(1, CGFloat(pixels[2]) / 255 / alpha)
        )
    }

    private static func normalizedImage(from image: UIImage, maximumDimension: CGFloat) -> UIImage {
        let sourceSize = image.size
        let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(width: max(1, floor(sourceSize.width * scale)), height: max(1, floor(sourceSize.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

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
    @State private var photoError: GarmentCaptureError?

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
        .alert("Couldn’t use camera", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(photoError?.localizedDescription ?? "") }
    }

    private func requestCamera() {
        Task {
            do { try await CameraAccess.request(); isShowingCamera = true }
            catch let captureError as GarmentCaptureError { photoError = captureError }
            catch { photoError = .cameraDenied }
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedItem else { return }
        do {
            guard let data = try await selectedItem.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                photoError = .unreadableImage
                return
            }
            onImage(image)
        } catch {
            photoError = .unreadableImage
        }
    }
}

struct GarmentCaptureSheet: View {
    let onSelect: (GarmentCaptureCandidate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [GarmentCaptureCandidate] = []
    @State private var selection: UUID?
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Add a garment photo", systemImage: "camera")
                    } description: {
                        Text("Take a single-item photo or choose one from your library. You can keep the full photo if no cutout is useful.")
                    } actions: {
                        GarmentPhotoSource(onImage: prepare)
                    }
                } else {
                    List {
                        Section("Choose preview") {
                            ForEach(candidates) { candidate in
                                Button { selection = candidate.id } label: {
                                    HStack {
                                        Image(uiImage: candidate.image).resizable().scaledToFill().frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading) {
                                            Text(candidate.kind == .foreground ? "Foreground selection" : "Use original photo")
                                            HStack { Circle().fill(candidate.swatch.color).frame(width: 12, height: 12); Text("Average swatch") }
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selection == candidate.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                    }
                                }.buttonStyle(.plain).accessibilityLabel(candidate.kind == .foreground ? "Select foreground cutout" : "Select original photo")
                            }
                        }
                        Section { GarmentPhotoSource(onImage: prepare) } footer: { Text("If the foreground choices are wrong or incomplete, choose the original photo and continue editing manually.") }
                    }
                }
            }
            .overlay { if isPreparing { ProgressView("Preparing photo…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .navigationTitle("Garment photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if let selectedCandidate { ToolbarItem(placement: .confirmationAction) { Button("Use photo") { onSelect(selectedCandidate); dismiss() } } }
            }
            .alert("Couldn’t prepare photo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var selectedCandidate: GarmentCaptureCandidate? {
        candidates.first { $0.id == selection }
    }

    private func prepare(_ image: UIImage) {
        isPreparing = true
        let input = ImagePreparationInput(image: image)
        Task { @MainActor in
            defer { isPreparing = false }
            let result = await Task.detached(priority: .userInitiated) { () -> (candidates: [GarmentCaptureCandidate]?, errorMessage: String?) in
                do {
                    let original = try GarmentImagePreparation.originalCandidate(from: input.image)
                    do {
                        return ([original] + (try GarmentImagePreparation.foregroundCandidates(from: original)), nil)
                    } catch {
                        return ([original], nil)
                    }
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            if let preparedCandidates = result.candidates {
                candidates = preparedCandidates
                selection = preparedCandidates.first?.id
            } else {
                errorMessage = result.errorMessage
            }
        }
    }
}
