//
//  HTMLRenderer.swift
//  Kalvian Roots
//
//  Server-side HTML rendering for family display
//

#if os(macOS)
import Foundation

/**
 * HTML Renderer for server-rendered family pages
 */
struct HTMLRenderer {

    // MARK: - Landing Page

    static func renderLandingPage(error: String? = nil) -> String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Kalvian Roots</title>
            <style>
                \(cssStyles)
                .landing-container {
                    max-width: 600px;
                    margin: 100px auto;
                    padding: 40px;
                    background: white;
                    border-radius: 8px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                h1 {
                    color: #333;
                    margin-bottom: 30px;
                }
                .form-group {
                    margin-bottom: 20px;
                }
                label {
                    display: block;
                    margin-bottom: 8px;
                    color: #666;
                    font-weight: 500;
                }
                input[type="text"] {
                    width: 100%;
                    padding: 12px;
                    border: 2px solid #ddd;
                    border-radius: 4px;
                    font-size: 16px;
                    font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
                }
                input[type="text"]:focus {
                    outline: none;
                    border-color: #0066cc;
                }
                button {
                    background: #0066cc;
                    color: white;
                    border: none;
                    padding: 12px 30px;
                    border-radius: 4px;
                    font-size: 16px;
                    cursor: pointer;
                    font-weight: 500;
                }
                button:hover {
                    background: #0052a3;
                }
                .error-message {
                    color: #dc3545;
                    margin-top: 10px;
                    padding: 10px;
                    background: #fee;
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>
            <div class="landing-container">
                <h1>Kalvian Roots Browser</h1>
                <form method="GET" action="/family">
                    <div class="form-group">
                        <label for="family">Enter Family ID:</label>
                        <input type="text" id="family" name="id"
                               placeholder="e.g., KORPI 6"
                               required autofocus>
                        \(error == "invalid" ? """
                        <div class="error-message">
                            Invalid family ID. Please check and try again.
                        </div>
                        """ : "")
                    </div>
                    <button type="submit">Go</button>
                </form>
            </div>
        </body>
        </html>
        """
    }

    // MARK: - Family Display

    static func renderFamily(
        family: Family,
        network: FamilyNetwork?,
        homeId: String? = nil,
        citationText: String? = nil,
        sourceText: String? = nil,
        errorMessage: String? = nil
    ) -> String {
        let tokenizer = FamilyTokenizer()
        let tokens = tokenizer.tokenizeFamily(family: family, network: network)

        // Determine home and displayed IDs
        let displayedId = family.familyId
        let actualHomeId = homeId ?? displayedId
        
        // Generate navigation bar
        let navBar = renderNavigationBar(homeId: actualHomeId, displayedId: displayedId)
        
        // Generate family content with home parameter for links
        let familyHTML = renderTokens(tokens, familyId: displayedId, homeId: actualHomeId)
        let citationPanel = renderCitationPanel(citationText: citationText, errorMessage: errorMessage)
        let sourcePanel = renderSourcePanel(sourceText: sourceText)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(displayedId)) - Kalvian Roots</title>
            <style>
                \(cssStyles)
            </style>
        </head>
        <body>
            <div class="container">
                \(navBar)
                \(citationPanel)
                \(sourcePanel)
                <div class="family-content">
                    \(familyHTML)
                </div>
            </div>
            \(copyButtonScript)
            \(navigationScript)
        </body>
        </html>
        """
    }
    
    // MARK: - Navigation Bar
    
    private static func renderNavigationBar(homeId: String, displayedId: String) -> String {
        // Calculate navigation targets based on homeId
        let previousId = FamilyIDs.previousFamilyBefore(homeId)
        let nextId = FamilyIDs.nextFamilyAfter(homeId)
        let canGoPrevious = previousId != nil
        let canGoNext = nextId != nil
        let isViewingHome = (homeId == displayedId)
        
        // Generate button URLs
        let previousURL = previousId.map { "/family/\(urlEncode($0))" } ?? ""
        let homeURL = "/family/\(urlEncode(homeId))"
        let nextURL = nextId.map { "/family/\(urlEncode($0))" } ?? ""
        let reloadURL = "/family/\(urlEncode(homeId))?reload=1"
        let sourceURL = "/family/\(urlEncode(displayedId))/source" + (displayedId == homeId ? "" : "?home=\(urlEncode(homeId))")
        
        return """
        <div class="nav-bar">
            <div class="nav-buttons">
                <a href="\(previousURL)" class="nav-btn\(canGoPrevious ? "" : " disabled")" \(canGoPrevious ? "" : "onclick='return false;'")>←</a>
                <a href="\(homeURL)" class="nav-btn\(isViewingHome ? " disabled" : "")" \(isViewingHome ? "onclick='return false;'" : "")>⌂</a>
                <a href="\(nextURL)" class="nav-btn\(canGoNext ? "" : " disabled")" \(canGoNext ? "" : "onclick='return false;'")>→</a>
                <a href="\(reloadURL)" class="nav-btn">↺</a>
                <a href="\(sourceURL)" class="nav-btn" title="View source text">📄</a>
            </div>
            <form method="GET" action="/family" class="nav-form" onsubmit="showLoading(event)">
                <div class="input-wrapper">
                    <input type="text" id="familyInput" name="id" value="\(escapeHTML(homeId))" class="family-input" placeholder="Enter family ID..." required autocomplete="off">
                    <button type="button" class="clear-btn" onclick="clearInput()" style="display: none;">✕</button>
                </div>
            </form>
            <div class="loading-indicator" id="loadingIndicator" style="display: none;">
                <div class="spinner"></div>
                <span id="loadingText">Loading...</span>
            </div>
        </div>
        """
    }

    // MARK: - Token Rendering

    private static func renderTokens(_ tokens: [FamilyToken], familyId: String, homeId: String) -> String {
        var html = ""

        for token in tokens {
            switch token {
            case .text(let str):
                let renderedText = str
                    .replacingOccurrences(of: "as_child", with: "a child in")
                    .replacingOccurrences(of: "as_parent", with: "parents in")
                html += escapeHTML(renderedText)

            case .person(let name, let birthDate):
                // Preserve home parameter in citation links
                let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
                let params = buildQueryParams([
                    "name": name,
                    "birth": birthDate
                ])
                html += """
                <a href="/family/\(urlEncode(familyId))/cite?\(params)\(homeParam)"
                   class="person-link">\(escapeHTML(name))</a>
                """

            case .date(let date, let eventType, let person, let spouse1, let spouse2):
                // Preserve home parameter in HisKi links
                let homeParam = (familyId == homeId) ? "" : "&home=\(urlEncode(homeId))"
                
                if eventType == .marriage, let s1 = spouse1, let s2 = spouse2 {
                    // Marriage date
                    let params = buildQueryParams([
                        "spouse1": s1.name,
                        "birth1": s1.birthDate,
                        "spouse2": s2.name,
                        "birth2": s2.birthDate,
                        "event": "marriage",
                        "date": date
                    ])
                    html += """
                    <a href="/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
                       class="date-link">\(escapeHTML(date))</a>
                    """
                } else if let person = person {
                    // Birth or death date
                    let params = buildQueryParams([
                        "name": person.name,
                        "birth": person.birthDate,
                        "event": eventType.rawValue,
                        "date": date
                    ])
                    html += """
                    <a href="/family/\(urlEncode(familyId))/hiski?\(params)\(homeParam)"
                       class="date-link">\(escapeHTML(date))</a>
                    """
                } else {
                    // Non-clickable date
                    html += escapeHTML(date)
                }

            case .familyId(let id):
                if FamilyIDs.isValid(familyId: id) {
                    // Family reference links preserve home parameter
                    let homeParam = (id == homeId) ? "" : "?home=\(urlEncode(homeId))"
                    html += """
                    <a href="/family/\(urlEncode(id))\(homeParam)"
                       class="family-link">\(escapeHTML(id))</a>
                    """
                } else {
                    // Pseudo-family ID, not clickable
                    html += escapeHTML(id)
                }

            case .enhanced(let content):
                html += """
                        <span class="enhanced">\(escapeHTML(content))</span>
                        """

            case .symbol(let sym):
                html += """
                        <span class="symbol">\(escapeHTML(sym))</span>
                        """

            case .lineBreak:
                html += "<br>"

            case .sectionHeader(let title):
                html += """
                        <div class="section-header">\(escapeHTML(title))</div>
                        """
            }
        }

        return html
    }

    // MARK: - Citation Panel

    private static func renderCitationPanel(citationText: String? = nil, errorMessage: String? = nil) -> String {
        guard citationText != nil || errorMessage != nil else {
            return ""
        }

        if let error = errorMessage {
            return """
            <div class="error-panel">
                <div class="error-title">Error</div>
                <div class="error-message">\(escapeHTML(error))</div>
            </div>
            """
        }

        if let citation = citationText {
            return """
            <div class="citation-panel">
                <div class="citation-header">
                    <span class="citation-title">Citation</span>
                    <button id="copyBtn" class="copy-button" onclick="copyCitation()">Copy</button>
                </div>
                <textarea id="citationText" class="citation-textarea" spellcheck="false">\(escapeHTML(citation))</textarea>
                <div id="copyHint" class="copy-hint" style="display: none;">Press Cmd+C / Ctrl+C to copy</div>
            </div>
            """
        }

        return ""
    }

    // MARK: - Source Text Panel

    private static func renderSourcePanel(sourceText: String? = nil) -> String {
        guard let source = sourceText else {
            return ""
        }

        return """
        <div class="source-panel">
            <div class="source-header">
                <span class="source-title">📄 Source Text from JuuretKälviällä.roots</span>
            </div>
            <pre class="source-text">\(escapeHTML(source))</pre>
        </div>
        """
    }

    // MARK: - CSS Styles

    private static var cssStyles: String {
        return """
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .nav-bar {
            background: white;
            padding: 15px 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .nav-buttons {
            display: flex;
            gap: 8px;
        }
        .nav-btn {
            background: #0066cc;
            color: white;
            border: none;
            padding: 8px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 18px;
            text-decoration: none;
            display: inline-block;
            transition: background 0.2s;
        }
        .nav-btn:hover:not(.disabled) {
            background: #0052a3;
        }
        .nav-btn.disabled {
            background: #ccc;
            cursor: not-allowed;
            opacity: 0.6;
        }
        .nav-form {
            flex: 1;
            max-width: 400px;
        }
        .input-wrapper {
            position: relative;
            width: 100%;
        }
        .family-input {
            width: 100%;
            padding: 8px 32px 8px 12px;
            border: 2px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
        }
        .family-input:focus {
            outline: none;
            border-color: #0066cc;
        }
        .clear-btn {
            position: absolute;
            right: 6px;
            top: 50%;
            transform: translateY(-50%);
            background: #e0e0e0;
            border: none;
            color: #666;
            font-size: 16px;
            line-height: 1;
            cursor: pointer;
            padding: 0;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            display: none;
            align-items: center;
            justify-content: center;
        }
        .clear-btn:hover {
            background: #d0d0d0;
            color: #333;
        }
        .loading-indicator {
            display: flex;
            align-items: center;
            gap: 10px;
            color: #666;
            font-size: 14px;
        }
        .spinner {
            width: 20px;
            height: 20px;
            border: 3px solid #f3f3f3;
            border-top: 3px solid #0066cc;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        .nav-link {
            color: #0066cc;
            text-decoration: none;
            font-weight: 500;
        }
        .nav-link:hover {
            text-decoration: underline;
        }
        .family-id-nav {
            font-size: 18px;
            font-weight: bold;
            color: #333;
        }
        .family-content {
            background: #fefdf8;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            font-size: 16px;
            white-space: pre-wrap;
        }
        .section-header {
            font-size: 18px;
            font-weight: bold;
            margin-top: 20px;
            margin-bottom: 10px;
            color: #333;
        }
        .person-link, .date-link, .family-link {
            color: #0066cc;
            text-decoration: underline;
            cursor: pointer;
        }
        .person-link:hover, .date-link:hover, .family-link:hover {
            color: #0052a3;
            text-decoration: underline;
        }
        .person-link:focus, .date-link:focus, .family-link:focus {
            outline: 2px solid #0066cc;
            outline-offset: 2px;
        }
        .enhanced {
            color: #8b4513;
        }
        .symbol {
            color: #333;
        }
        .citation-panel {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .citation-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        .citation-title {
            font-size: 18px;
            font-weight: bold;
            color: #333;
        }
        .citation-textarea {
            width: 100%;
            min-height: 200px;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 14px;
            resize: vertical;
            background: #f9f9f9;
        }
        .citation-textarea:focus {
            outline: none;
            border-color: #0066cc;
            background: white;
        }
        .copy-button {
            background: #0066cc;
            color: white;
            border: none;
            padding: 8px 16px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
        }
        .copy-button:hover {
            background: #0052a3;
        }
        .copy-hint {
            margin-top: 10px;
            padding: 8px 12px;
            background: #e7f3ff;
            border: 1px solid #b3d9ff;
            border-radius: 4px;
            color: #0066cc;
            font-size: 13px;
        }
        .error-panel {
            background: #fee;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            border: 1px solid #fcc;
        }
        .error-title {
            font-size: 18px;
            font-weight: bold;
            color: #dc3545;
            margin-bottom: 10px;
        }
        .error-message {
            color: #721c24;
        }
        .source-panel {
            background: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .source-header {
            margin-bottom: 15px;
        }
        .source-title {
            font-size: 16px;
            font-weight: bold;
            color: #333;
        }
        .source-text {
            width: 100%;
            padding: 15px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', monospace;
            font-size: 13px;
            background: #f9f9f9;
            white-space: pre-wrap;
            overflow-x: auto;
            line-height: 1.5;
            color: #333;
        }
        """
    }

    // MARK: - JavaScript

    private static var copyButtonScript: String {
        return """
        <script>
        function copyCitation() {
            const textarea = document.getElementById('citationText');
            const hint = document.getElementById('copyHint');

            if (textarea) {
                textarea.focus();
                textarea.select();
                hint.style.display = 'block';

                setTimeout(() => {
                    hint.style.display = 'none';
                }, 3000);
            }
        }
        </script>
        """
    }
    
    private static var navigationScript: String {
        return """
        <script>
        // Show/hide clear button based on input content
        const familyInput = document.getElementById('familyInput');
        const clearBtn = document.querySelector('.clear-btn');
        
        if (familyInput && clearBtn) {
            // Initial state
            clearBtn.style.display = familyInput.value ? 'flex' : 'none';
            
            // Update on input
            familyInput.addEventListener('input', function() {
                clearBtn.style.display = this.value ? 'flex' : 'none';
            });
        }
        
        // Clear input function
        function clearInput() {
            const input = document.getElementById('familyInput');
            if (input) {
                input.value = '';
                input.focus();
                const clearBtn = document.querySelector('.clear-btn');
                if (clearBtn) {
                    clearBtn.style.display = 'none';
                }
            }
        }
        
        // Show loading indicator
        function showLoading(event) {
            const input = document.getElementById('familyInput');
            const form = document.querySelector('.nav-form');
            const loadingIndicator = document.getElementById('loadingIndicator');
            const loadingText = document.getElementById('loadingText');
            
            if (input && loadingIndicator && loadingText) {
                const familyId = input.value.trim().toUpperCase();
                loadingText.textContent = 'Loading ' + familyId + '...';
                form.style.display = 'none';
                loadingIndicator.style.display = 'flex';
            }
        }
        
        // Show loading when clicking navigation buttons
        document.querySelectorAll('.nav-btn:not(.disabled)').forEach(btn => {
            btn.addEventListener('click', function(e) {
                const href = this.getAttribute('href');
                if (href && href !== '#' && !this.classList.contains('disabled')) {
                    const form = document.querySelector('.nav-form');
                    const loadingIndicator = document.getElementById('loadingIndicator');
                    const loadingText = document.getElementById('loadingText');
                    
                    if (loadingIndicator && loadingText) {
                        // Extract family ID from href
                        const match = href.match(/\\/family\\/([^?]+)/);
                        if (match) {
                            const familyId = decodeURIComponent(match[1]);
                            loadingText.textContent = 'Loading ' + familyId + '...';
                        } else {
                            loadingText.textContent = 'Loading...';
                        }
                        if (form) form.style.display = 'none';
                        loadingIndicator.style.display = 'flex';
                    }
                }
            });
        });
        </script>
        """
    }

    // MARK: - Helper Functions

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    
    private static func urlEncode(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? string
    }

    private static func buildQueryParams(_ params: [String: String?]) -> String {
        var components: [String] = []
        for (key, value) in params {
            if let value = value, !value.isEmpty {
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                components.append("\(encodedKey)=\(encodedValue)")
            }
        }
        return components.joined(separator: "&")
    }
}

#endif // os(macOS)
