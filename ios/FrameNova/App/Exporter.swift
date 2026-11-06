import AVFoundation
import Photos
import UIKit

struct ExportSettings {
    var tier: Resolution = .uhd
    var fps = 30
    var hevc = true
    var quality = "High"
}
@MainActor final class Exporter: ObservableObject {
    @Published var running = false
    @Published var progress: Float = 0
    @Published var url: URL?
    @Published var error: String? {didSet {if let error {AppLog.record(error)}}}
    private var job: Task<Void,Never>?
    private var background: UIBackgroundTaskIdentifier = .invalid
    func cancel() { job?.cancel() }
    func start(_ project: Project,settings:ExportSettings) {
        guard !running else { return }
        running = true; progress = 0; error = nil; url = nil
        background = UIApplication.shared.beginBackgroundTask(withName:"FrameNova export") { [weak self] in Task { @MainActor in self?.cancel() } }
        job = Task {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("FrameNova-\(newID()).mp4")
            do {
                var p = project; p.canvas.tier = settings.tier; p.canvas.fps = settings.fps
                let built = try await CompositionFactory.build(p,exportCover:true)
                try await Self.write(built,project:p,settings:settings,to:destination) { [weak self] value in Task { @MainActor in self?.progress = value } }
                self.url = destination; progress = 1
            } catch {
                try? FileManager.default.removeItem(at:destination)
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
            running = false
            if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
        }
    }
    nonisolated private static func write(_ built:BuiltComposition,project:Project,settings:ExportSettings,to url:URL,progress:@escaping (Float)->Void) async throws {
        let task = Task.detached(priority:.userInitiated) {
            let reader = try AVAssetReader(asset:built.asset), writer = try AVAssetWriter(outputURL:url,fileType:.mp4)
            let video = AVAssetReaderVideoCompositionOutput(videoTracks:built.asset.tracks(withMediaType:.video),videoSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            video.videoComposition = built.video; video.alwaysCopiesSampleData = false; reader.add(video)
            let size = project.canvas.size
            let factor = settings.quality == "High" ? 0.16 : settings.quality == "Medium" ? 0.1 : 0.06
            let videoInput = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:settings.hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,AVVideoWidthKey:size.width,AVVideoHeightKey:size.height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:Int(Double(size.width*size.height*project.canvas.fps)*factor),AVVideoExpectedSourceFrameRateKey:project.canvas.fps]])
            guard writer.canAdd(videoInput) else { throw MediaError.export }; writer.add(videoInput)
            var audio: AVAssetReaderAudioMixOutput?, audioInput: AVAssetWriterInput?
            let tracks = built.asset.tracks(withMediaType:.audio)
            if !tracks.isEmpty {
                let output = AVAssetReaderAudioMixOutput(audioTracks:tracks,audioSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsNonInterleaved:false])
                output.audioMix = built.audio; output.audioTimePitchAlgorithm = .spectral; reader.add(output); audio = output
                let input = AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVEncoderBitRateKey:192000])
                guard writer.canAdd(input) else { throw MediaError.export }; writer.add(input); audioInput = input
            }
            guard writer.startWriting(),reader.startReading() else { throw writer.error ?? reader.error ?? MediaError.export }
            writer.startSession(atSourceTime:.zero)
            do {
                var videoDone = false, audioDone = audio == nil
                while !videoDone || !audioDone {
                    try Task.checkCancellation()
                    var advanced = false
                    if !videoDone && videoInput.isReadyForMoreMediaData {
                        if let sample = video.copyNextSampleBuffer() {
                            guard videoInput.append(sample) else { throw writer.error ?? MediaError.export }
                            progress(Float(CMSampleBufferGetPresentationTimeStamp(sample).seconds/(Double(project.durationUs)/1_000_000)))
                        } else { videoInput.markAsFinished(); videoDone = true }; advanced = true
                    }
                    if !audioDone, let audio, let input = audioInput, input.isReadyForMoreMediaData {
                        if let sample = audio.copyNextSampleBuffer() { guard input.append(sample) else { throw writer.error ?? MediaError.export } }
                        else { input.markAsFinished(); audioDone = true }; advanced = true
                    }
                    if reader.status == .failed { throw reader.error ?? MediaError.export }
                    if writer.status == .failed { throw writer.error ?? MediaError.export }
                    if !advanced { try await Task.sleep(nanoseconds:2_000_000) }
                }
                await writer.finishWriting()
                guard writer.status == .completed else { throw writer.error ?? MediaError.export }
            } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
        }
        try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
    }
    func saveToPhotos() async {
        guard let url else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for:.addOnly)
        guard status == .authorized || status == .limited else { error = String(localized: "Allow saving videos in Settings."); return }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL:url) } }
        catch { self.error = error.localizedDescription }
    }
}
