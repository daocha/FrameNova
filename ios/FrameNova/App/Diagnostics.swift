import Foundation

enum AppLog {
    private static let lock = NSLock()
    static var url:URL {ProjectStore.root.appendingPathComponent("diagnostics.log")}
    static func record(_ message:String) {
        lock.lock(); defer {lock.unlock()}
        var value = (try? String(contentsOf:url,encoding:.utf8)) ?? ""
        value += Date().formatted(.iso8601)+" "+message+"\n"
        if value.count > 200_000 {value = String(value.suffix(150_000))}
        try? value.write(to:url,atomically:true,encoding:.utf8)
    }
    /// A dated copy in the temporary folder, so the saved file has a recognisable name.
    static func exportCopy()->URL? {
        if !FileManager.default.fileExists(atPath:url.path) {record("Developer tools enabled")}
        let formatter = DateFormatter();formatter.dateFormat = "yyyyMMdd-HHmmss"
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("FrameNova-log-\(formatter.string(from:Date())).log")
        try? FileManager.default.removeItem(at:copy)
        do {try FileManager.default.copyItem(at:url,to:copy);return copy} catch {return nil}
    }
    static var text:String {(try? String(contentsOf:url,encoding:.utf8)) ?? "No logs recorded."}
}
