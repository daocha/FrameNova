import SwiftUI
import Photos
import PhotosUI

struct LibraryAlbum:Identifiable {
    let collection:PHAssetCollection
    let cover:PHAsset
    let count:Int
    var id:String {collection.localIdentifier}
    var name:String {collection.localizedTitle ?? localized("Album")}
}

@MainActor final class PhotoLibraryModel:NSObject,ObservableObject,PHPhotoLibraryChangeObserver {
    @Published var access = PHPhotoLibrary.authorizationStatus(for:.readWrite)
    @Published var items:[PHAsset] = []
    @Published var albums:[LibraryAlbum] = []
    @Published var loading = false
    @Published var revision = 0
    @Published var progress = 0.0
    @Published var importing = false
    @Published var error:String?
    var filter = "Library",sort = "newest",albumID:String?
    let thumbnails = PHCachingImageManager()
    override init() {super.init();PHPhotoLibrary.shared().register(self)}
    deinit {PHPhotoLibrary.shared().unregisterChangeObserver(self)}
    nonisolated func photoLibraryDidChange(_ change:PHChange) {Task {@MainActor [weak self] in self?.reload()}}
    var allowed:Bool {access == .authorized || access == .limited}
    func request() async {access = await PHPhotoLibrary.requestAuthorization(for:.readWrite);reload()}
    private func options() -> PHFetchOptions {
        let options = PHFetchOptions()
        if filter == "Photos" {options.predicate = NSPredicate(format:"mediaType == %d",PHAssetMediaType.image.rawValue)}
        else if filter == "Videos" {options.predicate = NSPredicate(format:"mediaType == %d",PHAssetMediaType.video.rawValue)}
        else {options.predicate = NSPredicate(format:"mediaType == %d OR mediaType == %d",PHAssetMediaType.image.rawValue,PHAssetMediaType.video.rawValue)}
        options.sortDescriptors = [NSSortDescriptor(key:"creationDate",ascending:sort == "oldest")]
        return options
    }
    func reload() {
        access = PHPhotoLibrary.authorizationStatus(for:.readWrite)
        guard allowed else {items = [];albums = [];return}
        loading = true
        let options = options()
        var groups:[LibraryAlbum] = []
        var seen:Set<String> = []
        for type in [PHAssetCollectionType.album,.smartAlbum] {
            PHAssetCollection.fetchAssetCollections(with:type,subtype:.any,options:nil).enumerateObjects {collection,_,_ in
                guard !seen.contains(collection.localIdentifier) else {return};seen.insert(collection.localIdentifier)
                let assets = PHAsset.fetchAssets(in:collection,options:options)
                if let cover = assets.firstObject {groups.append(LibraryAlbum(collection:collection,cover:cover,count:assets.count))}
            }
        }
        albums = groups.sorted {a,b in
            if sort == "nameAZ" || sort == "nameZA" {return sort == "nameAZ" ? a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending:a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending}
            let left = a.cover.creationDate ?? .distantPast,right = b.cover.creationDate ?? .distantPast
            return sort == "oldest" ? left<right:left>right
        }
        let fetched:PHFetchResult<PHAsset>
        if let id = albumID,let album = groups.first(where:{$0.id == id}) {fetched = PHAsset.fetchAssets(in:album.collection,options:options)}
        else {albumID = nil;fetched = PHAsset.fetchAssets(with:options)}
        var list:[PHAsset] = [];fetched.enumerateObjects {asset,_,_ in list.append(asset)}
        if sort == "nameAZ" || sort == "nameZA" {
            list.sort {a,b in
                let left = PHAssetResource.assetResources(for:a).first?.originalFilename ?? a.localIdentifier
                let right = PHAssetResource.assetResources(for:b).first?.originalFilename ?? b.localIdentifier
                return sort == "nameAZ" ? left.localizedCaseInsensitiveCompare(right) == .orderedAscending:left.localizedCaseInsensitiveCompare(right) == .orderedDescending
            }
        }
        items = list;revision += 1;loading = false
    }
    func choose(_ ids:[String],completion:@escaping ([MediaAsset],String?)->Void) {
        guard !importing else {return};importing = true;progress = 0;error = nil
        Task {
            var media:[MediaAsset] = [],failures:[String] = []
            let assets = PHAsset.fetchAssets(withLocalIdentifiers:ids,options:nil)
            var index:[String:PHAsset] = [:];assets.enumerateObjects {asset,_,_ in index[asset.localIdentifier] = asset}
            for (offset,id) in ids.enumerated() {
                guard let asset = index[id] else {failures.append(localized("An item is no longer available in the library."));continue}
                do {
                    let resources = PHAssetResource.assetResources(for:asset)
                    let type:PHAssetResourceType = asset.mediaType == .video ? .video:.photo
                    guard let resource = resources.first(where:{$0.type == (asset.mediaType == .video ? .fullSizeVideo:.fullSizePhoto)}) ?? resources.first(where:{$0.type == type}) ?? resources.first else {throw MediaError.invalid}
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(newID(),isDirectory:true)
                    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    defer {try? FileManager.default.removeItem(at:folder)}
                    let url = folder.appendingPathComponent((resource.originalFilename as NSString).lastPathComponent)
                    let options = PHAssetResourceRequestOptions();options.isNetworkAccessAllowed = true
                    options.progressHandler = {[weak self] value in Task {@MainActor in self?.progress = (Double(offset)+value)/Double(ids.count)}}
                    try await withCheckedThrowingContinuation {(continuation:CheckedContinuation<Void,Error>) in
                        PHAssetResourceManager.default().writeData(for:resource,toFile:url,options:options) {error in
                            if let error {continuation.resume(throwing:error)} else {continuation.resume()}
                        }
                    }
                    media.append(try await ProjectStore.ingest(url))
                } catch {failures.append(error.localizedDescription)}
                progress = Double(offset+1)/Double(ids.count)
            }
            importing = false
            completion(media,failures.isEmpty ? nil:failures.joined(separator:"\n"))
        }
    }
}

