import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceDropTarget {
    var kind: TrackKind?
    var trackID: String?
    var time: Int64 = 0
    static let library = WorkspaceDropTarget()
}

@MainActor enum WorkspaceDrop {
    static let types = [UTType.fileURL.identifier, UTType.plainText.identifier]
    static let assetPrefix = "framenova-asset:"

    static func accept(_ providers: [NSItemProvider], model: EditorModel, target: WorkspaceDropTarget) -> Bool {
        guard !providers.isEmpty, !model.busy else { return false }
        if let id = target.trackID, model.project.tracks.first(where: { $0.id == id })?.locked != false { return false }
        model.busy = true
        Task {
            defer { model.busy = false }
            var media: [MediaAsset] = []
            var failures: [String] = []
            for provider in providers {
                do {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let url: URL = try await withCheckedThrowingContinuation { continuation in
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                                if let url = value as? URL { continuation.resume(returning: url) }
                                else if let data = value as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { continuation.resume(returning: url) }
                                else { continuation.resume(throwing: error ?? MediaError.invalid) }
                            }
                        }
                        media.append(try await ProjectStore.ingest(url))
                    } else {
                        let value: String = try await withCheckedThrowingContinuation { continuation in
                            provider.loadObject(ofClass: NSString.self) { value, error in
                                if let text = value as? String { continuation.resume(returning: text) }
                                else { continuation.resume(throwing: error ?? MediaError.invalid) }
                            }
                        }
                        guard value.hasPrefix(assetPrefix), let asset = model.project.asset(String(value.dropFirst(assetPrefix.count))) else { continue }
                        media.append(asset)
                    }
                } catch { failures.append(error.localizedDescription) }
            }
            // A drop is one undo step, including multi-file drops in their supplied order.
            model.change { project in
                if let kind = target.kind {
                    var cursor = target.time
                    for asset in media {
                        if let id = project.insertAsset(asset, kind: kind, trackID: target.trackID, at: cursor) {
                            model.selected = id
                            if kind == .main { cursor = project.clip(id)?.endUs ?? cursor }
                        } else {
                            project.addLibraryAssets([asset])
                            failures.append("\(asset.name) was added to Media because it is incompatible with the destination track.")
                        }
                    }
                } else { project.addLibraryAssets(media) }
            }
            if !failures.isEmpty { model.error = failures.joined(separator: "\n") }
        }
        return true
    }
}

struct TimelineMediaDrop: DropDelegate {
    let model: EditorModel
    let geometry: TimelineGeometry
    let kind: TrackKind
    let trackID: String?
    @Binding var hoverTime: Int64?

    func validateDrop(info: DropInfo) -> Bool {
        kind != .text && (trackID == nil || model.project.tracks.first(where: { $0.id == trackID })?.locked == false)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        hoverTime = geometry.snap(geometry.time(at: info.location.x), project: model.project, playhead: model.playhead)
        return DropProposal(operation: .copy)
    }
    func dropExited(info: DropInfo) { hoverTime = nil }
    func performDrop(info: DropInfo) -> Bool {
        let time = geometry.snap(geometry.time(at: info.location.x), project: model.project, playhead: model.playhead)
        hoverTime = nil
        return WorkspaceDrop.accept(info.itemProviders(for: WorkspaceDrop.types), model: model,
                                    target: WorkspaceDropTarget(kind: kind, trackID: trackID, time: time))
    }
}
