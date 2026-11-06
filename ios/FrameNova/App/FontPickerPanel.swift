import SwiftUI
import CoreText

private struct BundledFont:Decodable,Identifiable {let id:String;let name:String;let group:String;let file:String}
struct FontPickerPanel:View {
    @ObservedObject var model:EditorModel
    private var fonts:[BundledFont] {Bundle.main.url(forResource:"BundledFonts",withExtension:"json").flatMap {try? Data(contentsOf:$0)}.flatMap {try? JSONDecoder().decode([BundledFont].self,from:$0)} ?? []}
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            group("System")
            choice("System Sans",id:"system");choice("System Serif",id:"system_serif");choice("System Mono",id:"system_mono")
            ForEach(["English","Art & display"],id:\.self) {name in
                group(name)
                ForEach(fonts.filter {$0.group == name}) {font in
                    if let id = postscript(font.file) {choice(font.name,id:id)}
                }
            }
            group("繁體中文 (download once)")
            DownloadFontList {name in model.edit {$0.text?.fontID = name}}
        }
    }
    private func group(_ title:String) -> some View {Text(loc(title)).font(.system(size:12)).foregroundStyle(Palette.dim).padding(.top,6).padding(.bottom,2)}
    private func postscript(_ file:String)->String? {
        guard let url = Bundle.main.url(forResource:file,withExtension:"ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],let descriptor = descriptors.first else {return nil}
        return CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String
    }
    private func choice(_ name:String,id:String)->some View {
        let system = id.hasPrefix("system"),selected = model.clip?.text?.fontID == id
        return Button {model.edit {$0.text?.fontID = id}} label:{HStack {
            Text(system ? loc(name) : name).font(system ? .system(size:16):.custom(id,size:16)).foregroundStyle(Palette.text)
            Spacer();Text(system && id != "system_mono" ? "Aa 字":"Aa").font(system ? .system(size:16):.custom(id,size:16)).foregroundStyle(Palette.dim)
        }.padding(.horizontal,10).padding(.vertical,8).background(selected ? Palette.accentSoft:.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle())}.buttonStyle(.plain)
    }
}
