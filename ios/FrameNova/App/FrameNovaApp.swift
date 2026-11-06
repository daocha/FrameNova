import SwiftUI
import AVFoundation

// Keep stored view state on the property-wrapper API across supported SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>
typealias EditorFocus<Value: Hashable> = SwiftUI.FocusState<Value>

extension Color { init(argb:UInt32) { self.init(uiColor:UIColor(argb:argb)) } }
/// The app icon followed by the FrameNova wordmark: heavy, rounded letters, with "Nova" in the icon's gradient.
struct BrandMark: View {
    var body: some View {
        HStack(spacing:9) {
            Image("BrandIcon").resizable().frame(width:30,height:30).clipShape(RoundedRectangle(cornerRadius:7,style:.continuous))
            (Text("Frame").foregroundStyle(.white)
                + Text("Nova").foregroundStyle(LinearGradient(colors:[Palette.accent,Color(argb:0xFF4F7CFF),Palette.teal],startPoint:.leading,endPoint:.trailing)))
                .font(.system(size:24,weight:.black,design:.rounded)).tracking(-0.6)
        }.accessibilityElement(children:.ignore).accessibilityLabel("FrameNova")
    }
}

enum Palette {
    static let accent = Color(argb:0xFF8B6CFF), teal = Color(argb:0xFF2FD1C1), bg = Color(argb:0xFF0E0E12)
    static let surface = Color(argb:0xFF17171D), surface2 = Color(argb:0xFF202028), dim = Color(argb:0xFF9B9BA8)
    static func track(_ kind:TrackKind) -> Color { Color(argb:kind == .main ? 0xFF3A3A48 : kind == .overlay ? 0xFF4A3B7A : kind == .text ? 0xFFB0457E:0xFF1F6F6A) }
}
@main struct FrameNovaApp: App {
    @StateObject private var store = ProjectStore()
    var body: some Scene {
        WindowGroup { root.onAppear {
            FontRegistry.register()
            try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            #if targetEnvironment(macCatalyst)
            for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}) {scene.sizeRestrictions?.minimumSize = CGSize(width:1000,height:640)}
            #endif
        }.environmentObject(store).preferredColorScheme(.dark).tint(Palette.accent) }
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
    @ViewState<Bool> private var importing = false
    @ViewState<[MediaAsset]> private var pending: [MediaAsset] = []
    @ViewState<CanvasSettings> private var canvas = CanvasSettings()
    @ViewState<Project?> private var renaming: Project?
    @ViewState<Project?> private var deleting: Project?
    @ViewState<String> private var name = ""
    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
            ScrollView {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:EditorPresentation.projectColumns(width:viewport.size.width)),spacing:12) {
                    Section {
                        ForEach(store.projects) { project in
                            VStack(spacing:0) {
                                ProjectCover(project:project).aspectRatio(1.6,contentMode:.fit).overlay(alignment:.bottomTrailing) { Text(formatTime(project.durationUs)).font(.caption2).padding(5).background(.black.opacity(0.65)).padding(6) }
                                HStack {
                                    VStack(alignment:.leading) { Text(project.name).lineLimit(1); Text("\(project.canvas.aspect.rawValue) · \(project.modifiedAt.formatted(date:.numeric,time:.omitted))").font(.caption2).foregroundStyle(Palette.dim) }
                                    Spacer(minLength:0)
                                    Menu {
                                        Button("Rename") { name = project.name; renaming = project }
                                        Button("Duplicate") { var copy = project; copy.id = newID(); copy.name = String(localized: "\(project.name) copy"); do { try store.save(copy) } catch { store.error = error.localizedDescription } }
                                        Button("Delete",role:.destructive) { deleting = project }
                                    } label: { Image(systemName:"ellipsis").padding(8) }
                                }.padding(10)
                            }.background(Palette.surface).clipShape(RoundedRectangle(cornerRadius:14)).contentShape(Rectangle()).onTapGesture { selected = project }
                        }
                    } header: {
                        VStack(alignment:.leading,spacing:16) {
                            Button {
                                #if targetEnvironment(macCatalyst)
                                mediaSources = true
                                #else
                                picker = true
                                #endif
                            } label: {
                                HStack(spacing:12) { Image(systemName:"plus").font(.largeTitle); VStack(alignment:.leading) { Text("New project").font(.title3.bold()); Text("Pick videos and photos to start").font(.footnote) } }.frame(maxWidth:.infinity,minHeight:120)
                            }.buttonStyle(.plain).background(LinearGradient(colors:[Palette.accent,Color(argb:0xFF4F7CFF),Palette.teal],startPoint:.topLeading,endPoint:.bottomTrailing)).clipShape(RoundedRectangle(cornerRadius:18))
                            if importing { ProgressView("Importing…") }
                            if store.projects.isEmpty { Text("Your projects appear here. Everything stays on this device.").font(.subheadline).foregroundStyle(Palette.dim).padding(8) }
                        }.padding(.bottom,12)
                    }
                }.padding(16).frame(maxWidth:1400).frame(maxWidth:.infinity)
            }.background(Palette.bg).navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.topBarLeading) { BrandMark() }; ToolbarItem(placement:.primaryAction) { Button { settings = true } label: { Image(systemName:"gearshape") }.accessibilityLabel("Settings") } }
                .navigationDestination(isPresented:Binding(get:{selected != nil},set:{if !$0 {selected = nil}})) { if let project = selected { EditorView(project:project,store:store) } }
        }
        }
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
            NavigationStack { CanvasControls(canvas:$canvas).navigationTitle("New project").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("Cancel") { pending = [] } }
                ToolbarItem(placement:.confirmationAction) { Button("Create") { var p = Project(name:String(localized: "Project \(Date().formatted(date:.abbreviated,time:.omitted))"),canvas:canvas); p.add(pending,kind:.main,at:0); do { try store.save(p);Task {_ = await store.cover(p)}; pending = []; selected = p } catch { store.error = error.localizedDescription } } }
            } }.presentationDetents([.medium,.large])
        }
        .sheet(isPresented:$settings) { SettingsView() }
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
    @AppStorage("developerToolsVersion") private var developerVersion = ""
    @ViewState<Int> private var taps = 0
    @ViewState<Bool> private var logs = false
    @ViewState<Bool> private var shareLogs = false
    private var version:String {Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"}
    private var build:String {Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"}
    private var unlocked:Bool {developerVersion == version+"-"+build}
    var body: some View {NavigationStack {Form {
        Text("Version \(version) (\(build))").onTapGesture {taps += 1; if taps >= 10 {developerVersion = version+"-"+build}}
        Text("Projects and imported media stay on this device.")
        if unlocked {
            Section("Developer tools") {
                Toggle("Enabled",isOn:Binding(get:{unlocked},set:{if !$0 {developerVersion = ""; taps = 0}}))
                Button("Developer logs") {logs = true}
                Button("Save logs") {if !FileManager.default.fileExists(atPath:AppLog.url.path) {AppLog.record("Developer tools enabled")}; shareLogs = true}
            }
        }
        Section("Licenses") {
            Text("FrameNova is source-available under the PolyForm Strict License 1.0.0.")
            DisclosureGroup("License details") {
                Text(Bundle.main.url(forResource:"LICENSE",withExtension:nil).flatMap {try? String(contentsOf:$0,encoding:.utf8)} ?? loc("License unavailable.")).font(.caption)
            }
            Text("Bundled and downloadable fonts use the SIL Open Font License 1.1.").font(.footnote)
        }
    }.navigationTitle("FrameNova").toolbar {Button("Close") {dismiss()}}}
        .sheet(isPresented:$logs) {NavigationStack {ScrollView {Text(AppLog.text).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding()}.navigationTitle("Developer logs").toolbar {Button("Close") {logs = false}}}}
        .sheet(isPresented:$shareLogs) {ShareSheet(url:AppLog.url)}
    }
}
