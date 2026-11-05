import SwiftUI
import UniformTypeIdentifiers

struct CoverPanel: View {
    @ObservedObject var model: EditorModel
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var photos = false
    private var images: [MediaAsset] {model.project.assets.filter {$0.type == .image}}
    private func choose(_ assets: [MediaAsset]) {
        guard let image = assets.first(where:{$0.type == .image}) else {return}
        model.change {$0.addLibraryAssets([image]);$0.coverAssetID = image.id}
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Choose a project thumbnail. You can also add it as a three-second opening clip, then trim it in the timeline.")
                .font(.caption).foregroundStyle(Palette.dim)
            if let asset = model.project.asset(model.project.coverAssetID) {
                MediaThumbnail(asset:asset).aspectRatio(1.6,contentMode:.fit)
                Text(asset.name).font(.caption)
            }
            Menu("Choose from media") {
                ForEach(images) {asset in Button(asset.name) {choose([asset])}}
            }.disabled(images.isEmpty)
            HStack {
                Button("Files…") {files = true}
                Button("Photos…") {photos = true}
            }.buttonStyle(.bordered)
            Button("Use automatic thumbnail") {model.change {$0.coverAssetID = nil}}
                .disabled(model.project.coverAssetID == nil)
            Button("Add cover to start") {
                var id:String?
                model.change {id = $0.prependCover()}
                model.selected = id;model.seek(0)
            }.disabled(!model.project.canPrependCover)
            if model.project.coverAssetID != nil && !model.project.canPrependCover {
                Text("Unlock tracks before adding an opening clip.").font(.caption).foregroundStyle(Palette.dim)
            }
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
