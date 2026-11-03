import AVFoundation

@MainActor final class AudioWaveforms {
    static let shared = AudioWaveforms()
    private var values:[String:[Float]] = [:]
    private var pending:Set<String> = []
    func peaks(_ asset:MediaAsset,ready:@escaping ()->Void)->[Float]? {
        if let result = values[asset.id] {return result}
        guard pending.insert(asset.id).inserted else {return nil}
        Task {
            let result = await Task.detached(priority:.utility) {await Self.read(asset)}.value
            if values.count>=16,let key = values.keys.first {values.removeValue(forKey:key)}
            values[asset.id] = result;pending.remove(asset.id);ready()
        }
        return nil
    }
    nonisolated private static func read(_ asset:MediaAsset) async -> [Float] {
        do {
            let source = AVURLAsset(url:ProjectStore.mediaURL(asset.path))
            guard let track = try await source.loadTracks(withMediaType:.audio).first else {return []}
            let formats = try await track.load(.formatDescriptions)
            guard let format = formats.first,let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {return []}
            let channels = max(1,Int(stream.pointee.mChannelsPerFrame)),rate = stream.pointee.mSampleRate
            let reader = try AVAssetReader(asset:source)
            let output = AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsNonInterleaved:false])
            output.alwaysCopiesSampleData = false;reader.add(output)
            guard reader.startReading() else {return []}
            var peaks = [Float](repeating:0,count:max(1,Int(asset.durationUs/50_000)+1))
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else {continue}
                let total = CMBlockBufferGetDataLength(block)
                guard total>0,total%MemoryLayout<Float>.size == 0 else {continue}
                var samples = [Float](repeating:0,count:total/MemoryLayout<Float>.size)
                let status = samples.withUnsafeMutableBytes {bytes in CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:total,destination:bytes.baseAddress!)}
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard status == kCMBlockBufferNoErr,start.isFinite,rate>0 else {continue}
                for frame in stride(from:0,to:total/MemoryLayout<Float>.size/channels,by:4) {
                    let index = Int((start+Double(frame)/rate)*20)
                    guard index>=0,index<peaks.count else {continue}
                    for channel in 0..<channels {peaks[index] = max(peaks[index],min(1,abs(samples[frame*channels+channel])))}
                }
            }
            return peaks
        } catch {return []}
    }
}
