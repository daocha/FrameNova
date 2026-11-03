import Testing
import UIKit
import AVFoundation
import CoreImage
@testable import FrameNova

@Suite(.serialized) @MainActor struct RenderingTests {
    @Test func backgroundAndTextProduceFramesWithoutVideoSources() throws {
        var p = Project(name:"Render test"); p.canvas.tier = .hd; p.canvas.background = 0xFFFF0000
        p.place(Clip(srcOutUs:1_000_000,text:TextStyle(text:"FrameNova")),kind:.text)
        let instruction = FrameInstruction(project:p,sources:[:],orientations:[:])
        let renderer = FrameRenderer(), image = try renderer.render(instruction,at:0) {_ in nil}
        var pixel = [UInt8](repeating:0,count:4)
        renderer.context.render(image,toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:0,y:0,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        #expect(pixel[0] > 240); #expect(pixel[1] < 10); #expect(pixel[2] < 10)
        #expect(image.extent.width == 1280)
    }
    @Test func stillOnlyCompositionExportsAtRequestedSize() async throws {
        let folder = ProjectStore.root.appendingPathComponent("Media")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let path = newID()+".png", url = ProjectStore.mediaURL(path)
        let image = UIGraphicsImageRenderer(size:CGSize(width:100,height:100)).image {ctx in UIColor.green.setFill(); ctx.fill(CGRect(x:0,y:0,width:100,height:100))}
        try #require(image.pngData()).write(to:url)
        defer {try? FileManager.default.removeItem(at:url)}
        var p = Project(name:"Export test"); p.canvas.tier = .hd; p.canvas.fps = 24
        p.add([MediaAsset(path:path,type:.image,name:"Still",durationUs:3_000_000,width:100,height:100)],kind:.main,at:0)
        p.update(p.tracks[p.mainIndex].clips[0].id) {$0.srcOutUs = 500_000}
        let exporter = Exporter(); exporter.start(p,settings:ExportSettings(tier:.hd,fps:24,hevc:false))
        let deadline = Date().addingTimeInterval(60)
        while exporter.running && Date() < deadline {try await Task.sleep(nanoseconds:50_000_000)}
        if exporter.running {exporter.cancel()}
        #expect(exporter.error == nil)
        let output = try #require(exporter.url); defer {try? FileManager.default.removeItem(at:output)}
        let asset = AVURLAsset(url:output), duration = try await asset.load(.duration)
        #expect(abs(duration.seconds-0.5)<0.1)
        let track = try #require(try await asset.loadTracks(withMediaType:.video).first)
        let size = try await track.load(.naturalSize)
        #expect(size == CGSize(width:1280,height:720))
    }
}

@Suite @MainActor struct PreviewParityTests {
    @Test func livePreviewStateDoesNotMutateExportSnapshot() throws {
        var project = Project(name:"Snapshot");project.tracks[0].clips = [Clip(text:TextStyle())]
        let live = PreviewProjectState(project)
        let preview = FrameInstruction(project:project,sources:[:],orientations:[:],previewState:live,renderSize:CGSize(width:320,height:180))
        let export = FrameInstruction(project:project,sources:[:],orientations:[:])
        project.canvas.background = 0xFFFF0000;live.update(project)
        #expect(preview.project.canvas.background == 0xFFFF0000)
        #expect(export.project.canvas.background == 0xFF000000)
        let image = try FrameRenderer().render(preview,at:0) {_ in nil}
        #expect(image.extent.size == CGSize(width:320,height:180))
    }
    @Test func dipColorsStayBelowOverlayTracks() throws {
        let renderer = FrameRenderer()
        var project = Project(name:"Dip");project.canvas.tier = .hd
        let a = MediaAsset(id:"a",path:"a.mov",type:.video,name:"A",durationUs:4_000_000)
        let b = MediaAsset(id:"b",path:"b.mov",type:.video,name:"B",durationUs:4_000_000)
        let overlay = MediaAsset(id:"overlay",path:"o.mov",type:.video,name:"Overlay",durationUs:4_000_000)
        project.assets = [a,b,overlay]
        project.tracks[0].clips = [Clip(id:"a",assetID:a.id,srcOutUs:4_000_000),Clip(id:"b",assetID:b.id,startUs:3_000_000,srcOutUs:4_000_000,transitionIn:Transition(type:.dipWhite,durationUs:1_000_000))]
        func frame(_ id:Int32)->CIImage? {CIImage(color:id == 1 ? .red:id == 2 ? .blue:.green).cropped(to:CGRect(x:0,y:0,width:160,height:90))}
        let first = FrameInstruction(project:project,sources:["a":1,"b":2],orientations:[:])
        let white = try renderer.render(first,at:3_500_000,frame:frame)
        var pixel = [UInt8](repeating:0,count:4)
        renderer.context.render(white,toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:640,y:360,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        #expect(pixel[0]>245 && pixel[1]>245 && pixel[2]>245)
        project.tracks.insert(Track(kind:.overlay,clips:[Clip(id:"overlay",assetID:overlay.id,startUs:3_000_000,srcOutUs:1_000_000)]),at:0)
        let second = FrameInstruction(project:project,sources:["a":1,"b":2,"overlay":3],orientations:[:])
        let green = try renderer.render(second,at:3_500_000,frame:frame)
        renderer.context.render(green,toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:640,y:360,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        #expect(pixel[0]<10 && pixel[1]>245 && pixel[2]<10)
    }
}

@Suite @MainActor struct TimelineMediaTests {
    @Test func videoFilmstripLoadsARealFrame() async throws {
        let source = try #require(Bundle.main.url(forResource:"preview_filler",withExtension:"mp4"))
        try FileManager.default.createDirectory(at:ProjectStore.root.appendingPathComponent("Media"),withIntermediateDirectories:true)
        let path = newID()+".mp4",url = ProjectStore.mediaURL(path)
        try FileManager.default.copyItem(at:source,to:url)
        defer {try? FileManager.default.removeItem(at:url)}
        let asset = MediaAsset(path:path,type:.video,name:"Video thumbnail",durationUs:10_000_000,width:160,height:90)
        let cache = TimelineThumbnails.shared
        var image = cache.image(asset,at:1_000_000)
        let deadline = Date().addingTimeInterval(10)
        while image == nil && Date()<deadline {
            try await Task.sleep(nanoseconds:20_000_000)
            image = cache.image(asset,at:1_000_000)
        }
        let frame = try #require(image)
        #expect(frame.size.width>0 && frame.size.width<=180)
        #expect(frame.size.height>0 && frame.size.height<=120)
    }
}

@Suite @MainActor struct WaveformParityTests {
    @Test func waveformDecodesRealAudioRatherThanPlaceholderBars() async throws {
        try FileManager.default.createDirectory(at:ProjectStore.root.appendingPathComponent("Media"),withIntermediateDirectories:true)
        let path = newID()+".wav",url = ProjectStore.mediaURL(path)
        var data = Data()
        func tag(_ text:String) {data.append(contentsOf:text.utf8)}
        func number<T:FixedWidthInteger>(_ value:T) {var value = value.littleEndian;withUnsafeBytes(of:&value) {data.append(contentsOf:$0)}}
        let sampleRate = 16_000,count = sampleRate
        tag("RIFF");number(UInt32(36+count*2));tag("WAVEfmt ");number(UInt32(16));number(UInt16(1));number(UInt16(1));number(UInt32(sampleRate));number(UInt32(sampleRate*2));number(UInt16(2));number(UInt16(16));tag("data");number(UInt32(count*2))
        for index in 0..<count {number(Int16(sin(Double(index)*2 * .pi*440/Double(sampleRate))*16_000))}
        try data.write(to:url);defer {try? FileManager.default.removeItem(at:url)}
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID())
        defer {try? FileManager.default.removeItem(at:folder)}
        let asset = MediaAsset(path:path,type:.audio,name:"Waveform",durationUs:1_000_000,hasAudio:true),cache = AudioWaveforms(directory:folder)
        let result:[Float]? = await withCheckedContinuation {continuation in
            if let value = cache.peaks(asset,ready:{continuation.resume(returning:cache.peaks(asset,ready:{}))}) {continuation.resume(returning:value)}
        }
        let peaks = try #require(result)
        #expect(peaks.count>=20)
        #expect((peaks.max() ?? 0) > 0.4 && (peaks.max() ?? 1) < 0.6)
        try FileManager.default.removeItem(at:url)
        let reopened = AudioWaveforms(directory:folder)
        let restored:[Float]? = await withCheckedContinuation {continuation in
            if let value = reopened.peaks(asset,ready:{continuation.resume(returning:reopened.peaks(asset,ready:{}))}) {continuation.resume(returning:value)}
        }
        #expect(restored == peaks)
    }
}

private actor DecodeCalls {
    private(set) var count = 0
    func increment() {count += 1}
}

@Suite(.serialized) @MainActor struct PersistentThumbnailTests {
    private func image()->UIImage {UIGraphicsImageRenderer(size:CGSize(width:32,height:18)).image {context in UIColor.red.setFill();context.fill(CGRect(x:0,y:0,width:32,height:18))}}
    @Test func fileImportKeepsSuccessfulFilesWhenAnotherFileFails() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),store = ProjectStore(directory:folder)
        let source = folder.appendingPathComponent("Selected image.png")
        try #require(image().pngData()).write(to:source)
        let model = EditorModel(project:Project(name:"File import"),store:store)
        defer {
            model.close()
            for asset in model.project.assets {try? FileManager.default.removeItem(at:ProjectStore.mediaURL(asset.path))}
            try? FileManager.default.removeItem(at:folder)
        }
        model.ingest([source,folder.appendingPathComponent("missing.wav")],kind:.main,libraryOnly:true)
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date()<deadline {try await Task.sleep(nanoseconds:20_000_000)}
        #expect(!model.busy)
        let asset = try #require(model.project.assets.first)
        #expect(asset.type == .image);#expect(model.project.assets.count == 1)
        #expect(model.project.durationUs == 0)
        #expect(model.error?.contains("missing.wav") == true)
        #expect(FileManager.default.fileExists(atPath:ProjectStore.mediaURL(asset.path).path))
        #expect(FileManager.default.fileExists(atPath:source.path))
        #expect(ProjectStore(directory:folder).projects.first?.assets.count == 1)
    }
    @Test func concurrentRequestsDecodeOnceAndReopeningReadsDisk() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),calls = DecodeCalls(),frame = image()
        defer {try? FileManager.default.removeItem(at:folder)}
        let asset = MediaAsset(path:"source.mov",type:.video,name:"Cache test",durationUs:10_000_000)
        let cache = MediaThumbnailStore(directory:folder,decoder:{_,_,_ in await calls.increment();try? await Task.sleep(nanoseconds:20_000_000);return frame})
        async let first = cache.image(asset,at:1_000_000,size:.timeline)
        async let second = cache.image(asset,at:1_000_000,size:.timeline)
        let images = await (first,second)
        #expect(images.0 != nil && images.1 != nil);#expect(await calls.count == 1)
        let reopened = MediaThumbnailStore(directory:folder,decoder:{_,_,_ in await calls.increment();return nil})
        let restored = await reopened.image(asset,at:1_000_000,size:.timeline)
        #expect(restored?.cgImage?.width == frame.cgImage?.width)
        #expect(restored?.cgImage?.height == frame.cgImage?.height)
        #expect(await calls.count == 1)
    }
    @Test func corruptFilesRecoverAndChangedSourcesInvalidateCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),calls = DecodeCalls(),frame = image()
        defer {try? FileManager.default.removeItem(at:folder)}
        var asset = MediaAsset(path:"first.mov",type:.video,name:"Cache recovery",durationUs:10_000_000)
        let original = MediaThumbnailStore(directory:folder,decoder:{_,_,_ in return frame})
        #expect(await original.image(asset,at:0,size:.cover) != nil)
        let file = try #require(try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).first)
        try Data([0,1,2]).write(to:file)
        let reopened = MediaThumbnailStore(directory:folder,decoder:{_,_,_ in await calls.increment();return frame})
        #expect(await reopened.image(asset,at:0,size:.cover) != nil)
        asset.path = "replacement.mov"
        #expect(await reopened.image(asset,at:0,size:.cover) != nil)
        #expect(await calls.count == 2)
    }
    @Test func projectCoverSurvivesRelaunchWithoutSourceAndIsDeletedWithProject() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),path = newID()+".png",source = ProjectStore.mediaURL(path)
        try FileManager.default.createDirectory(at:source.deletingLastPathComponent(),withIntermediateDirectories:true)
        try #require(image().pngData()).write(to:source)
        defer {try? FileManager.default.removeItem(at:folder);try? FileManager.default.removeItem(at:source)}
        let store = ProjectStore(directory:folder)
        let asset = MediaAsset(path:path,type:.image,name:"Persisted cover",durationUs:3_000_000,width:32,height:18)
        var project = Project(name:"Cover");project.add([asset],kind:.main,at:0)
        try store.save(project)
        #expect(await store.cover(project) != nil)
        let file = store.coverURL(project)
        #expect(FileManager.default.fileExists(atPath:file.path))
        try FileManager.default.removeItem(at:source)
        let reopened = ProjectStore(directory:folder)
        #expect(await reopened.cover(project) != nil)
        try reopened.delete(project)
        #expect(!FileManager.default.fileExists(atPath:file.path))
    }
    @Test func coverUsesTrimmedMainClipInsteadOfFirstImportedAsset() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID()),store = ProjectStore(directory:folder)
        defer {try? FileManager.default.removeItem(at:folder)}
        let unused = MediaAsset(path:"unused.mov",type:.video,name:"Unused",durationUs:10_000_000)
        let used = MediaAsset(path:"used.mov",type:.video,name:"Used",durationUs:10_000_000)
        var project = Project(name:"Cover source");project.assets = [unused,used]
        project.tracks[0].clips = [Clip(assetID:used.id,srcInUs:3_000_000,srcOutUs:8_000_000)]
        #expect(store.coverSource(project)?.asset.id == used.id)
        #expect(store.coverSource(project)?.time == 3_000_000)
        let firstKey = store.coverKey(project)
        project.tracks[0].clips[0].srcInUs = 4_000_000
        #expect(store.coverKey(project) != firstKey)
    }
}
