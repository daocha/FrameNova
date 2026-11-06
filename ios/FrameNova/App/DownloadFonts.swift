import SwiftUI
import CoreText

struct DownloadableFont: Codable, Identifiable {
    let id:String
    let name:String
    let path:String
    let sizeMB:Int
}
@MainActor final class DownloadFonts: ObservableObject {
    @Published var busy:String?
    @Published var error:String?
    let catalog:[DownloadableFont]
    static var folder:URL {ProjectStore.root.appendingPathComponent("Fonts",isDirectory:true)}
    init() {
        catalog = Bundle.main.url(forResource:"DownloadFonts",withExtension:"json").flatMap {try? Data(contentsOf:$0)}.flatMap {try? JSONDecoder().decode([DownloadableFont].self,from:$0)} ?? []
    }
    func select(_ font:DownloadableFont,completion:@escaping (String)->Void) {
        guard busy == nil else {return}; busy = font.id
        Task {
            defer {busy = nil}
            do {
                try FileManager.default.createDirectory(at:Self.folder,withIntermediateDirectories:true)
                let local = Self.folder.appendingPathComponent(font.id+".ttf")
                if !FileManager.default.fileExists(atPath:local.path) {
                    let url = URL(string:"https://raw.githubusercontent.com/google/fonts/main/ofl/"+font.path)!
                    let (temporary,response) = try await URLSession.shared.download(from:url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {throw MediaError.invalid}
                    guard CTFontManagerCreateFontDescriptorsFromURL(temporary as CFURL) != nil else {throw MediaError.invalid}
                    try FileManager.default.moveItem(at:temporary,to:local)
                }
                CTFontManagerRegisterFontsForURL(local as CFURL,.process,nil)
                guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(local as CFURL) as? [CTFontDescriptor], let first = descriptors.first,
                      let name = CTFontDescriptorCopyAttribute(first,kCTFontNameAttribute) as? String else {throw MediaError.invalid}
                completion(name)
            } catch {self.error = error.localizedDescription}
        }
    }
}
struct DownloadFontList:View {
    @StateObject private var fonts = DownloadFonts()
    var selected:(String)->Void
    private func available(_ font:DownloadableFont) -> Bool {FileManager.default.fileExists(atPath:DownloadFonts.folder.appendingPathComponent(font.id+".ttf").path)}
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            ForEach(fonts.catalog) {font in
                Button {fonts.select(font,completion:selected)} label:{HStack(spacing:8) {
                    Text(font.name).font(.system(size:16)).foregroundStyle(Palette.text)
                    Spacer()
                    if fonts.busy == font.id {ProgressView().controlSize(.small)}
                    else if !available(font) {Text("\(font.sizeMB) MB").font(.system(size:11)).foregroundStyle(Palette.dim);Image(systemName:"arrow.down.to.line").font(.system(size:14)).foregroundStyle(Palette.dim)}
                }.padding(.horizontal,10).padding(.vertical,8).contentShape(Rectangle())}.buttonStyle(.plain).disabled(fonts.busy != nil)
            }
            if let error = fonts.error {Text(error).foregroundStyle(Palette.danger).font(.system(size:12))}
        }
    }
}
