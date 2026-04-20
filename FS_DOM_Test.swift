import AppKit
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow?
    var webView: WKWebView?
    var keyMonitor: Any?

    private let targetURL = URL(string: "https://www.familysearch.org/en/tree/person/details/K1K9-QMK")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("applicationDidFinishLaunching")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "FamilySearch DOM Test"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.charactersIgnoringModifiers == "q" {
                self.runExtraction()
                return nil
            }
            return event
        }

        print("Window visible:", window.isVisible)
        print("Loading \(targetURL.absoluteString)")
        webView.load(URLRequest(url: targetURL))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Page loaded")
        print("When the correct FamilySearch person page is visible, click once in the window and press 'q' to extract.")
    }

    func runExtraction() {
        print("\nRunning extraction...\n")
        extract()
    }

    func extract() {
        guard let webView else { return }

        let js = """
        (function () {
            function clean(text) {
                return (text || "").replace(/\\s+/g, " ").trim();
            }

            const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5'));
            const familyHeading = headings.find(h => clean(h.textContent) === 'Family Members');

            if (!familyHeading) {
                return { found: false, reason: 'Family Members heading not found' };
            }

            const familySection =
                familyHeading.closest('div[all]') ||
                familyHeading.parentElement;

            if (!familySection) {
                return { found: false, reason: 'Family Members container not found' };
            }

            const text = familySection.innerText || "";

            const spousesStart = text.indexOf("Spouses and Children");
            if (spousesStart === -1) {
                return { found: false, reason: '"Spouses and Children" not found' };
            }

            const childrenStart = text.indexOf("Children (", spousesStart);
            if (childrenStart === -1) {
                return { found: false, reason: 'Children block not found' };
            }

            let end = text.indexOf("ADD CHILD", childrenStart);
            if (end === -1) end = text.indexOf("Parents and Siblings", childrenStart);
            if (end === -1) end = text.length;

            const childrenText = text.slice(childrenStart, end);

            const lines = childrenText
                .split("\\n")
                .map(s => clean(s))
                .filter(Boolean);

            const children = [];
            let i = 0;

            if (lines[0] && /^Children \\(\\d+\\)$/.test(lines[0])) {
                i = 1;
            }

            while (i < lines.length) {
                const name = lines[i];
                if (!name || name.startsWith("ADD ")) break;

                const sex = lines[i + 1] || "";
                const lifespan = lines[i + 2] || "";
                const pid = lines[i + 4] || "";

                const looksLikeSex = /^(Male|Female|Unknown)$/i.test(sex);
                const looksLikePid = /^[A-Z0-9-]{4,}$/i.test(pid);

                if (!looksLikeSex || !looksLikePid) {
                    i += 1;
                    continue;
                }

                children.push({
                    name,
                    sex,
                    lifespan,
                    id: pid
                });

                i += 5;
            }

            return {
                found: true,
                count: children.length,
                children
            };
        })();
        """

        webView.evaluateJavaScript(js) { result, error in
            if let error {
                print("JS Error: \(error)")
                return
            }

            print("\n=== EXTRACTION RESULT ===")
            print(result ?? "nil")
        }
    }
}

@main
struct FS_DOM_Test {
    static func main() {
        print("main() starting")

        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.setActivationPolicy(.regular)
        app.delegate = delegate

        print("about to run app")
        app.run()
    }
}
