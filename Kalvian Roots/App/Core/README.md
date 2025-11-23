// Kalvian Roots

// Kalvian Roots is a genealogical research app focused on extracting and organizing family data from historical Finnish sources. It combines local AI (MLX on Apple Silicon) and cloud services to parse families and generate citations.

// Server Direction (Browser UI)
// We are moving toward a browser-based UI backed by a Vapor server, with in-memory jobs and family locks (no database initially). The detailed plan, endpoints, and phases are documented here:

// - docs/ServerScaffold.md

// Current Status
// - macOS app implementation in progress (local MLX support; cloud services available)
// - iOS-specific code removed/disabled in this branch to focus on macOS + server
// - Debug facilities available for MLX requests/responses (see MLXService)

// Key Decisions (Summary)
// - Framework: Vapor (async/await routes)
// - Exposure: Optional Cloudflare Tunnel; MLX remains on 127.0.0.1:8080
// - UI: SPA served from Vapor Public/ (or later Cloudflare Pages)
// - Auth: Bearer token on all /api (KALVIAN_API_TOKEN)
// - Jobs: In-memory job store (actor)
// - Locks: In-memory family locks (lease-based; TTL ~120–180s; heartbeat ~30–45s)
// - DB: Not yet (swap-in repository later)
// - Hiski: Server-side fetch + HTML parse; return { url, recordId, citation? }

// Environment (planned for server)
// - KALVIAN_API_TOKEN=...
// - ROOTS_FILE=/path/to/JuuretKälviällä.roots

// Phased Roadmap
// 1) Skeleton (health, status, static SPA)
// 2) Extraction + SSE
// 3) Citations + Hiski
// 4) Family Locks (in-memory)
// 5) Hardening (CORS/cache headers/Cloudflare Tunnel)

// See docs/ServerScaffold.md for the full plan.

## Tasks (Planning Only — do not start Phase 1 yet)
- [ ] Confirm environment values and secrets management
  - `KALVIAN_API_TOKEN` for API auth
  - `ROOTS_FILE` absolute path for headless file loading
- [ ] Decide SPA hosting for first iteration
  - Serve from Vapor `Public/` (simplest) OR host on Cloudflare Pages (requires CORS)
- [ ] Lock policy confirmation
  - TTL: 120–180s (default 120s)
  - Heartbeat: 30–45s (default 30s)
  - Header for guarded routes: `X-Lock-Lease: <UUID>`
- [ ] Progress transport
  - Prefer SSE with 25s heartbeat; allow polling fallback
- [ ] Error shape
  - Use a simple JSON envelope: `{ "error": { "code": "string", "message": "string" } }`
- [ ] Core services audit for server safety
  - Identify any `@MainActor` usage to remove/guard on server path
  - Ensure MLX remains on `127.0.0.1:8080`
- [ ] In-memory stores design notes
  - `InMemoryJobStore` (actor): job states, result JSON, timestamps
  - `InMemoryLockStore` (actor): leaseId, owner, purpose, expiresAt
- [ ] Security checklist
  - Token middleware for all `/api/*`
  - Optional Cloudflare Tunnel later; keep origin on `127.0.0.1:8081`
- [ ] Logging & correlation
  - Add `X-Request-Id` generation and include in logs and responses

## Contributing / Notes
// - Keep architectural decisions and endpoint changes updated in docs/ServerScaffold.md so the plan remains canonical even if chat history is truncated.
// - MLX logs can be toggled in Debug builds via `MLXService.debugLoggingEnabled = true`.

