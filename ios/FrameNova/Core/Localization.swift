import Foundation

/// The language chosen in Settings: the device's own, English or Traditional Chinese. A change shows at once: strings
/// looked up with `loc` and `localized` follow it, and the root view gives SwiftUI the matching locale.
enum AppLanguage {
    static let storageKey = "appLanguage"
    static let system = "system",english = "en",traditionalChinese = "zh-Hant"
    static let all = [system,english,traditionalChinese]
    static func normalized(_ tag:String?) -> String {tag.flatMap {all.contains($0) ? $0:nil} ?? system}
    static var current:String {normalized(UserDefaults.standard.string(forKey:storageKey))}
    static func locale(for tag:String) -> Locale {normalized(tag) == system ? .autoupdatingCurrent : Locale(identifier:normalized(tag))}
    /// Where strings come from for `tag`: nil is the English text itself (the keys), the main bundle is the device's language.
    static func bundle(for tag:String) -> Bundle? {
        switch normalized(tag) {
        case system: return .main
        case english: return nil
        case let other: return Bundle.main.path(forResource:other,ofType:"lproj").flatMap {Bundle(path:$0)}
        }
    }
}

/// Looks up a user-visible string that is chosen or built at run time (a variable, a conditional or a table entry).
/// SwiftUI localises string literals by itself; everything else goes through here. Without a translation the
/// key itself is returned, so the English text is the key. `english` is for keys that differ from their English text.
func loc(_ key:String,_ english:String? = nil) -> String {
    guard let bundle = AppLanguage.bundle(for:AppLanguage.current) else {return english ?? key}
    return bundle.localizedString(forKey:key,value:english,table:nil)
}

/// A string with values in it, written like `String(localized:)`: "Imported \(count) files". Its key is the text with a
/// placeholder in place of each value, which is how the translations are keyed.
struct LocalizedText:ExpressibleByStringInterpolation {
    var key:String
    var arguments:[CVarArg]
    init(stringLiteral value:String) {key = value.replacingOccurrences(of:"%",with:"%%");arguments = []}
    init(stringInterpolation:Interpolation) {key = stringInterpolation.key;arguments = stringInterpolation.arguments}
    struct Interpolation:StringInterpolationProtocol {
        var key = "",arguments:[CVarArg] = []
        init(literalCapacity:Int,interpolationCount:Int) {}
        mutating func appendLiteral(_ literal:String) {key += literal.replacingOccurrences(of:"%",with:"%%")}
        mutating func appendInterpolation(_ value:String) {key += "%@";arguments.append(value)}
        mutating func appendInterpolation(_ value:Int) {key += "%lld";arguments.append(value)}
    }
}
func localized(_ text:LocalizedText) -> String {
    let format = loc(text.key)
    return text.arguments.isEmpty ? format.replacingOccurrences(of:"%%",with:"%") : String(format:format,arguments:text.arguments)
}

/// The name of a colour filter. "Fade" is also a transition, with another Chinese name, so the filter has its own key.
func filterName(_ id:String?) -> String {
    guard let id else {return loc("None")}
    if id == "fade" {return loc("Fade filter","Fade")}
    return FilterCube.names[id].map {loc($0)} ?? id
}
