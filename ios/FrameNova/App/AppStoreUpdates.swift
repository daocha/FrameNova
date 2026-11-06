import Foundation

/// Looks FrameNova up on the App Store and says whether a newer version is out. A build that is not on the App Store
/// (a development or TestFlight build) is not found, and sees no update.
@MainActor final class AppStoreUpdates: ObservableObject {
    enum Phase: Equatable {case idle,checking,current,available(String),notListed,failed(String)}
    @Published private(set) var phase = Phase.idle
    private(set) var storeURL: URL?
    var hasUpdate: Bool {if case .available = phase {return true};return false}
    var version: String {if case .available(let version) = phase {return version};return ""}

    private struct Lookup: Decodable {
        struct Listing: Decodable {let version: String;let trackViewUrl: String?}
        let results: [Listing]
    }
    /// Whether `latest` is a later dotted version than `current`.
    nonisolated static func isNewer(_ latest: String,than current: String) -> Bool {
        let a = latest.split(separator:".").map {Int($0) ?? 0},b = current.split(separator:".").map {Int($0) ?? 0}
        for index in 0..<max(a.count,b.count) {
            let x = index < a.count ? a[index]:0,y = index < b.count ? b[index]:0
            if x != y {return x > y}
        }
        return false
    }
    /// A manual check reports a failure; the check at launch stays quiet.
    func check(manual: Bool = false) async {
        guard phase != .checking else {return}
        guard let bundleID = Bundle.main.bundleIdentifier,var components = URLComponents(string:"https://itunes.apple.com/lookup") else {return}
        components.queryItems = [URLQueryItem(name:"bundleId",value:bundleID)]
        guard let url = components.url else {return}
        let before = phase
        phase = .checking
        do {
            let (data,response) = try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {throw URLError(.badServerResponse)}
            guard let listing = try JSONDecoder().decode(Lookup.self,from:data).results.first else {phase = .notListed;return}
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            if Self.isNewer(listing.version,than:current) {
                storeURL = listing.trackViewUrl.flatMap {URL(string:$0)}
                phase = .available(listing.version)
            } else {phase = .current}
        } catch {
            phase = manual ? .failed(error.localizedDescription):before == .checking ? .idle:before
        }
    }
}
