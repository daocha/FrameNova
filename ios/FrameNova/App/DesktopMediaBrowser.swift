import SwiftUI
import AVFoundation
import ImageIO

struct DesktopMediaBrowser: View {
    @ObservedObject var model: EditorModel
    var onImport: () -> Void
    @ViewState<String> private var query = ""
    @ViewState<String> private var filter = "All"
    @ViewState<String?> private var selectedID: String?
    @ViewState<Bool> private var dropping = false

    private var media: [MediaAsset] {
        model.project.assets.filter { asset in
            (query.isEmpty || asset.name.localizedCaseInsensitiveContains(query)) &&
            (filter == "All" || filter == "Video" && asset.type == .video || filter == "Photos" && asset.type == .image || filter == "Audio" && asset.type == .audio)
        }
    }
    private var selection: MediaAsset? { model.project.asset(selectedID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Media").font(.headline)
                Text("\(model.project.assets.count)").font(.caption).foregroundStyle(Palette.dim)
                Spacer()
                Button(action: onImport) { Image(systemName: "plus") }.help("Import media (⌘I)").disabled(model.busy)
            }.padding(12)
            TextField("Search media", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 10)
            Picker("Show", selection: $filter) { ForEach(["All", "Video", "Photos", "Audio"], id: \.self) { Text(loc($0)).tag($0) } }
                .pickerStyle(.menu).padding(.horizontal, 10).padding(.vertical, 8)
            if let status = model.importStatus {Text(status).font(.caption2).foregroundStyle(Palette.dim).textSelection(.enabled).padding(.horizontal,10).padding(.bottom,8)}
            Divider()
            ScrollView {
                if media.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 32)).foregroundStyle(Palette.dim)
                        Text(query.isEmpty && filter == "All" ? loc("Drop media files here") : loc("No matching media")).font(.callout)
                        if query.isEmpty && filter == "All" {
                            Text("Import once, then drag onto the timeline or double-click to add at the playhead.")
                                .font(.caption).foregroundStyle(Palette.dim).multilineTextAlignment(.center)
                            Button("Import media…", action: onImport).buttonStyle(.bordered).disabled(model.busy)
                        }
                    }.padding(20).frame(maxWidth: .infinity).padding(.top, 24)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 220), spacing: 8)], spacing: 10) {
                    ForEach(media) { asset in
                        mediaCard(asset)
                    }
                }.padding(10)
            }
            .onChange(of:model.project.assets.map(\.id)) {old,new in
                if let added = new.first(where:{!old.contains($0)}) {query = "";filter = "All";selectedID = added}
            }
            Divider()
            if let asset = selection {
                VStack(alignment: .leading, spacing: 8) {
                    Text(asset.name).font(.caption.bold()).lineLimit(2)
                    Text(asset.type == .audio ? formatTime(asset.durationUs) : "\(asset.width) × \(asset.height) · \(asset.type == .image ? loc("Photo") : formatTime(asset.durationUs))")
                        .font(.caption2).foregroundStyle(Palette.dim)
                    HStack {
                        Button("Add to timeline") { model.insert(asset) }.buttonStyle(.borderedProminent)
                        Menu {
                            Button("Add as layer") { model.insert(asset, kind: .overlay) }.disabled(asset.type == .audio)
                            Button("Add audio") { model.insert(asset, kind: .audio) }.disabled(!asset.hasAudio)
                        } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton)
                    }.controlSize(.small)
                }.padding(12)
            } else {
                Text("Drag media onto a track to place it.").font(.caption2).foregroundStyle(Palette.dim).padding(12)
            }
        }
        .background(Palette.surface)
        .overlay { if dropping { RoundedRectangle(cornerRadius: 6).stroke(Palette.teal, lineWidth: 2).padding(3).allowsHitTesting(false) } }
        .onDrop(of: WorkspaceDrop.types, isTargeted: $dropping) { providers in WorkspaceDrop.accept(providers, model: model, target: .library) }
        .accessibilityIdentifier("desktop.mediaBrowser")
    }

    private func mediaCard(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MediaThumbnail(asset: asset).aspectRatio(1.6, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: asset.type == .audio ? "waveform" : asset.type == .image ? "photo" : "film")
                        .font(.system(size: 9)).padding(4).background(.black.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 3)).padding(3)
                }
            Text(asset.name).font(.system(size: 10)).lineLimit(2).padding(.horizontal, 5).padding(.bottom, 5)
        }
        .background(selectedID == asset.id ? Palette.accent.opacity(0.25) : Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedID == asset.id ? Palette.accent : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selectedID = asset.id; model.insert(asset) }
        .simultaneousGesture(TapGesture().onEnded { selectedID = asset.id })
        .onDrag { selectedID = asset.id; return NSItemProvider(object: (WorkspaceDrop.assetPrefix + asset.id) as NSString) }
        .contextMenu {
            Button("Add to timeline") { model.insert(asset) }
            if asset.type == .image {Button("Use as cover") {model.change {if $0.coverAssetID != asset.id {$0.coverFraming = nil};$0.coverAssetID = asset.id}}}
            Button("Add as layer") { model.insert(asset, kind: .overlay) }.disabled(asset.type == .audio)
            Button("Add audio") { model.insert(asset, kind: .audio) }.disabled(!asset.hasAudio)
        }
        .help(localized("\(asset.name) — double-click to add, or drag onto a track"))
    }
}

struct MediaThumbnail: View {
    let asset: MediaAsset
    @ViewState<UIImage?> private var image: UIImage?
    var body: some View {
        GeometryReader {geometry in
            ZStack {
                Palette.surface2
                if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height)}
                else {Image(systemName:asset.type == .audio ? "waveform":"film").foregroundStyle(Palette.dim).font(.title2)}
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.task(id:MediaThumbnailStore.sourceKey(asset)) {image = await MediaThumbnailStore.shared.image(asset,at:0,size:.cover)}
    }
}
