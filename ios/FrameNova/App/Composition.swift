import AVFoundation
import CoreImage
import UIKit

func mediaTime(_ us: Int64) -> CMTime { CMTime(value: us,timescale: 1_000_000) }
final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = true
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let renderSize:CGSize
    private let snapshot:Project
    private let previewState:PreviewProjectState?
    var project:Project {previewState?.project ?? snapshot}
    let sources: [String: CMPersistentTrackID]
    let orientations: [String: CGAffineTransform]
    init(project: Project, sources: [String: CMPersistentTrackID], orientations: [String: CGAffineTransform],previewState:PreviewProjectState? = nil,renderSize:CGSize? = nil) {
        self.renderSize = renderSize ?? CGSize(width:project.canvas.size.width,height:project.canvas.size.height)
        self.snapshot = project;self.previewState = previewState; self.sources = sources; self.orientations = orientations
        timeRange = CMTimeRange(start: .zero,duration: mediaTime(project.durationUs))
        requiredSourceTrackIDs = sources.values.map { NSNumber(value:$0) }
    }
}
struct BuiltComposition {
    let asset: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
    func playerItem() -> AVPlayerItem { let item = AVPlayerItem(asset:asset); item.videoComposition = video; item.audioMix = audio; item.audioTimePitchAlgorithm = .spectral; return item }
}
enum CompositionFactory {
    static func build(_ project: Project,previewState:PreviewProjectState? = nil) async throws -> BuiltComposition {
        let composition = AVMutableComposition()
        var sources: [String:CMPersistentTrackID] = [:], orientations: [String:CGAffineTransform] = [:]
        var audioParams: [AVAudioMixInputParameters] = []
        for track in project.tracks {
            for clip in track.clips {
                guard let media = project.asset(clip.assetID), media.type != .image else { continue }
                let url = ProjectStore.mediaURL(media.path)
                guard FileManager.default.fileExists(atPath:url.path) else { throw MediaError.missing(media.name) }
                let source = AVURLAsset(url:url)
                let range = CMTimeRange(start:mediaTime(clip.srcInUs),end:mediaTime(clip.srcOutUs))
                let start = mediaTime(clip.startUs), duration = mediaTime(clip.durationUs)
                if media.type == .video && !clip.audioOnly && !track.hidden {
                    if let input = try await source.loadTracks(withMediaType:.video).first,
                       let output = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) {
                        try output.insertTimeRange(range,of:input,at:start)
                        output.scaleTimeRange(CMTimeRange(start:start,duration:range.duration),toDuration:duration)
                        sources[clip.id] = output.trackID; orientations[clip.id] = try await input.load(.preferredTransform)
                    }
                }
                if media.hasAudio && !track.muted && clip.volume > 0 {
                    if let input = try await source.loadTracks(withMediaType:.audio).first,
                       let output = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
                        try output.insertTimeRange(range,of:input,at:start)
                        output.scaleTimeRange(CMTimeRange(start:start,duration:range.duration),toDuration:duration)
                        let params = AVMutableAudioMixInputParameters(track:output), volume = Float(clip.volume)
                        params.audioTimePitchAlgorithm = .spectral
                        params.setVolume(volume,at:start)
                        let fadeIn = min(clip.fadeInUs,clip.durationUs/2), fadeOut = min(clip.fadeOutUs,clip.durationUs/2)
                        if fadeIn > 0 { params.setVolumeRamp(fromStartVolume:0,toEndVolume:volume,timeRange:CMTimeRange(start:start,duration:mediaTime(fadeIn))) }
                        if fadeOut > 0 { params.setVolumeRamp(fromStartVolume:volume,toEndVolume:0,timeRange:CMTimeRange(start:mediaTime(clip.endUs-fadeOut),duration:mediaTime(fadeOut))) }
                        audioParams.append(params)
                    }
                }
            }
        }
        guard let fillerURL = Bundle.main.url(forResource:"preview_filler",withExtension:"mp4") else {throw MediaError.export}
        let filler = AVURLAsset(url:fillerURL)
        guard let source = try await filler.loadTracks(withMediaType:.video).first,
              let clock = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else {throw MediaError.export}
        let fillerDuration = try await filler.load(.duration)
        try clock.insertTimeRange(CMTimeRange(start:.zero,duration:fillerDuration),of:source,at:.zero)
        clock.scaleTimeRange(CMTimeRange(start:.zero,duration:fillerDuration),toDuration:mediaTime(project.durationUs))
        sources["__clock"] = clock.trackID
        let video = AVMutableVideoComposition(); video.customVideoCompositorClass = FrameCompositor.self
        let size = previewState == nil ? project.canvas.size:CanvasSettings(aspect:project.canvas.aspect,tier:project.canvas.tier.rawValue>1920 ? .fhd:project.canvas.tier).size
        video.renderSize = CGSize(width:size.width,height:size.height)
        video.frameDuration = CMTime(value:1,timescale:Int32(project.canvas.fps))
        video.instructions = [FrameInstruction(project:project,sources:sources,orientations:orientations,previewState:previewState,renderSize:video.renderSize)]
        let audio = AVMutableAudioMix(); audio.inputParameters = audioParams
        return BuiltComposition(asset:composition,video:video,audio:audio)
    }
}
final class FrameCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String:Any]? = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String:Any] = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
    private let queue = DispatchQueue(label:"com.framenova.compositor")
    private let renderer = FrameRenderer()
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            autoreleasepool {
                do {
                    guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
                          let output = request.renderContext.newPixelBuffer() else { throw MediaError.export }
                    let time = Int64(request.compositionTime.seconds*1_000_000)
                    let image = try self.renderer.render(instruction,at:time) { id in request.sourceFrame(byTrackID:id).map { CIImage(cvPixelBuffer:$0) } }
                    self.renderer.context.render(image,to:output,bounds:CGRect(origin:.zero,size:request.renderContext.size),colorSpace:CGColorSpaceCreateDeviceRGB())
                    request.finish(withComposedVideoFrame:output)
                } catch { request.finish(with:error) }
            }
        }
    }
    func cancelAllPendingVideoCompositionRequests() { queue.sync {} }
}
