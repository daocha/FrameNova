import SwiftUI
import CoreText

private struct BundledFont:Decodable,Identifiable {let id:String;let name:String;let group:String;let file:String}
struct FontPickerPanel:View {
    @ObservedObject var model:EditorModel
    private var fonts:[BundledFont] {Bundle.main.url(forResource:"BundledFonts",withExtension:"json").flatMap {try? Data(contentsOf:$0)}.flatMap {try? JSONDecoder().decode([BundledFont].self,from:$0)} ?? []}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("System").font(.caption).foregroundStyle(Palette.dim)
            choice("System Sans",id:"system");choice("System Serif",id:"system_serif");choice("System Mono",id:"system_mono")
            ForEach(["English","Art & display"],id:\.self) {group in
                Text(group).font(.caption).foregroundStyle(Palette.dim).padding(.top,8)
                ForEach(fonts.filter {$0.group == group}) {font in
                    if let id = postscript(font.file) {choice(font.name,id:id)}
                }
            }
            DownloadFontList {name in model.edit {$0.text?.fontID = name}}
        }
    }
    private func postscript(_ file:String)->String? {
        guard let url = Bundle.main.url(forResource:file,withExtension:"ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],let descriptor = descriptors.first else {return nil}
        return CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String
    }
    private func choice(_ name:String,id:String)->some View {
        Button {model.edit {$0.text?.fontID = id}} label:{HStack {
            Text(name).font(id.hasPrefix("system") ? .system(size:16):.custom(id,size:16)).foregroundStyle(.white)
            Spacer();Text("Aa").font(id.hasPrefix("system") ? .system(size:16):.custom(id,size:16)).foregroundStyle(Palette.dim)
            if model.clip?.text?.fontID == id {Image(systemName:"checkmark").foregroundStyle(Palette.accent)}
        }.padding(10).background(model.clip?.text?.fontID == id ? Palette.accent.opacity(0.18):Palette.surface2,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain)
    }
}
