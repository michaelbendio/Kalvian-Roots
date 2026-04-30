# Kalvian Roots

A SwiftUI app for comparing Finnish genealogical records from Juuret Kälviällä,
FamilySearch, and HisKi. The app parses Juuret family text with DeepSeek,
converts all sources into a shared comparison model, and proposes citations for
manual user approval.

## Quick start
- Open `Kalvian Roots.xcodeproj` in Xcode
- Run the app
- Put `JuuretKälviällä.roots` in local Documents, or select it with the Open File button
- Configure the DeepSeek API key in AI Settings
- Enter a family ID (e.g., `KORPI 6`) and extract

SwiftNIO and SwiftLog are already configured as Xcode package dependencies.

If you use Xcode beta outside `/Applications/Xcode.app`, either select it in
Xcode's Locations settings or run command-line builds with:

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" xcodebuild test -project "Kalvian Roots.xcodeproj" -scheme "Kalvian Roots"
```

## Browser Interface (macOS only)

The app includes an HTTP server for browser-based access to family data,
designed for remote family members to access via Tailscale.

### Features
- Server-rendered HTML (no JavaScript framework required)
- Clickable elements for navigation:
  - Person names generate citations
  - Dates trigger HisKi queries
  - Family IDs navigate between families
- Citation panel with copy functionality
- Automatic HisKi citation extraction
- FamilySearch extraction callback support for the bookmarklet workflow

### Setup
1. Install Tailscale on your Mac and remote devices
2. The HTTP server starts automatically when the app launches
3. Access via: `http://[your-tailscale-ip]:8080`
4. The server binds to all interfaces (0.0.0.0:8080)
5. FamilySearch extraction callbacks post to `http://127.0.0.1:8081`

### Usage
- Landing page: Enter a family ID to view
- Family display: Click on any person, date, or family ID
- Citations: Click person names to generate citations
- HisKi queries: Click dates to search church records
- Copy citations: Use the Copy button and press Cmd+C/Ctrl+C
- FamilySearch: Use the bookmarklet workflow documented in `Docs/familysearch-bookmarklet.md`

### Security
- Designed for Tailscale network access only
- No built-in authentication (Tailscale provides network-level security)
- Do not expose to public internet

## AI services
- Current implementation: hosted DeepSeek only
- Configure the API key in the in-app AI Settings screen
- API keys are stored locally for personal use

## Documentation
- See `Docs/Architecture.md` for architecture and data flow
- See `Docs/implementation-plan.md` for the staged implementation plan and current status
- See `Docs/familysearch-bookmarklet.md` for the current FamilySearch extraction workflow
- See `development.md` for current build, test, and development workflow

## Targets
- macOS app primary; iOS builds may require wrapping macOS-only features (e.g., `NSOpenPanel`) with `#if os(macOS)`

## License
Personal research project.
