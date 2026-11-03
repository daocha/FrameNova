import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct FileMediaPicker:UIViewControllerRepresentable {
    let types:[UTType]
    let multiple:Bool
    let onPick:([URL])->Void
    let onCancel:()->Void
    func makeCoordinator()->Coordinator {Coordinator(onPick:onPick,onCancel:onCancel)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes:types,asCopy:true)
        picker.allowsMultipleSelection = multiple;picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {
        context.coordinator.onPick = onPick;context.coordinator.onCancel = onCancel
    }
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        var onPick:([URL])->Void
        var onCancel:()->Void
        init(onPick:@escaping ([URL])->Void,onCancel:@escaping ()->Void) {self.onPick = onPick;self.onCancel = onCancel}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {onPick(urls)}
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {onCancel()}
    }
}

private struct MediaFileImporter:ViewModifier {
    @Binding var presented:Bool
    let types:[UTType]
    let multiple:Bool
    let completion:(Result<[URL],Error>)->Void
    func body(content:Content)->some View {
        #if targetEnvironment(macCatalyst)
        content.sheet(isPresented:$presented) {
            FileMediaPicker(types:types,multiple:multiple,onPick:{urls in
                AppLog.record("File picker delivered \(urls.count) files")
                completion(.success(urls));presented = false
            },onCancel:{presented = false})
        }
        #else
        content.fileImporter(isPresented:$presented,allowedContentTypes:types,allowsMultipleSelection:multiple,onCompletion:completion)
        #endif
    }
}
extension View {
    func mediaFileImporter(isPresented:Binding<Bool>,allowedContentTypes:[UTType],allowsMultipleSelection:Bool,onCompletion:@escaping (Result<[URL],Error>)->Void)->some View {
        modifier(MediaFileImporter(presented:isPresented,types:allowedContentTypes,multiple:allowsMultipleSelection,completion:onCompletion))
    }
}
