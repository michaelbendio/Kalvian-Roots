import App
import Vapor
import Logging

var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)

let logger = Logger(label: "kalvianroots.main")
logger.info("🔧 KalvianRootsServer starting… environment: \(env.name)")

let app = Application(env)
defer {
    logger.info("🛑 KalvianRootsServer shutting down…")
    app.shutdown()
}

try configure(app)

logger.info("✅ Configuration complete. Listening on \(app.http.server.configuration.hostname):\(app.http.server.configuration.port)")

try app.run()
