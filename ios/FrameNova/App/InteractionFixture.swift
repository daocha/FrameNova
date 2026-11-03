#if DEBUG
import SwiftUI

@MainActor final class InteractionFixture:ObservableObject {
    let project:Project
    let store:ProjectStore
    private let imageURL:URL
    private let directory:URL
    init() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(newID(),isDirectory:true)
        store = ProjectStore(directory:directory)
        try? FileManager.default.createDirectory(at:ProjectStore.root.appendingPathComponent("Media"),withIntermediateDirectories:true)
        let path = newID()+".png";imageURL = ProjectStore.mediaURL(path)
        let image = UIGraphicsImageRenderer(size:CGSize(width:320,height:180)).image {context in
            UIColor(argb:0xFF6554C0).setFill();context.fill(CGRect(x:0,y:0,width:320,height:180))
        }
        try? image.pngData()?.write(to:imageURL)
        let asset = MediaAsset(path:path,type:.image,name:"Timeline fixture",durationUs:10_000_000,width:320,height:180)
        var p = Project(name:"Interaction regression");p.canvas.tier = .hd;p.assets = [asset]
        p.tracks[0].clips = [Clip(id:"fixture-main",assetID:asset.id,srcOutUs:10_000_000)]
        project = p
    }
    deinit {try? FileManager.default.removeItem(at:imageURL);try? FileManager.default.removeItem(at:directory)}
}
struct InteractionFixtureView:View {
    @StateObject private var fixture = InteractionFixture()
    var body:some View {NavigationStack {EditorView(project:fixture.project,store:fixture.store)}}
}
#endif
