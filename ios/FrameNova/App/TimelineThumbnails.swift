import UIKit
import Combine
import SwiftUI

@MainActor final class TimelineThumbnails:ObservableObject {
    static let shared = TimelineThumbnails()
    @Published private(set) var revision = 0
    private let memory = NSCache<NSString,UIImage>()
    private let store:MediaThumbnailStore
    private var pending:Set<String> = []
    private var prepared:Set<String> = []
    private var queue:[(MediaAsset,Int64,String)] = []
    private var active = 0
    private var failed:Set<String> = []
    private var sourceKeys:[String:(MediaAsset,String)] = [:]
    init(store:MediaThumbnailStore = .shared) {self.store = store;memory.totalCostLimit = 32*1024*1024;memory.countLimit = 500}
    private func sourceKey(_ asset:MediaAsset)->String {
        if let cached = sourceKeys[asset.id],cached.0 == asset {return cached.1}
        let key = MediaThumbnailStore.sourceKey(asset)
        sourceKeys[asset.id] = (asset,key)
        return key
    }
    private func request(_ asset:MediaAsset,time:Int64) {
        let key = sourceKey(asset)+"-\(time)"
        guard !pending.contains(key),!failed.contains(key),memory.object(forKey:key as NSString) == nil else {return}
        pending.insert(key);queue.append((asset,time,key));pump()
    }
    func image(_ asset:MediaAsset,at time:Int64)->UIImage? {
        let plan = FilmstripPlan(duration:asset.durationUs)
        let time = asset.type == .image ? 0:plan.time(at:plan.index(at:time))
        let prefix = sourceKey(asset)+"-",key = prefix+"\(time)"
        if let image = memory.object(forKey:key as NSString) {return image}
        request(asset,time:time)
        if asset.type == .video {
            let nearest = plan.index(at:time)
            for delta in 1..<plan.count {
                for slot in [nearest-delta,nearest+delta] where slot>=0 && slot<plan.count {
                    if let image = memory.object(forKey:(prefix+"\(plan.time(at:slot))") as NSString) {return image}
                }
            }
        }
        return nil
    }
    func prepare(_ assets:[MediaAsset]) {
        let videos = assets.filter {$0.type == .video && $0.durationUs>0 && prepared.insert(MediaThumbnailStore.sourceKey($0)).inserted}.map {asset in (asset,FilmstripPlan(duration:asset.durationUs),FilmstripPlan(duration:asset.durationUs).order)}
        // Interleave sources so the first frames of every clip appear before one long clip fills its strip.
        for offset in 0..<120 {for (asset,plan,order) in videos {
            if offset<order.count {request(asset,time:plan.time(at:order[offset]))}
        }}
    }
    private func pump() {
        while active<2 && !queue.isEmpty {
            let (asset,time,key) = queue.removeFirst();active += 1
            Task {
                let image = await store.image(asset,at:time,size:.timeline)
                if let image {memory.setObject(image,forKey:key as NSString,cost:Int(image.size.width*image.size.height*4))}
                else {failed.insert(key)}
                pending.remove(key);active -= 1;revision += 1;pump()
            }
        }
    }
}

struct TimelineMediaStrip:View {
    let clip:Clip
    let asset:MediaAsset
    let pointsPerSecond:Double
    var visibleStart:Double = 0
    var visibleEnd:Double = .greatestFiniteMagnitude
    var locked = false
    @ObservedObject private var waveforms = AudioWaveforms.shared
    @ObservedObject private var thumbnails = TimelineThumbnails.shared
    var body:some View {
        let _ = waveforms.revision
        let _ = thumbnails.revision
        GeometryReader {geometry in
            let start = min(geometry.size.width,max(0,visibleStart)),end = max(start,min(geometry.size.width,visibleEnd))
            Canvas {context,size in
                guard end>start else {return}
                if locked {context.addFilter(.saturation(0))}
                if clip.audioOnly || asset.type == .audio {
                    let peaks = waveforms.peaks(asset,ready:{}) ?? []
                    var path = Path()
                    for position in stride(from:floor(start/3)*3,to:end,by:3.0) {
                        let time = clip.sourceTime(at:clip.startUs+Int64(position/max(0.1,pointsPerSecond)*1_000_000))
                        let index = Int(time/AudioWaveforms.stepUs)
                        let value = index>=0 && index<peaks.count ? Double(peaks[index]):0
                        let amplitude = clamp(value*min(clip.volume,1.5),0.02,1)*size.height*0.42
                        path.move(to:CGPoint(x:position-start,y:size.height/2-amplitude));path.addLine(to:CGPoint(x:position-start,y:size.height/2+amplitude))
                    }
                    context.stroke(path,with:.color(Palette.teal),lineWidth:2)
                } else if clip.text == nil {
                    let width = max(16,size.height*clamp(Double(asset.width)/Double(max(1,asset.height)),0.5,2))
                    for index in Int(floor(start/width))..<Int(ceil(end/width)) {
                        let time = clip.sourceTime(at:clip.startUs+Int64(Double(index)*width/max(0.1,pointsPerSecond)*1_000_000))
                        guard let image = thumbnails.image(asset,at:time) else {continue}
                        let tile = CGRect(x:Double(index)*width-start,y:0,width:width,height:size.height)
                        let factor = max(tile.width/image.size.width,tile.height/image.size.height)
                        let rect = CGRect(x:tile.midX-image.size.width*factor/2,y:tile.midY-image.size.height*factor/2,width:image.size.width*factor,height:image.size.height*factor)
                        var drawing = context
                        drawing.clip(to:Path(tile))
                        drawing.draw(Image(uiImage:image),in:rect)
                    }
                }
            }.frame(width:max(0,end-start),height:geometry.size.height).clipped().offset(x:start)
        }.clipped().accessibilityIdentifier("timeline.mediaStrip")
    }
}