struct MediaPicker:View {
    var multiple = true
    var imagesOnly = false
    var completion:([MediaAsset],String?)->Void
    @StateObject private var library = PhotoLibraryModel()
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var filter = "Library"
    @AppStorage("library.media.section") private var section = "recent"
    @AppStorage("library.media.album") private var album = ""
    @AppStorage("library.media.sort") private var sort = "newest"
    @ViewState<OrderedMediaSelection> private var chosen = OrderedMediaSelection()
    var body:some View {
        NavigationStack {
            VStack(spacing:8) {
                if !imagesOnly {
                    Picker("Media type",selection:$filter) {ForEach(["Library","Photos","Videos"],id:\.self) {Text(loc($0)).tag($0)}}
                        .pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("media.filters")
                }
                HStack {
                    if section == "albums" && !album.isEmpty {Button {album = ""} label:{Image(systemName:"chevron.left")}.accessibilityLabel("All albums")}
                    Menu {
                        Button("Recent") {section = "recent";album = ""}
                        Button("Albums") {section = "albums";album = ""}
                    } label:{Label(section == "recent" ? loc("Recent") : library.albums.first(where:{$0.id == album})?.name ?? loc("Albums"),systemImage:"chevron.down")}
                    Spacer()
                    if !chosen.ids.isEmpty {Button("Clear") {chosen.clear()}}
                    Menu {
                        Picker("Sort",selection:$sort) {
                            Text("Date: newest first").tag("newest");Text("Date: oldest first").tag("oldest")
                            Text("Name: A to Z").tag("nameAZ");Text("Name: Z to A").tag("nameZA")
                        }
                    } label:{Image(systemName:"arrow.up.arrow.down")}.accessibilityLabel("Sort")
                }.padding(.horizontal)
                if library.access == .limited {
                    Button("Manage access") {if let controller = UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).flatMap(\.windows).first(where:{$0.isKeyWindow})?.rootViewController {var current = controller;while let next = current.presentedViewController {current = next};PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:current)}}.font(.caption)
                }
                if !library.allowed {
                    Spacer();Text("Allow access to your videos and photos to browse them here.").multilineTextAlignment(.center).padding()
                    Button(library.access == .denied ? loc("Open Settings"):loc("Allow access")) {
                        if library.access == .denied,let url = URL(string:UIApplication.openSettingsURLString) {UIApplication.shared.open(url)}
                        else {Task {await library.request()}}
                    }.buttonStyle(.borderedProminent);Spacer()
                } else if library.loading {Spacer();ProgressView();Spacer()}
                else if section == "albums" && album.isEmpty {
                    ScrollView {LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:12) {ForEach(library.albums) {item in
                        Button {album = item.id} label:{VStack(alignment:.leading) {
                            LibraryThumbnail(asset:item.cover,manager:library.thumbnails).aspectRatio(1.2,contentMode:.fit).clipped()
                            Text(item.name).lineLimit(1);Text("\(item.count) items").font(.caption).foregroundStyle(Palette.dim)
                        }}.buttonStyle(.plain)
                    }}.padding()}
                } else if library.items.isEmpty {Spacer();Text("No media found").foregroundStyle(Palette.dim);Spacer()}
                else {PhotoSelectionGrid(assets:library.items,manager:library.thumbnails,revision:library.revision,selection:$chosen,multiple:multiple)}
                HStack {
                    Text("\(chosen.ids.count) selected").font(.caption).foregroundStyle(Palette.dim)
                    Spacer()
                    Button(chosen.ids.isEmpty ? loc("Add") : localized("Add (\(chosen.ids.count))")) {
                        library.choose(chosen.ids) {media,error in completion(media,error);dismiss()}
                    }.buttonStyle(.borderedProminent).disabled(chosen.ids.isEmpty)
                }.padding()
            }.background(Palette.bg).navigationTitle("Media library").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.cancellationAction) {Button("Cancel") {completion([],nil);dismiss()}}}
                .disabled(library.importing)
                .overlay {if library.importing {VStack(spacing:12) {ProgressView(value:library.progress);Text("Importing… \(Int(library.progress*100))%").font(.caption)}.padding(24).frame(width:240).background(Palette.surface,in:RoundedRectangle(cornerRadius:16))}}
        }
        .interactiveDismissDisabled(library.importing)
        .task {if imagesOnly {filter = "Photos"};chosen.limit = multiple ? 50:1;library.filter = filter;library.sort = sort;library.albumID = section == "albums" && !album.isEmpty ? album:nil;if library.access == .notDetermined {await library.request()} else {reload()}}
        .onChange(of:filter) {_,_ in reload()}
        .onChange(of:section) {_,_ in reload()}
        .onChange(of:album) {_,_ in reload()}
        .onChange(of:sort) {_,_ in reload()}
    }
    private func reload() {library.filter = filter;library.sort = sort;library.albumID = section == "albums" && !album.isEmpty ? album:nil;library.reload()}
}

