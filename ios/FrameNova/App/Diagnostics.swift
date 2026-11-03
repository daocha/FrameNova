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
    static var text:String {(try? String(contentsOf:url,encoding:.utf8)) ?? "No logs recorded."}
}
