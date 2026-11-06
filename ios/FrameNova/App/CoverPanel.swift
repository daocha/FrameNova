import SwiftUI
import UniformTypeIdentifiers

struct CoverPanel: View {
    @ObservedObject var model: EditorModel
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var photos = false
    @ViewState<Bool> private var sources = false
    private var images: [MediaAsset] {model.project.assets.filter {$0.type == .image}}
    private func choose(_ assets: [MediaAsset]) {
        guard let image = assets.first(where:{$0.type == .image}) else {return}
        model.change {$0.addLibraryAssets([image]);if $0.coverAssetID != image.id {$0.coverFraming = nil};$0.coverAssetID = image.id}
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Choose a project thumbnail. You can also add it as a three-second opening clip, then trim it in the timeline.")
                .font(.caption).foregroundStyle(Palette.dim)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    Button {sources = true} label: {
                        Image(systemName:"plus").font(.title2).foregroundStyle(Palette.accent)
                            .frame(width:72,height:72).background(Palette.surface2,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain).accessibilityLabel("Choose a photo")
                    ForEach(images) {asset in
                        Button {model.change {if $0.coverAssetID != asset.id {$0.coverFraming = nil};$0.coverAssetID = asset.id}} label: {
                            MediaThumbnail(asset:asset).frame(width:72,height:72).clipShape(RoundedRectangle(cornerRadius:8))
                                .overlay {RoundedRectangle(cornerRadius:8).stroke(Palette.accent,lineWidth:model.project.coverAssetID == asset.id ? 2:0)}
                        }.buttonStyle(.plain).accessibilityLabel(asset.name)
                    }
                }
            }
            if let cover = model.project.asset(model.project.coverAssetID),cover.type == .image {CoverFramer(model:model,asset:cover)}
            if images.isEmpty {Text("No photos in this project yet. Tap + to choose one.").font(.caption).foregroundStyle(Palette.dim)}
            HStack {
                Button("Use automatic thumbnail") {model.change {$0.coverAssetID = nil;$0.coverFraming = nil}}
                    .disabled(model.project.coverAssetID == nil)
                Spacer()
                if model.project.asset(model.project.coverAssetID)?.type == .image {
                    Button("Reset position") {model.change {$0.coverFraming = nil}}.disabled(model.project.coverFraming == nil)
                }
            }
            Button("Add cover to start") {
                var id:String?
                model.change {id = $0.prependCover()}
                model.selected = id;model.seek(0)
            }.disabled(!model.project.canPrependCover)
            if model.project.coverAssetID != nil && !model.project.canPrependCover {
                Text("Unlock tracks before adding an opening clip.").font(.caption).foregroundStyle(Palette.dim)
            }
        }
        .confirmationDialog("Choose media source",isPresented:$sources,titleVisibility:.visible) {
            Button("Files…") {files = true}
            Button("Photos…") {photos = true}
            Button("Cancel",role:.cancel) {}
        }
        .mediaFileImporter(isPresented:$files,allowedContentTypes:[.image],allowsMultipleSelection:false) {result in
            do {
                let urls = try result.get()
                Task {
                    do {var assets:[MediaAsset] = [];for url in urls {assets.append(try await ProjectStore.ingest(url))};choose(assets)}
                    catch {model.error = error.localizedDescription}
                }
            } catch {model.error = error.localizedDescription}
        }
        .sheet(isPresented:$photos) {
            MediaPicker(multiple:false,imagesOnly:true) {assets,error in
                photos = false
                if let error {model.error = error}
                choose(assets)
            }
        }
    }
}

/// The cover photo placed in a frame of the video's shape as the framing says.
struct FramedCover: View {
    let asset: MediaAsset
    let framing: CoverFraming
    var onSize: (CGSize)->Void = {_ in}
    @ViewState<UIImage?> private var image: UIImage?
    var body: some View {
        GeometryReader {geometry in
            ZStack(alignment:.topLeading) {
                Color.black
                if let image {
                    let at = framing.placement(photo:image.size,frame:geometry.size)
                    Image(uiImage:image).resizable().frame(width:at.width,height:at.height).offset(x:at.minX,y:at.minY)
                }
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.task(id:MediaThumbnailStore.sourceKey(asset)) {image = await MediaThumbnailStore.shared.image(asset,at:0,size:.cover);if let image {onSize(image.size)}}
    }
}

/// Shows the cover as it will fill the video frame; drag to move it, pinch or use the slider to zoom.
struct CoverFramer: View {
    @ObservedObject var model: EditorModel
    let asset: MediaAsset
    @ViewState<CoverFraming?> private var start: CoverFraming?
    @ViewState<CGSize> private var photoSize = CGSize(width:1,height:1)
    private var framing: CoverFraming {model.project.framing}
    private func set(_ value: CoverFraming) {
        var value = value
        value.zoom = clamp(value.zoom,1,CoverFraming.maxZoom);value.panX = clamp(value.panX,-1,1);value.panY = clamp(value.panY,-1,1)
        model.change {$0.coverFraming = value == CoverFraming() ? nil:value}
    }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Drag the photo to move it, pinch to zoom.").font(.caption).foregroundStyle(Palette.dim)
            HStack {
                Spacer()
                FramedCover(asset:asset,framing:framing,onSize:{photoSize = $0})
                    .aspectRatio(model.project.canvas.aspect.ratio,contentMode:.fit).frame(height:200)
                    .clipShape(RoundedRectangle(cornerRadius:6)).overlay {RoundedRectangle(cornerRadius:6).stroke(Palette.accent,lineWidth:1)}
                    .contentShape(Rectangle())
                    .gesture(DragGesture().onChanged {drag in
                        model.beginGesture()
                        let base = start ?? framing;start = base
                        let frame = CGSize(width:200*model.project.canvas.aspect.ratio,height:200)
                        let at = base.placement(photo:photoSize,frame:frame)
                        var next = framing
                        if at.width-frame.width > 1 {next.panX = base.panX-drag.translation.width/((at.width-frame.width)/2)}
                        if at.height-frame.height > 1 {next.panY = base.panY-drag.translation.height/((at.height-frame.height)/2)}
                        set(next)
                    }.onEnded {_ in start = nil;model.endGesture()}
                    .simultaneously(with:MagnificationGesture().onChanged {scale in
                        model.beginGesture()
                        let base = start ?? framing;start = base
                        var next = framing;next.zoom = base.zoom*scale
                        set(next)
                    }.onEnded {_ in start = nil;model.endGesture()}))
                    .accessibilityLabel("Cover position. Drag to move, pinch to zoom.")
                Spacer()
            }
            ValueSlider(title:"Zoom",value:Binding(get:{framing.zoom},set:{value in var next = framing;next.zoom = value;set(next)}),range:1...CoverFraming.maxZoom,format:{String(format:"%.1f×",$0)})
        }.padding(.vertical,6)
    }
}
