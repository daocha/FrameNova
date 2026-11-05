import Foundation

final class PreviewProjectState:@unchecked Sendable {
    private let lock = NSLock()
    private var snapshot:Project
    init(_ project:Project) {snapshot = project}
    var project:Project {lock.lock();defer {lock.unlock()};return snapshot}
    func update(_ project:Project) {lock.lock();snapshot = project;lock.unlock()}
}
