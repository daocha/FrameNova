import UIKit

enum TextFonts {
    static func font(_ style:TextStyle,size:CGFloat)->UIFont {
        var font:UIFont
        if style.fontID == "system_mono" {font = .monospacedSystemFont(ofSize:size,weight:style.bold ? .bold:.regular)}
        else if style.fontID == "system_serif",let descriptor = UIFont.systemFont(ofSize:size).fontDescriptor.withDesign(.serif) {font = UIFont(descriptor:descriptor,size:size)}
        else {font = style.fontID == "system" ? .systemFont(ofSize:size,weight:style.bold ? .bold:.regular):UIFont(name:style.fontID,size:size) ?? .systemFont(ofSize:size)}
        var traits:UIFontDescriptor.SymbolicTraits = []
        if style.bold {traits.insert(.traitBold)};if style.italic {traits.insert(.traitItalic)}
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {font = UIFont(descriptor:descriptor,size:size)}
        return font
    }
    static func layoutAttributes(_ style:TextStyle,size:CGFloat)->[NSAttributedString.Key:Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = style.alignment == "Left" ? .left:style.alignment == "Right" ? .right:.center
        paragraph.lineSpacing = size*(style.lineSpacing-1)
        return [.font:font(style,size:size),.paragraphStyle:paragraph,.kern:style.letterSpacing*size]
    }
}