struct LibraryThumbnail:View {
    let asset:PHAsset
    let manager:PHCachingImageManager
    @ViewState<UIImage?> private var image:UIImage?
    var body:some View {
        ZStack {Palette.surface2;if let image {Image(uiImage:image).resizable().scaledToFill()}}
            .clipped().task(id:asset.localIdentifier) {
                image = nil
                let options = PHImageRequestOptions();options.deliveryMode = .opportunistic;options.isNetworkAccessAllowed = true
                manager.requestImage(for:asset,targetSize:CGSize(width:300,height:300),contentMode:.aspectFill,options:options) {value,_ in Task {@MainActor in image = value}}
            }
    }
}

struct PhotoSelectionGrid:UIViewRepresentable {
    let assets:[PHAsset]
    let manager:PHCachingImageManager
    let revision:Int
    @Binding var selection:OrderedMediaSelection
    let multiple:Bool
    func makeCoordinator() -> Coordinator {Coordinator(self)}
    func makeUIView(context:Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout();layout.minimumInteritemSpacing = 3;layout.minimumLineSpacing = 3
        let view = UICollectionView(frame:.zero,collectionViewLayout:layout);view.backgroundColor = UIColor(argb:0xFF0E0E12)
        view.register(PhotoCell.self,forCellWithReuseIdentifier:"photo");view.delegate = context.coordinator;view.dataSource = context.coordinator
        let hold = UILongPressGestureRecognizer(target:context.coordinator,action:#selector(Coordinator.dragSelected(_:)));hold.minimumPressDuration = 0.35;hold.allowableMovement = 10
        view.addGestureRecognizer(hold);view.panGestureRecognizer.require(toFail:hold)
        return view
    }
    func updateUIView(_ view:UICollectionView,context:Context) {
        let previous = context.coordinator.parent.revision
        context.coordinator.parent = self
        if previous != revision {view.reloadData();view.setContentOffset(.zero,animated:false)}
        else {for cell in view.visibleCells {if let index = view.indexPath(for:cell),let cell = cell as? PhotoCell {context.coordinator.badge(cell,index:index.item)}}}
    }
    static func dismantleUIView(_ view:UICollectionView,coordinator:Coordinator) {coordinator.stop()}
    final class Coordinator:NSObject,UICollectionViewDataSource,UICollectionViewDelegateFlowLayout {
        var parent:PhotoSelectionGrid
        private var visited:Set<String> = []
        private var adding = true
        private var lastIndex:Int?
        private var link:CADisplayLink?
        private weak var collection:UICollectionView?
        private var dragPoint = CGPoint.zero
        init(_ parent:PhotoSelectionGrid) {self.parent = parent}
        deinit {link?.invalidate()}
        func stop() {link?.invalidate();link = nil}
        func collectionView(_ collectionView:UICollectionView,numberOfItemsInSection section:Int)->Int {parent.assets.count}
        func collectionView(_ collectionView:UICollectionView,layout:UICollectionViewLayout,sizeForItemAt indexPath:IndexPath)->CGSize {
            let columns = max(3,Int(collectionView.bounds.width/115)),side = (collectionView.bounds.width-CGFloat(columns-1)*3)/CGFloat(columns)
            return CGSize(width:side,height:side)
        }
        func collectionView(_ view:UICollectionView,cellForItemAt index:IndexPath)->UICollectionViewCell {
            let cell = view.dequeueReusableCell(withReuseIdentifier:"photo",for:index) as! PhotoCell,asset = parent.assets[index.item]
            cell.assetID = asset.localIdentifier;cell.image.image = nil;badge(cell,index:index.item)
            cell.duration.text = asset.mediaType == .video ? formatTime(Int64(asset.duration*1_000_000)):""
            let options = PHImageRequestOptions();options.isNetworkAccessAllowed = true;options.deliveryMode = .opportunistic
            parent.manager.requestImage(for:asset,targetSize:CGSize(width:260,height:260),contentMode:.aspectFill,options:options) {[weak cell] image,_ in
                DispatchQueue.main.async {if cell?.assetID == asset.localIdentifier {cell?.image.image = image}}
            }
            return cell
        }
        func badge(_ cell:PhotoCell,index:Int) {
            let order = parent.selection.ids.firstIndex(of:parent.assets[index].localIdentifier)
            cell.badge.text = order.map {String($0+1)} ?? ""
            cell.badge.backgroundColor = order == nil ? UIColor.black.withAlphaComponent(0.4):UIColor(argb:0xFF8B6CFF)
            cell.layer.borderColor = UIColor(argb:0xFF8B6CFF).cgColor;cell.layer.borderWidth = order == nil ? 0:3
        }
        func collectionView(_ view:UICollectionView,didSelectItemAt index:IndexPath) {
            if !parent.multiple && !parent.selection.ids.contains(parent.assets[index.item].localIdentifier) {parent.selection.clear()}
            parent.selection.toggle(parent.assets[index.item].localIdentifier)
            for cell in view.visibleCells {if let i = view.indexPath(for:cell),let cell = cell as? PhotoCell {badge(cell,index:i.item)}}
        }
        @objc func dragSelected(_ gesture:UILongPressGestureRecognizer) {
            guard let view = gesture.view as? UICollectionView,parent.multiple else {return}
            collection = view;dragPoint = gesture.location(in:view)
            if gesture.state == .began {
                visited = [];lastIndex = nil
                if let index = view.indexPathForItem(at:dragPoint) {adding = !parent.selection.ids.contains(parent.assets[index.item].localIdentifier)}
                link = CADisplayLink(target:self,selector:#selector(autoScroll));link?.add(to:.main,forMode:.common)
            }
            if gesture.state == .began || gesture.state == .changed {chooseUnderFinger(view)}
            else {link?.invalidate();link = nil;visited = []}
        }
        private func chooseUnderFinger(_ view:UICollectionView) {
            guard let index = view.indexPathForItem(at:dragPoint) else {return}
            let previous = lastIndex ?? index.item
            for position in stride(from:previous,through:index.item,by:index.item >= previous ? 1 : -1) {
                let id = parent.assets[position].localIdentifier
                if visited.insert(id).inserted {parent.selection.set(id,selected:adding)}
            }
            lastIndex = index.item
            for cell in view.visibleCells {if let i = view.indexPath(for:cell),let cell = cell as? PhotoCell {badge(cell,index:i.item)}}
        }
        @objc private func autoScroll() {
            guard let view = collection else {return}
            let y = dragPoint.y-view.contentOffset.y
            let step:CGFloat = y<45 ? -5 : y>view.bounds.height-45 ? 5:0
            let offset = clamp(view.contentOffset.y+step,0,max(0,view.contentSize.height-view.bounds.height))
            let difference = offset-view.contentOffset.y;view.contentOffset.y = offset;dragPoint.y += difference;chooseUnderFinger(view)
        }
    }
    final class PhotoCell:UICollectionViewCell {
        let image = UIImageView(),badge = UILabel(),duration = UILabel()
        var assetID:String?
        override init(frame:CGRect) {
            super.init(frame:frame);image.contentMode = .scaleAspectFill;image.clipsToBounds = true
            badge.textAlignment = .center;badge.textColor = .white;badge.font = .systemFont(ofSize:12,weight:.bold);badge.layer.cornerRadius = 12;badge.clipsToBounds = true
            duration.textColor = .white;duration.font = .monospacedDigitSystemFont(ofSize:11,weight:.medium);duration.backgroundColor = .black.withAlphaComponent(0.5)
            for view in [image,badge,duration] {contentView.addSubview(view)}
        }
        required init?(coder:NSCoder) {fatalError("init(coder:) is unavailable")}
        override func layoutSubviews() {super.layoutSubviews();image.frame = contentView.bounds;badge.frame = CGRect(x:bounds.width-29,y:5,width:24,height:24);duration.sizeToFit();duration.frame.origin = CGPoint(x:max(2,bounds.width-duration.bounds.width-5),y:bounds.height-20)}
    }
}
