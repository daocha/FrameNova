import Foundation

/// Looks up a user-visible string that is chosen or built at run time (a variable, a conditional or a table entry).
/// SwiftUI localises string literals by itself; everything else goes through here. Without a translation the
/// key itself is returned, so the English text is the key. `english` is for keys that differ from their English text.
func loc(_ key:String,_ english:String? = nil) -> String {Bundle.main.localizedString(forKey:key,value:english,table:nil)}

/// The name of a colour filter. "Fade" is also a transition, with another Chinese name, so the filter has its own key.
func filterName(_ id:String?) -> String {
    guard let id else {return loc("None")}
    if id == "fade" {return loc("Fade filter","Fade")}
    return FilterCube.names[id].map {loc($0)} ?? id
}
