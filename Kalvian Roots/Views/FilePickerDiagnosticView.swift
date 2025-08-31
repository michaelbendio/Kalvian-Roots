//
//  Simple File Picker Diagnostic Test
//  No SwiftUI fileImporter - just NSOpenPanel testing
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

struct FilePickerDiagnosticView: View {
    @State private var result = "No test run yet"
    
    #if os(iOS)
    @State private var showingPicker = false
    @State private var pickedURL: URL?
    #endif
    
    var body: some View {
        VStack(spacing: 20) {
            Text("File Picker Diagnostic")
                .font(.title)
            
            ScrollView {
                Text(result)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .frame(minHeight: 200)
            }
            
            #if os(macOS)
            // MARK: macOS Buttons
            Button("Test NSOpenPanel (macOS Native)") {
                testNSOpenPanel()
            }
            .buttonStyle(.borderedProminent)
            
            Button("Test Simple Panel") {
                testSimplePanel()
            }
            .buttonStyle(.bordered)
            
            Button("Test File Search") {
                testFileSearch()
            }
            .buttonStyle(.bordered)
            #endif
            
            #if os(iOS)
            // MARK: iOS/iPadOS Button and Document Picker Sheet
            Button("Test UIDocumentPicker (iOS/iPadOS)") {
                showingPicker = true
            }
            .buttonStyle(.borderedProminent)
            .sheet(isPresented: $showingPicker) {
                DocumentPickerView(urlPicked: { url in
                    pickedURL = url
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        result = "Picked: \(url.lastPathComponent)\n" + content
                    } else {
                        result = "Picked: \(url.lastPathComponent)\nUnable to read file content."
                    }
                })
            }
            
            Button("Test File Search") {
                testFileSearch()
            }
            .buttonStyle(.bordered)
            #endif
            
            Button("Clear Results") {
                result = "Results cleared"
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
    
    #if os(macOS)
    private func testNSOpenPanel() {
        print("🧪 Starting NSOpenPanel diagnostic test")
        result = "🧪 Starting NSOpenPanel test...\n"
        
        // Test on main thread
        let panel = NSOpenPanel()
        panel.title = "Diagnostic Test - Select JuuretKälviällä.roots"
        panel.message = "This test allows ANY file type - your .roots file should NOT be grayed out"
        
        // FIXED: Don't restrict file types at all for testing
        panel.allowedContentTypes = []  // Empty = allow all types
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        result += "🧪 About to show NSOpenPanel (ALL file types allowed)...\n"
        print("🧪 About to show NSOpenPanel")
        
        let response = panel.runModal()
        
        result += "🧪 NSOpenPanel response: \(response.rawValue)\n"
        result += "🧪 Expected OK value: \(NSApplication.ModalResponse.OK.rawValue)\n"
        
        print("🧪 NSOpenPanel response: \(response.rawValue)")
        print("🧪 NSOpenPanel.OK.rawValue: \(NSApplication.ModalResponse.OK.rawValue)")
        
        if response == .OK {
            if let url = panel.url {
                result += "🧪 SUCCESS: Selected file: \(url.lastPathComponent)\n"
                result += "🧪 Full path: \(url.path)\n"
                print("🧪 SUCCESS: Selected file: \(url.path)")
                
                // Test file access
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                result += "🧪 Security scoped access: \(accessing ? "SUCCESS" : "FAILED")\n"
                
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let preview = String(content.prefix(100))
                    result += "🧪 ✅ FILE READ SUCCESS!\n"
                    result += "🧪 File size: \(content.count) characters\n"
                    result += "🧪 Preview: \(preview)\n"
                    print("🧪 File read successfully: \(content.count) characters")
                } catch {
                    result += "🧪 ❌ FILE READ FAILED: \(error.localizedDescription)\n"
                    print("🧪 File read failed: \(error)")
                }
            } else {
                result += "🧪 ❌ ERROR: NSOpenPanel returned OK but no URL!\n"
                print("🧪 ERROR: NSOpenPanel returned OK but no URL")
            }
        } else if response == .cancel {
            result += "🧪 User cancelled NSOpenPanel\n"
            print("🧪 User cancelled NSOpenPanel")
        } else {
            result += "🧪 ❌ Unknown response: \(response.rawValue)\n"
            print("🧪 Unknown NSOpenPanel response: \(response.rawValue)")
        }
    }
    
    private func testSimplePanel() {
        result = "🔧 Testing simple panel...\n"
        
        let panel = NSOpenPanel()
        panel.title = "Simple Test"
        
        let response = panel.runModal()
        
        result += "Simple panel response: \(response.rawValue)\n"
        if response == .OK {
            result += "Simple panel URL: \(panel.url?.path ?? "nil")\n"
        }
    }
    #endif
    
    private func testFileSearch() {
        result = "📁 Searching for JuuretKälviällä.roots...\n"
        
        #if os(macOS)
        let homeURL = Foundation.FileManager.default.homeDirectoryForCurrentUser
        let searchPaths = [
            ("Desktop", homeURL.appendingPathComponent("Desktop")),
            ("Documents", homeURL.appendingPathComponent("Documents")),
            ("Downloads", homeURL.appendingPathComponent("Downloads")),
            ("iCloud Documents", getiCloudDocumentsURL()),
            ("Home", homeURL)
        ]
        
        for (name, url) in searchPaths {
            guard let url = url else { continue }
            let targetFile = url.appendingPathComponent("JuuretKälviällä.roots")
            
            if Foundation.FileManager.default.fileExists(atPath: targetFile.path) {
                result += "✅ FOUND at \(name): \(targetFile.path)\n"
                
                // Test if we can read it
                do {
                    let content = try String(contentsOf: targetFile, encoding: .utf8)
                    result += "   📖 Can read: \(content.count) characters\n"
                } catch {
                    result += "   ❌ Cannot read: \(error.localizedDescription)\n"
                }
            } else {
                result += "❌ Not found at \(name)\n"
            }
        }
        #elseif os(iOS)
        // iOS sandbox Documents folder search
        let fileManager = Foundation.FileManager.default
        if let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let targetFile = docDir.appendingPathComponent("JuuretKälviällä.roots")
            if fileManager.fileExists(atPath: targetFile.path) {
                result += "✅ FOUND in Documents: \(targetFile.path)\n"
                do {
                    let content = try String(contentsOf: targetFile, encoding: .utf8)
                    result += "   📖 Can read: \(content.count) characters\n"
                } catch {
                    result += "   ❌ Cannot read: \(error.localizedDescription)\n"
                }
            } else {
                result += "❌ Not found in Documents\n"
            }
        } else {
            result += "❌ Could not access Documents directory\n"
        }
        #endif
    }
    
    #if os(macOS)
    private func getiCloudDocumentsURL() -> URL? {
        guard let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return iCloudURL.appendingPathComponent("Documents")
    }
    #endif
}

#if os(iOS)
// MARK: - DocumentPickerView for iOS/iPadOS

struct DocumentPickerView: UIViewControllerRepresentable {
    var urlPicked: (URL) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [UTType.data, UTType.content, UTType.item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // no update needed
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerView
        
        init(_ parent: DocumentPickerView) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let first = urls.first {
                parent.urlPicked(first)
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Optionally handle cancellation
        }
    }
}
#endif
