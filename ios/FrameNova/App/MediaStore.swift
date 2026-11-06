import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

final class ProjectStore: ObservableObject {
    static let root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FrameNova", isDirectory: true)
    @Published var projects: [Project] = []
    @Published var error: String? {didSet {if let error {AppLog.record(error)}}}
    private let directory: URL
    init(directory: URL = ProjectStore.root) { self.directory = directory; refresh() }
    static func mediaURL(_ path: String) -> URL { root.appendingPathComponent("Media").appendingPathComponent(path) }
    func refresh() {
        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("Media"), withIntermediateDirectories: true)
            projects = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(Project.self, from: Data(contentsOf: $0)) }.sorted { $0.modifiedAt > $1.modifiedAt }
        } catch { self.error = error.localizedDescription }
    }
    func save(_ project: Project) throws {
        var project = project; project.modifiedAt = Date()
        try JSONEncoder().encode(project).write(to: directory.appendingPathComponent(project.id+".json"), options: .atomic)
        refresh()
    }
    func delete(_ project: Project) throws {
        try FileManager.default.removeItem(at: directory.appendingPathComponent(project.id+".json")); refresh()
        try? FileManager.default.removeItem(at:directory.appendingPathComponent("Covers").appendingPathComponent(project.id,isDirectory:true))
        let referenced = Set(projects.flatMap(\.assets).map(\.path))
        for asset in project.assets where !referenced.contains(asset.path) { try? FileManager.default.removeItem(at: directory.appendingPathComponent("Media").appendingPathComponent(asset.path)) }
    }
    func coverSource(_ project:Project)->(asset:MediaAsset,time:Int64)? {
        if let cover = project.asset(project.coverAssetID),cover.type == .image {return (cover,0)}
        let clips = project.tracks[project.mainIndex].clips+project.tracks.flatMap(\.clips)
        guard let clip = clips.first(where:{project.asset($0.assetID).map {$0.type != .audio} == true}),let asset = project.asset(clip.assetID) else {return nil}
        return (asset,clip.srcInUs)
    }
    func coverKey(_ project:Project)->String {
        guard let source = coverSource(project) else {return "empty"}
        let framing = project.asset(project.coverAssetID)?.type == .image ? "-\(project.framing.zoom)-\(project.framing.panX)-\(project.framing.panY)-\(project.canvas.aspect.rawValue)":""
        return MediaThumbnailStore.sourceKey(source.asset)+"-\(source.time)"+framing
    }
    func coverURL(_ project:Project)->URL {
        directory.appendingPathComponent("Covers").appendingPathComponent(project.id,isDirectory:true).appendingPathComponent(coverKey(project)+".jpg")
    }
    @MainActor func cover(_ project:Project) async ->UIImage? {
        guard let source = coverSource(project) else {return nil}
        let file = coverURL(project)
        if let image = await Task.detached(priority:.utility,operation:{UIImage(contentsOfFile:file.path)}).value {return image}
        guard var image = await MediaThumbnailStore.shared.image(source.asset,at:source.time,size:.cover) else {return nil}
        if source.asset.type == .image {
            // Shaped like the video and placed as the cover framing says, as in the export.
            let ratio = project.canvas.aspect.ratio,frame = CGSize(width:360*ratio,height:360),at = project.framing.placement(photo:image.size,frame:frame)
            let format = UIGraphicsImageRendererFormat();format.scale = 1
            image = UIGraphicsImageRenderer(size:frame,format:format).image {_ in image.draw(in:at)}
        }
        guard FileManager.default.fileExists(atPath:directory.appendingPathComponent(project.id+".json").path) else {return image}
        await Task.detached(priority:.utility) {
            let folder = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            if let data = image.jpegData(compressionQuality:0.85) {try? data.write(to:file,options:.atomic)}
            if let files = try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
                for old in files where old != file {try? FileManager.default.removeItem(at:old)}
            }
        }.value
        return image
    }
    static func ingest(_ url: URL) async throws -> MediaAsset {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased(), path = newID()+"."+ext, destination = mediaURL(path)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let coordinator = NSFileCoordinator()
        var coordinationError:NSError?,copyError:Error?
        coordinator.coordinate(readingItemAt:url,options:[],error:&coordinationError) {readable in
            do {try FileManager.default.copyItem(at:readable,to:destination)} catch {copyError = error}
        }
        if let error = copyError ?? coordinationError {try? FileManager.default.removeItem(at:destination);throw error}
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
    var errorDescription: String? { switch self { case .invalid: return String(localized: "This media cannot be opened."); case .export: return String(localized: "The export could not be created."); case .missing(let name): return String(localized: "Missing media: \(name)") } }
}
