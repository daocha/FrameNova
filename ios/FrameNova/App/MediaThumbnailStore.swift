import AVFoundation
import CryptoKit
import ImageIO
import UIKit

actor MediaThumbnailStore {
    enum Size:String {case timeline,cover}
    typealias Decoder = @Sendable (MediaAsset,Int64,Size) async -> UIImage?
    static let shared = MediaThumbnailStore()
    static let directory = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("FrameNova/MediaThumbnails/v1",isDirectory:true)
    private let directory:URL
    private let decoder:Decoder
    private let memory = NSCache<NSString,UIImage>()
    private var pending:[String:Task<UIImage?,Never>] = [:]
    init(directory:URL = MediaThumbnailStore.directory,decoder:@escaping Decoder = {asset,time,size in await MediaThumbnailStore.decode(asset,time,size)}) {
        self.directory = directory;self.decoder = decoder
        memory.totalCostLimit = 48*1024*1024;memory.countLimit = 400
    }
    nonisolated static func sourceKey(_ asset:MediaAsset)->String {
        digest("\(asset.path)|\(asset.type.rawValue)|\(asset.durationUs)|\(asset.width)x\(asset.height)")
    }
    nonisolated static func digest(_ value:String)->String {SHA256.hash(data:Data(value.utf8)).map {String(format:"%02x",$0)}.joined()}
    func image(_ asset:MediaAsset,at time:Int64,size:Size) async ->UIImage? {
        guard asset.type != .audio else {return nil}
        let time = asset.type == .image ? 0:clamp(time,0,max(0,asset.durationUs-1))
        let key = Self.sourceKey(asset)+"-\(size.rawValue)-\(time)"
        if let value = memory.object(forKey:key as NSString) {return value}
        if let job = pending[key] {return await job.value}
        let file = directory.appendingPathComponent(key+".jpg"),decoder = decoder
        let job = Task.detached(priority:.utility) {()->UIImage? in
            if let image = UIImage(contentsOfFile:file.path) {return image}
            guard let image = await decoder(asset,time,size) else {return nil}
            if let data = image.jpegData(compressionQuality:size == .cover ? 0.85:0.82) {
                try? FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
                try? data.write(to:file,options:.atomic)
            }
            return image
        }
        pending[key] = job
        let image = await job.value;pending.removeValue(forKey:key)
        if let image {memory.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.size.height*image.scale*image.scale*4))}
        return image
    }
    nonisolated private static func decode(_ asset:MediaAsset,_ time:Int64,_ size:Size) async ->UIImage? {
        let url = ProjectStore.mediaURL(asset.path),maxSize = size == .cover ? CGSize(width:720,height:360):CGSize(width:180,height:128)
        if asset.type == .image {
            let scale = min(maxSize.width/Double(max(1,asset.width)),maxSize.height/Double(max(1,asset.height)))
            let longest = asset.width>0 && asset.height>0 ? ceil(Double(max(asset.width,asset.height))*min(1,scale)):max(maxSize.width,maxSize.height)
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),let frame = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:longest,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else {return nil}
            return UIImage(cgImage:frame)
        }
        let generator = AVAssetImageGenerator(asset:AVURLAsset(url:url))
        generator.appliesPreferredTrackTransform = true;generator.maximumSize = maxSize
        generator.requestedTimeToleranceBefore = .positiveInfinity;generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let frame = try? await generator.image(at:mediaTime(time)) else {return nil}
        return UIImage(cgImage:frame.image)
    }
}
