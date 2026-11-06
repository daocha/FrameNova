import SwiftUI
import AVFoundation

// Keep stored view state on the property-wrapper API across supported SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias EditorFocus<Value: Hashable> = SwiftUI.FocusState<Value>

extension Color { init(argb:UInt32) { self.init(uiColor:UIColor(argb:argb)) } }
/// The app icon followed by the FrameNova wordmark: heavy, tightly spaced letters, with "Nova" in the icon's gradient.
struct BrandMark: View {
    var body: some View {
        HStack(spacing:10) {
            Image("BrandIcon").resizable().frame(width:34,height:34).clipShape(RoundedRectangle(cornerRadius:8,style:.continuous))
            (Text("Frame").foregroundStyle(Palette.text)
                + Text("Nova").foregroundStyle(Palette.brandGradient(startPoint:.leading,endPoint:.trailing)))
                .font(.system(size:27,weight:.black)).tracking(-0.8)
        }.accessibilityElement(children:.ignore).accessibilityLabel("FrameNova")
    }
}

enum Palette {
    static let accent = Color(argb:0xFF8B6CFF), accentSoft = Color(argb:0xFF2C2547), teal = Color(argb:0xFF2FD1C1), bg = Color(argb:0xFF0E0E12)
    static let surface = Color(argb:0xFF17171D), surface2 = Color(argb:0xFF202028), surface3 = Color(argb:0xFF2A2A34)
    static let text = Color(argb:0xFFF2F2F5), dim = Color(argb:0xFF9B9BA8), danger = Color(argb:0xFFFF5A6A)
    static func brandGradient(startPoint:UnitPoint = .topLeading,endPoint:UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(colors:[accent,Color(argb:0xFF4F7CFF),teal],startPoint:startPoint,endPoint:endPoint)
    }
    static func track(_ kind:TrackKind) -> Color { Color(argb:kind == .main ? 0xFF3A3A48 : kind == .overlay ? 0xFF4A3B7A : kind == .text ? 0xFFB0457E:0xFF1F6F6A) }
}
@main struct FrameNovaApp: App {
    @StateObject private var store = ProjectStore()
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    init() {
        // An earlier build kept the language in the system's per-app list, which only applies after a restart.
        UserDefaults.standard.removeObject(forKey:"AppleLanguages")
    }
    var body: some Scene {
        WindowGroup { root.onAppear {
            FontRegistry.register()
            try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            #if targetEnvironment(macCatalyst)
            for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}) {scene.sizeRestrictions?.minimumSize = CGSize(width:1000,height:640)}
            #endif
        }.environmentObject(store).environment(\.locale,AppLanguage.locale(for:language)).preferredColorScheme(.dark).tint(Palette.accent) }
        .commands {
            #if targetEnvironment(macCatalyst)
            DesktopEditorCommands()
            #endif
            CommandGroup(replacing:.help) { Link("FrameNova license",destination:URL(string:"https://polyformproject.org/licenses/strict/1.0.0/")!) } }
    }
    @ViewBuilder private var root:some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--editor-ui-fixture") {InteractionFixtureView()}
        else {HomeView()}
        #else
        HomeView()
        #endif
    }

}
struct HomeView: View {
    @EnvironmentObject var store: ProjectStore
    @ViewState<Project?> private var selected: Project?
    @ViewState<Bool> private var picker = false
    @ViewState<Bool> private var files = false
    @ViewState<Bool> private var mediaSources = false
    @ViewState<Bool> private var settings = false
    @StateObject private var updates = AppStoreUpdates()
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @Environment(\.openURL) private var openURL
    @ViewState<Bool> private var importing = false
    @ViewState<[MediaAsset]> private var pending: [MediaAsset] = []
    @ViewState<CanvasSettings> private var canvas = CanvasSettings()
    @ViewState<Project?> private var renaming: Project?
    @ViewState<Project?> private var deleting: Project?
    @ViewState<String> private var name = ""
    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
            VStack(spacing:0) {
                // Same header as Android: the brand on the left, the settings cog on the right, no navigation bar.
                HStack(spacing:0) {
                    BrandMark(); Spacer(minLength:0)
                    Button { settings = true } label: {
                        Image(systemName:"gearshape.fill").font(.system(size:21)).foregroundStyle(Palette.text).frame(width:48,height:48)
                            .overlay(alignment:.topTrailing) {if updates.hasUpdate {Circle().fill(Palette.danger).frame(width:8,height:8).padding(.top,12).padding(.trailing,12)}}
                    }.accessibilityLabel("Settings")
                }.padding(.leading,20).padding(.trailing,8).padding(.top,12).padding(.bottom,4)
                ScrollView {
                    VStack(spacing:12) {
                        if updates.hasUpdate {
                            HStack(spacing:10) {
                                Image(systemName:"arrow.down.app").font(.system(size:22)).foregroundStyle(Palette.accent)
                                Text("Version \(updates.version) is available").font(.system(size:16)).foregroundStyle(Palette.text).frame(maxWidth:.infinity,alignment:.leading)
                                Button("Update") {if let url = updates.storeURL {openURL(url)}}.font(.system(size:14,weight:.medium))
                            }.padding(14).background(Palette.accentSoft).clipShape(RoundedRectangle(cornerRadius:12))
                                .contentShape(Rectangle()).onTapGesture {settings = true}
                        }
                        Button {
                            #if targetEnvironment(macCatalyst)
                            mediaSources = true
                            #else
                            picker = true
                            #endif
                        } label: {
                            Group {
                                if importing { ProgressView().tint(.white) }
                                else {
                                    HStack(spacing:8) {
                                        Image(systemName:"plus").font(.system(size:34))
                                        VStack(alignment:.leading,spacing:0) {
                                            Text("New project").font(.system(size:20,weight:.semibold))
                                            Text("Pick videos and photos to start").font(.system(size:13)).opacity(0.85)
                                        }
                                    }.foregroundStyle(.white)
                                }
                            }.frame(maxWidth:.infinity).frame(height:120)
                        }.buttonStyle(.plain).disabled(importing).background(Palette.brandGradient()).clipShape(RoundedRectangle(cornerRadius:18))
                        if store.projects.isEmpty { Text("Your projects appear here. Everything stays on this device.").font(.system(size:16)).foregroundStyle(Palette.dim).padding(8).frame(maxWidth:.infinity,alignment:.leading) }
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:EditorPresentation.projectColumns(width:viewport.size.width)),spacing:12) {
                            ForEach(store.projects) { project in
                                VStack(spacing:0) {
                                    ProjectCover(project:project).aspectRatio(1.6,contentMode:.fit).overlay(alignment:.bottomTrailing) {
                                        Text(formatTime(project.durationUs)).font(.system(size:11)).foregroundStyle(Palette.text).padding(.horizontal,5).padding(.vertical,1)
                                            .background(.black.opacity(0.6),in:RoundedRectangle(cornerRadius:4)).padding(6)
                                    }
                                    HStack(spacing:0) {
                                        VStack(alignment:.leading,spacing:0) {
                                            Text(project.name).font(.system(size:16,weight:.medium)).foregroundStyle(Palette.text).lineLimit(1)
                                            Text("\(project.canvas.aspect.rawValue) · \(project.modifiedAt.formatted(date:.numeric,time:.omitted))").font(.system(size:11)).foregroundStyle(Palette.dim)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        Menu {
                                            Button("Rename") { name = project.name; renaming = project }
                                            Button("Duplicate") { var copy = project; copy.id = newID(); copy.name = localized("\(project.name) copy"); do { try store.save(copy) } catch { store.error = error.localizedDescription } }
                                            Button("Delete",role:.destructive) { deleting = project }
                                        } label: { Image(systemName:"ellipsis").rotationEffect(.degrees(90)).font(.system(size:18)).foregroundStyle(Palette.text).frame(width:48,height:48) }
                                            .accessibilityLabel("More")
                                    }.padding(.leading,10).padding(.vertical,6)
                                }.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius:14)).contentShape(Rectangle()).onTapGesture { selected = project }
                            }
                        }
                    }.padding(16).frame(maxWidth:1400).frame(maxWidth:.infinity)
                }
            }.background(Palette.bg).toolbar(.hidden,for:.navigationBar)
                .navigationDestination(isPresented:Binding(get:{selected != nil},set:{if !$0 {selected = nil}})) { if let project = selected { EditorView(project:project,store:store) } }
        }
        }
        // A new language rebuilds the screen so every string is looked up again; the sheets stay open.
        .id(language)
        .confirmationDialog("New project",isPresented:$mediaSources,titleVisibility:.visible) {
            Button("Files…") {files = true}
            Button("Photos…") {picker = true}
            Button("Cancel",role:.cancel) {}
        }
        .sheet(isPresented:$picker) { MediaPicker { media,error in picker = false; receive(media); if let error { store.error = error } } }
        .mediaFileImporter(isPresented:$files,allowedContentTypes:[.movie,.image],allowsMultipleSelection:true) { result in
            Task { @MainActor in
                importing = true; defer { importing = false }
                do { var media:[MediaAsset] = []; for url in try result.get() { media.append(try await ProjectStore.ingest(url)) }; receive(media) }
                catch { store.error = error.localizedDescription }
            }
        }
        .sheet(isPresented:Binding(get:{ !pending.isEmpty },set:{ if !$0 { pending = [] } })) {
            NavigationStack { ScrollView {CanvasControls(canvas:$canvas).padding(.horizontal,16).padding(.bottom,24)}.background(Palette.surface).navigationTitle("New project").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { pending = [] } }
                ToolbarItem(placement:.confirmationAction) { Button("Create") { var p = Project(name:localized("Project \(Date().formatted(date:.abbreviated,time:.omitted))"),canvas:canvas); p.add(pending,kind:.main,at:0); do { try store.save(p);Task {_ = await store.cover(p)}; pending = []; selected = p } catch { store.error = error.localizedDescription } } }
            } }.presentationDetents([.medium,.large])
        }
        .task {await updates.check()}
        .sheet(isPresented:$settings) { SettingsView(updates:updates) }
        .alert("Rename project",isPresented:Binding(get:{renaming != nil},set:{if !$0 {renaming = nil}})) {
            TextField("Name",text:$name); Button("Save") { if var p = renaming { p.name = name; do { try store.save(p) } catch { store.error = error.localizedDescription } }; renaming = nil }; Button("Cancel",role:.cancel) {}
        }
        .alert("Delete project?",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting = nil}})) {
            Button("Delete",role:.destructive) { if let p = deleting { do { try store.delete(p) } catch { store.error = error.localizedDescription } }; deleting = nil }; Button("Cancel",role:.cancel) {}
        } message: { Text("The project is removed. Your original videos and photos are not touched.") }
        .alert("FrameNova",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error = nil}})) { Button("OK") {store.error = nil} } message: { Text(store.error ?? "") }
    }
    func receive(_ media:[MediaAsset]) {
        guard let first = media.first else { return }
        canvas.aspect = Aspect.allCases.min { abs($0.ratio-Double(first.width)/Double(max(1,first.height))) < abs($1.ratio-Double(first.width)/Double(max(1,first.height))) } ?? .wide
        canvas.tier = Resolution.allCases.last { $0.rawValue <= max(first.width,first.height)+64 } ?? .fhd
        canvas.fps = first.frameRate >= 50 ? 60 : first.frameRate >= 23 && first.frameRate <= 24.5 ? 24 : first.frameRate > 24.5 && first.frameRate < 26 ? 25:30
        pending = media
    }
}
struct ProjectCover: View {
    let project:Project
    @EnvironmentObject private var store:ProjectStore
    @ViewState<UIImage?> private var image:UIImage?
    var body:some View {
        GeometryReader {geometry in
            ZStack {
                Palette.surface2
                if let image {Image(uiImage:image).resizable().scaledToFill().frame(width:geometry.size.width,height:geometry.size.height)}
                else {Image(systemName:"film").foregroundStyle(Palette.dim)}
            }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
        }.task(id:store.coverKey(project)) {image = await store.cover(project)}
    }
}
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject var updates: AppStoreUpdates
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system
    @AppStorage("developerToolsVersion") private var developerVersion = ""
    @ViewState<Int> private var taps = 0
    @ViewState<Bool> private var logs = false
    @ViewState<Bool> private var shareLogs = false
    @ViewState<Bool> private var licensesExpanded = false
    private var version:String {Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"}
    private var build:String {Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"}
    private var unlocked:Bool {developerVersion == version+"-"+build}
    private var updateStatus:String {
        switch updates.phase {
        case .idle:return loc("Check for a newer version")
        case .checking:return loc("Checking for updates…")
        case .current:return loc("You're up to date")
        case .available(let version):return localized("Version \(version) is available")
        case .notListed:return loc("This build isn't on the App Store, so it doesn't check for updates.")
        case .failed(let message):return localized("Could not check for updates: \(message)")
        }
    }
    /// The bundled and downloadable fonts, all under the SIL Open Font License, as Android lists them.
    private var fontNames:String {
        struct Entry:Decodable {let name:String;let group:String?}
        func names(_ file:String,skipping:Set<String> = []) -> [String] {
            Bundle.main.url(forResource:file,withExtension:"json").flatMap {try? Data(contentsOf:$0)}.flatMap {try? JSONDecoder().decode([Entry].self,from:$0)}?.filter {!skipping.contains($0.group ?? "")}.map(\.name) ?? []
        }
        return (names("BundledFonts")+names("DownloadFonts")).joined(separator:", ")
    }
    private func label(_ text:String,medium:Bool = false) -> some View {Text(loc(text)).font(.system(size:16,weight:medium ? .medium:.regular)).foregroundStyle(Palette.text)}
    private func dim(_ text:String,size:CGFloat = 13) -> some View {Text(text).font(.system(size:size)).foregroundStyle(Palette.dim).fixedSize(horizontal:false,vertical:true)}
    /// The same content and order as Android's settings dialog.
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Text("FrameNova").font(.system(size:24)).foregroundStyle(Palette.text).padding(.bottom,16)
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    dim(localized("Version \(version) (\(build))")).onTapGesture {taps += 1; if taps >= 10 {developerVersion = version+"-"+build}}
                    label("Language",medium:true).padding(.top,12)
                    // The language changes at once, as on Android.
                    FlowLayout {
                        Chip(title:loc("System default"),selected:language == AppLanguage.system) {language = AppLanguage.system}
                        Chip(title:"English",selected:language == AppLanguage.english) {language = AppLanguage.english}
                        Chip(title:"繁體中文",selected:language == AppLanguage.traditionalChinese) {language = AppLanguage.traditionalChinese}
                    }.padding(.top,-4)
                    label(localized("Updates · App Store"),medium:true).padding(.top,12)
                    dim(updateStatus)
                    if updates.hasUpdate {TextAction(title:loc("Update now")) {if let url = updates.storeURL {openURL(url)}}.padding(.top,8)}
                    else {TextAction(title:loc("Check for updates"),enabled:updates.phase != .checking) {Task {await updates.check(manual:true)}}.padding(.top,8)}
                    if unlocked {
                        Divider().overlay(Palette.dim.opacity(0.4)).padding(.top,16)
                        HStack {
                            label("Developer tools",medium:true); Spacer()
                            // Turning them off locks them again; ten taps on the version unlock them.
                            Toggle("",isOn:Binding(get:{true},set:{if !$0 {developerVersion = ""; taps = 0}})).labelsHidden()
                        }.padding(.top,8)
                        OutlinedAction(title:loc("Developer logs")) {logs = true}
                        OutlinedAction(title:loc("Save logs")) {if !FileManager.default.fileExists(atPath:AppLog.url.path) {AppLog.record("Developer tools enabled")}; shareLogs = true}
                    }
                    Button {licensesExpanded.toggle()} label: {
                        HStack {label("Licenses",medium:true); Spacer(); Image(systemName:licensesExpanded ? "arrowtriangle.up.fill":"arrowtriangle.down.fill").font(.system(size:10)).foregroundStyle(Palette.text)}
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.top,16)
                    .accessibilityLabel(licensesExpanded ? loc("Hide license details"):loc("Show license details"))
                    dim(loc("FrameNova is source-available under the PolyForm Strict License 1.0.0."),size:12)
                    if licensesExpanded {
                        dim(loc("Uses only Apple's system frameworks: SwiftUI, AVFoundation and Core Image.")+"\n"+localized("Fonts, all under the SIL Open Font License 1.1: \(fontNames)."),size:12)
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            HStack {Spacer(); TextAction(title:loc("Close")) {dismiss()}}.padding(.top,24)
        }.padding(24).background(Palette.surface3.ignoresSafeArea()).presentationDetents([.medium,.large])
        .sheet(isPresented:$logs) {NavigationStack {ScrollView {Text(AppLog.text).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding()}.navigationTitle("Developer logs").toolbar {Button("Close") {logs = false}}}}
        .sheet(isPresented:$shareLogs) {ShareSheet(url:AppLog.url)}
    }
}
