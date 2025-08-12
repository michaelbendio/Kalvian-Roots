# Kalvian Roots

A SwiftUI app for parsing Finnish genealogical records ("Juuret Kälviällä") using local MLX models on Apple Silicon or cloud AI providers.

## Quick start
- Open `Kalvian Roots.xcodeproj` in Xcode (macOS recommended)
- Run the app
- Open your file `JuuretKälviällä.roots` (use the Open File button in the UI)
- Enter a family ID (e.g., `KORPI 6`) and extract

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
