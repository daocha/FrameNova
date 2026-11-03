import AVFoundation
import UIKit
import ImageIO

@MainActor final class TimelineThumbnails {
    static let shared = TimelineThumbnails()
    private let cache = NSCache<NSString,UIImage>()
    private var pending: [String:[() -> Void]] = [:]
    private var queue: [(MediaAsset,Int64,String)] = []
    private var active = 0
    private var failed:Set<String> = []
    init() {cache.totalCostLimit = 32*1024*1024;cache.countLimit = 320}
    func image(_ asset:MediaAsset,at time:Int64,ready:@escaping ()->Void) -> UIImage? {
        let bucket = asset.type == .image ? 0 : max(0,time/500_000)*500_000
        let key = asset.id+":"+String(bucket)
        if let image = cache.object(forKey:key as NSString) {return image}
        if failed.contains(key) {return nil}
        if pending[key] != nil {return nil}
        if queue.count>=64 {let old = queue.removeFirst();pending.removeValue(forKey:old.2)}
        pending[key] = [ready];queue.append((asset,bucket,key));pump()
        return nil
    }
    private func pump() {
        while active < 2 && !queue.isEmpty {
            let (asset,time,key) = queue.removeFirst();active += 1
            Task {
                let url = ProjectStore.mediaURL(asset.path)
                var image:UIImage?
                if asset.type == .image {
                    if let source = CGImageSourceCreateWithURL(url as CFURL,nil),
                       let frame = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:180,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) {image = UIImage(cgImage:frame)}
                } else if asset.type == .video {
                    let generator = AVAssetImageGenerator(asset:AVURLAsset(url:url))
                    generator.appliesPreferredTrackTransform = true;generator.maximumSize = CGSize(width:180,height:120)
                    generator.requestedTimeToleranceBefore = CMTime(seconds:0.25,preferredTimescale:600)
                    generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
                    if let frame = try? await generator.image(at:mediaTime(min(time,max(0,asset.durationUs-1)))) {image = UIImage(cgImage:frame.image)}
                }
                if let image {cache.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.size.height*4))}
                if image == nil {failed.insert(key)}
                let callbacks = pending.removeValue(forKey:key) ?? [];active -= 1
                for callback in callbacks {callback()};pump()
            }
        }
    }
}
