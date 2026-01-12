//
//  DocumentPickerView.swift
//  Kalvian Roots
//
//  Created by Michael Bendio on 1/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
struct DocumentPickerView: View {
    let fileManager: RootsFileManager
    @State private var showingPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Select File")
                .font(.largeTitle)
            
            Text("Please select JuuretKälviällä.roots from iCloud Drive/Documents")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding()
            
            Button("Select File") {
                showingPicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .sheet(isPresented: $showingPicker) {
            DocumentPicker(fileManager: fileManager)
        }
        .onAppear {
            // Auto-show picker on first appearance
            showingPicker = true
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let fileManager: RootsFileManager
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType(filenameExtension: "roots") ?? .plainText],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(fileManager: fileManager, dismiss: dismiss)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let fileManager: RootsFileManager
        let dismiss: DismissAction
        
        init(fileManager: RootsFileManager, dismiss: DismissAction) {
            self.fileManager = fileManager
            self.dismiss = dismiss
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            Task {
                do {
                    _ = try await fileManager.loadFileFromPicker(url)
                    dismiss()
                } catch {
                    await MainActor.run {
                        fileManager.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            dismiss()
        }
    }
}
#endif
