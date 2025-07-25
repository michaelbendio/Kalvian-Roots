//
//  Simple File Picker Diagnostic Test
//  No SwiftUI fileImporter - just NSOpenPanel testing
//

import SwiftUI
import UniformTypeIdentifiers

struct FilePickerDiagnosticView: View {
    @State private var result = "No test run yet"
    
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
            
            Button("Clear Results") {
                result = "Results cleared"
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
    }
    
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
    
    private func testFileSearch() {
        result = "📁 Searching for JuuretKälviällä.roots...\n"
        
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
    }
    
    private func getiCloudDocumentsURL() -> URL? {
        guard let iCloudURL = Foundation.FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return iCloudURL.appendingPathComponent("Documents")
    }
}
