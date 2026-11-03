import AVFoundation
import SwiftUI

@MainActor final class EditorModel: ObservableObject {
    @Published var project: Project
    @Published var selected: String?
    @Published var playhead: Int64 = 0
    @Published var playing = false
    @Published var error: String? {didSet {if let error {AppLog.record(error)}}}
    @Published var busy = false
    @Published var revision = 0
    @Published var recording = false
    @Published var shareURL:URL?
    private var gestureStart:Project?
    let player = AVPlayer()
    let exporter = Exporter()
    let store: ProjectStore
    private var undoStack: [Project] = [], redoStack: [Project] = []
    private var rebuild: Task<Void,Never>?
    private var observer: Any?
    private var recorder: AVAudioRecorder?
    private var recordStart: Int64 = 0
    private var endObserver: NSObjectProtocol?
    init(project:Project,store:ProjectStore) {
        self.project = project; self.store = store
        observer = player.addPeriodicTimeObserver(forInterval:CMTime(value:1,timescale:30),queue:.main) { [weak self] time in
            Task { @MainActor in guard let self, self.playing else { return }; self.playhead = Int64(max(0,time.seconds)*1_000_000) }
        }
        endObserver = NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:nil,queue:.main) { [weak self] notification in
            Task { @MainActor in guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }; self.playing = false }
        }
        schedulePreview()
    }
    var clip: Clip? { project.clip(selected) }
    var canUndo: Bool { !undoStack.isEmpty }; var canRedo: Bool { !redoStack.isEmpty }
    func change(_ body:(inout Project)->Void) {
        let old = project; body(&project)
        guard old != project else { return }
        if gestureStart == nil {undoStack.append(old); if undoStack.count > 100 {undoStack.removeFirst()}}; redoStack = []
        persist(); revision += 1; schedulePreview()
    }
    func beginGesture() {if gestureStart == nil {gestureStart = project}}
    func endGesture() {if let old = gestureStart, old != project {undoStack.append(old)}; gestureStart = nil}
    func edit(_ body:(inout Clip)->Void) {
        guard let id = selected, project.track(id)?.locked != true else { return }
        change { $0.update(id,body) }
    }
    func undo() { guard let p = undoStack.popLast() else { return }; redoStack.append(project); project = p; persist(); revision += 1; schedulePreview() }
    func redo() { guard let p = redoStack.popLast() else { return }; undoStack.append(project); project = p; persist(); revision += 1; schedulePreview() }
    func persist() { do { try store.save(project) } catch { self.error = error.localizedDescription } }
    func schedulePreview() {
        rebuild?.cancel(); player.pause(); playing = false
        let snapshot = project
        rebuild = Task {
            do {
                try await Task.sleep(nanoseconds:160_000_000)
                guard snapshot.durationUs > 0 else { player.replaceCurrentItem(with:nil); return }
                let built = try await CompositionFactory.build(snapshot)
                try Task.checkCancellation()
                player.replaceCurrentItem(with:built.playerItem()); seek(min(playhead,snapshot.durationUs))
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    func seek(_ time:Int64) { playhead = clamp(time,0,project.durationUs); player.seek(to:mediaTime(playhead),toleranceBefore:.zero,toleranceAfter:.zero) }
    func play() {
        if playing { player.pause(); playing = false }
        else { if playhead >= project.durationUs { seek(0) }; player.play(); playing = true }
    }
    func close() { if recording {toggleRecording()}; rebuild?.cancel(); player.pause(); persist(); if let observer { player.removeTimeObserver(observer); self.observer = nil }; if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }; recorder?.stop() }
    func split() { guard let id = selected ?? project.tracks[project.mainIndex].clips.first(where: { $0.contains(playhead) })?.id else { return }; change { selected = $0.split(id,at:playhead) ?? id } }
    func delete() { guard let id = selected, project.track(id)?.locked != true else { return }; change { $0.delete(id) }; selected = nil }
    func addText(_ role:String,content:String = "Text") {
        var style = TextStyle(); style.text = content; style.role = role
        let c = Clip(startUs:playhead,transform:Transform(cy:role == "Subtitle" ? 0.86:0.5),text:style)
        change { $0.place(c,kind:.text) }; selected = c.id
    }
    func ingest(_ urls:[URL],kind:TrackKind,replace:Bool = false,subtitles:Bool = false) {
        busy = true
        Task {
            defer { busy = false }
            do {
                if subtitles {
                    for url in urls {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let cues = Subtitles.parse(try String(contentsOf:url,encoding:.utf8),filename:url.lastPathComponent)
                        guard !cues.isEmpty else { throw MediaError.invalid }; change { $0.addSubtitles(cues) }
                    }
                } else {
                    var assets: [MediaAsset] = []
                    for url in urls { assets.append(try await ProjectStore.ingest(url)) }
                    imported(assets,kind:kind,replace:replace)
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func imported(_ assets:[MediaAsset],kind:TrackKind,replace:Bool = false) {
        if replace, let a = assets.first, let id = selected {
            change { p in
                p.assets.append(a); p.update(id) { c in c.assetID = a.id; c.srcInUs = 0; c.srcOutUs = a.type == .image ? max(minimumClip,c.durationUs):a.durationUs; c.speed = 1 }
            }
        } else { change { $0.add(assets,kind:kind,at:playhead) } }
    }
    func extractAudio() {
        guard let c = clip, project.asset(c.assetID)?.hasAudio == true else { return }
        var audio = c; audio.id = newID(); audio.audioOnly = true; audio.transitionIn = nil; audio.keyframes = []
        change { $0.update(c.id) { $0.volume = 0 }; $0.place(audio,kind:.audio) }; selected = audio.id
    }
    func saveAudio() {
        guard let c = clip, let media = project.asset(c.assetID), media.hasAudio else {return}
        busy = true
        Task {
            defer {busy = false}
            do {
                var audio = c; audio.startUs = 0; audio.audioOnly = true; audio.transitionIn = nil
                var p = Project(name:"Audio",canvas:project.canvas,assets:[media]); p.tracks.append(Track(kind:.audio,clips:[audio]))
                let built = try await CompositionFactory.build(p)
                guard let session = AVAssetExportSession(asset:built.asset,presetName:AVAssetExportPresetAppleM4A) else {throw MediaError.export}
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("FrameNova-"+newID()+".m4a")
                session.outputURL = url; session.outputFileType = .m4a; session.audioMix = built.audio
                await session.export()
                guard session.status == .completed else {throw session.error ?? MediaError.export}
                shareURL = url
            } catch {self.error = error.localizedDescription}
        }
    }
    func freeze() {
        guard let c = clip ?? project.tracks[project.mainIndex].clips.first(where: { $0.contains(playhead) }), let media = project.asset(c.assetID), media.type == .video else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let generator = AVAssetImageGenerator(asset:AVURLAsset(url:ProjectStore.mediaURL(media.path))); generator.appliesPreferredTrackTransform = true
                let result = try await generator.image(at:mediaTime(c.sourceTime(at:playhead)))
                guard let data = UIImage(cgImage:result.image).pngData() else { throw MediaError.invalid }
                let path = newID()+".png"; try data.write(to:ProjectStore.mediaURL(path))
                let a = MediaAsset(path:path,type:.image,name:"Freeze frame",durationUs:2_000_000,width:result.image.width,height:result.image.height)
                change { p in
                    p.assets.append(a); var still = c; still.id = newID(); still.assetID = a.id; still.srcInUs = 0; still.srcOutUs = 2_000_000; still.speed = 1; still.keyframes = []; still.transitionIn = nil
                    if p.track(c.id)?.kind == .main { let second = p.split(c.id,at:playhead); p.insertMain([still],at:second != nil ? playhead:c.endUs) }
                    else { still.startUs = playhead; p.place(still,kind:.overlay) }
                }
            } catch { self.error = error.localizedDescription }
        }
    }
    func toggleRecording() {
        if recording {
            recorder?.stop(); recording = false
            guard let url = recorder?.url else { return }; recorder = nil
            Task { do { let a = try await ProjectStore.ingest(url); change { $0.add([a],kind:.audio,at:recordStart) }; try? FileManager.default.removeItem(at:url) } catch { self.error = error.localizedDescription } }
            return
        }
        Task {
            let granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning:$0) } }
            guard granted else { error = "Allow microphone access in Settings to record a voiceover."; return }
            do {
                player.pause(); playing = false
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.default,options:[.defaultToSpeaker,.allowBluetooth])
                try AVAudioSession.sharedInstance().setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(newID()+".m4a")
                recorder = try AVAudioRecorder(url:url,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:128000]); recordStart = playhead
                recording = recorder?.record() == true
            } catch { self.error = error.localizedDescription }
        }
    }
}
