import Testing
import UIKit
import AVFoundation
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
