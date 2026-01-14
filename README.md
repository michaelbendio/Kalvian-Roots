# Kalvian Roots

A SwiftUI app for parsing Finnish genealogical records ("Juuret Kälviällä") using local MLX models on Apple Silicon or cloud AI providers. Includes a browser-based interface for remote family access via Tailscale.

## Quick start
- Open `Kalvian Roots.xcodeproj` in Xcode (macOS recommended)
- Add SwiftNIO dependency (see `SWIFT_NIO_SETUP.md` for instructions)
- Run the app
- Open your file `JuuretKälviällä.roots` (use the Open File button in the UI)
- Enter a family ID (e.g., `KORPI 6`) and extract

## Browser Interface (macOS only)

The app includes an HTTP server for browser-based access to family data, designed for remote family members to access via Tailscale.

### Features
- Server-rendered HTML (no JavaScript framework required)
- Clickable elements for navigation:
  - Person names generate citations
  - Dates trigger HisKi queries
  - Family IDs navigate between families
- Citation panel with copy functionality
- Automatic HisKi citation extraction

### Setup
1. Install Tailscale on your Mac and remote devices
2. The HTTP server starts automatically when the app launches
3. Access via: `http://[your-tailscale-ip]:8080`
4. The server binds to all interfaces (0.0.0.0:8080)

### Usage
- Landing page: Enter a family ID to view
- Family display: Click on any person, date, or family ID
- Citations: Click person names to generate citations
- HisKi queries: Click dates to search church records
- Copy citations: Use the Copy button and press Cmd+C/Ctrl+C

### Security
- Designed for Tailscale network access only
- No built-in authentication (Tailscale provides network-level security)
- Do not expose to public internet

## AI services
- Local: MLX models (Apple Silicon). Ensure your MLX server is running at `http://127.0.0.1:8080`
- Cloud: OpenAI, Claude, DeepSeek, and Ollama (local server)
- Configure API keys in the in-app AI Settings screen (stored locally for personal use)

## Documentation
- See `Docs/Architecture.md` for architecture and data flow

## Targets
- macOS app primary; iOS builds may require wrapping macOS-only features (e.g., `NSOpenPanel`) with `#if os(macOS)`

## License
Personal research project.
