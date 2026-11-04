import SwiftUI
import UniformTypeIdentifiers
private struct MediaFileImporter:ViewModifier {
    @Binding var presented:Bool
    let types:[UTType]
    let multiple:Bool
    let completion:(Result<[URL],Error>)->Void
    func body(content:Content)->some View {
        content.fileImporter(isPresented:$presented,allowedContentTypes:types,allowsMultipleSelection:multiple) {result in
            switch result {
            case .success(let urls):AppLog.record("File picker delivered \(urls.count) files")
            case .failure(let error):AppLog.record("File picker failed: \(error.localizedDescription)")
            }
            completion(result)
        }
    }
}
extension View {
    func mediaFileImporter(isPresented:Binding<Bool>,allowedContentTypes:[UTType],allowsMultipleSelection:Bool,onCompletion:@escaping (Result<[URL],Error>)->Void)->some View {
        modifier(MediaFileImporter(presented:isPresented,types:allowedContentTypes,multiple:allowsMultipleSelection,completion:onCompletion))
    }
}
