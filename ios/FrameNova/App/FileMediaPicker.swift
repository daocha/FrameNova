import SwiftUI
import UniformTypeIdentifiers
private struct MediaFileImporter:ViewModifier {
    @Binding var presented:Bool
    let types:[UTType]
    let multiple:Bool
    let completion:(Result<[URL],Error>)->Void
    let cancellation:()->Void
    func body(content:Content)->some View {
        content.fileImporter(isPresented:$presented,allowedContentTypes:types,allowsMultipleSelection:multiple,onCompletion:{result in
            switch result {
            case .success(let urls):AppLog.record("File picker delivered \(urls.count) files")
            case .failure(let error):AppLog.record("File picker failed: \(error.localizedDescription)")
            }
            completion(result)
        },onCancellation:{
            AppLog.record("File picker cancelled without delivering files")
            cancellation()
        })
        .onChange(of:presented) {_,open in if open {AppLog.record("File picker requested")}}
    }
}
extension View {
    func mediaFileImporter(isPresented:Binding<Bool>,allowedContentTypes:[UTType],allowsMultipleSelection:Bool,onCancellation:@escaping ()->Void = {},onCompletion:@escaping (Result<[URL],Error>)->Void)->some View {
        modifier(MediaFileImporter(presented:isPresented,types:allowedContentTypes,multiple:allowsMultipleSelection,completion:onCompletion,cancellation:onCancellation))
    }
}
