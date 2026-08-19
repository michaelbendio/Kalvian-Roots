import Foundation
import KalvianRootsMCPServer
import MCP

@main
struct KalvianRootsMCPMain {
  static func main() async {
    let server = await KalvianRootsMCPServerFactory().makeServer()
    let transport = StdioTransport()

    do {
      try await server.start(transport: transport)
      await server.waitUntilCompleted()
      await server.stop()
    } catch {
      let message = "KalvianRootsMCP failed: \(error.localizedDescription)\n"
      FileHandle.standardError.write(Data(message.utf8))
      await server.stop()
      Foundation.exit(EXIT_FAILURE)
    }
  }
}
