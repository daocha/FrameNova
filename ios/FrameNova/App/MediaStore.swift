import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

final class ProjectStore: ObservableObject {
    static let root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FrameNova", isDirectory: true)
    @Published var projects: [Project] = []
    @Published var error: String? {didSet {if let error {AppLog.record(error)}}}
    init() { refresh() }
    static func mediaURL(_ path: String) -> URL { root.appendingPathComponent("Media").appendingPathComponent(path) }
    func refresh() {
        do {
            try FileManager.default.createDirectory(at: Self.root.appendingPathComponent("Media"), withIntermediateDirectories: true)
            projects = try FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(Project.self, from: Data(contentsOf: $0)) }.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch { self.error = error.localizedDescription }
    }
    func save(_ project: Project) throws {
        var project = project; project.modifiedAt = Date()
        try JSONEncoder().encode(project).write(to: Self.root.appendingPathComponent(project.id+".json"), options: .atomic)
        refresh()
    }
    func delete(_ project: Project) throws {
        try FileManager.default.removeItem(at: Self.root.appendingPathComponent(project.id+".json")); refresh()
        let referenced = Set(projects.flatMap(\.assets).map(\.path))
        for asset in project.assets where !referenced.contains(asset.path) { try? FileManager.default.removeItem(at: Self.mediaURL(asset.path)) }
    }
    static func ingest(_ url: URL) async throws -> MediaAsset {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased(), path = newID()+"."+ext, destination = mediaURL(path)
        try FileManager.default.copyItem(at: url, to: destination)
        do {
            if let image = UIImage(contentsOfFile: destination.path) {
                return MediaAsset(path: path,type: .image,name: url.lastPathComponent,durationUs: 3_000_000,width: Int(image.size.width*image.scale),height: Int(image.size.height*image.scale))
            }
            let asset = AVURLAsset(url: destination), duration = try await asset.load(.duration)
            let videos = try await asset.loadTracks(withMediaType: .video), audios = try await asset.loadTracks(withMediaType: .audio)
            guard !videos.isEmpty || !audios.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else { throw MediaError.invalid }
            var result = MediaAsset(path: path,type: videos.isEmpty ? .audio : .video,name: url.lastPathComponent,durationUs: Int64(duration.seconds*1_000_000),hasAudio: !audios.isEmpty)
            if let video = videos.first {
                let size = try await video.load(.naturalSize), transform = try await video.load(.preferredTransform)
                let rect = CGRect(origin: .zero,size: size).applying(transform)
                result.width = Int(abs(rect.width)); result.height = Int(abs(rect.height)); result.frameRate = Double(try await video.load(.nominalFrameRate))
            }
            return result
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
}
enum MediaError: LocalizedError {
    case invalid, export, missing(String)
    var errorDescription: String? { switch self { case .invalid: return "This media cannot be opened."; case .export: return "The export could not be created."; case .missing(let name): return "Missing media: \(name)" } }
}
struct MediaPicker: UIViewControllerRepresentable {
    var completion: ([MediaAsset], String?) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared()); config.selectionLimit = 0; config.selection = .ordered; config.filter = .any(of: [.videos,.images]); config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: ([MediaAsset], String?) -> Void
        init(_ completion: @escaping ([MediaAsset], String?) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            Task { @MainActor in
                var media: [MediaAsset] = [], failures: [String] = []
                for result in results {
                    let provider = result.itemProvider
                    let type = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ? UTType.movie.identifier : UTType.image.identifier
                    do {
                        let local: URL = try await withCheckedThrowingContinuation { continuation in
                            provider.loadFileRepresentation(forTypeIdentifier: type) { url,error in
                                guard let url else { continuation.resume(throwing: error ?? MediaError.invalid); return }
                                let dest = FileManager.default.temporaryDirectory.appendingPathComponent(newID()+"."+url.pathExtension)
                                do { try FileManager.default.copyItem(at: url,to: dest); continuation.resume(returning: dest) }
                                catch { continuation.resume(throwing: error) }
                            }
                        }
                        defer { try? FileManager.default.removeItem(at: local) }
                        media.append(try await ProjectStore.ingest(local))
                    } catch { failures.append(error.localizedDescription) }
                }
                completion(media,failures.isEmpty ? nil : failures.joined(separator:"\n"))
            }
        }
    }
}
