import SwiftUI

extension Font {
    /// A fixed-size font that is 4 points larger on the Mac, where the small sizes used on the phone are too small to read
    /// at desktop distance. iPhone and iPad keep the size they pass.
    static func small(_ size:CGFloat,weight:Font.Weight = .regular)->Font {
        #if targetEnvironment(macCatalyst)
        .system(size:size+4,weight:weight)
        #else
        .system(size:size,weight:weight)
        #endif
    }
}
