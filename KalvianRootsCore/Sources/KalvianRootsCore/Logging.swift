import Foundation

public enum LogLevel: Int, CaseIterable {
    case error = 0
    case warn = 1
    case info = 2
    case debug = 3
    case trace = 4

    var prefix: String {
        switch self {
        case .error: return "❌ ERROR"
        case .warn: return "⚠️ WARN "
        case .info: return "ℹ️ INFO "
        case .debug: return "🔍 DEBUG"
        case .trace: return "📍 TRACE"
        }
    }
}

public enum LogCategory: String, CaseIterable {
    case app = "APP"
    case ai = "AI"
    case parsing = "PARSE"
    case crossRef = "XREF"
    case resolver = "RESOLVER"
    case file = "FILE"
    case citation = "CITE"
    case ui = "UI"
    case network = "NET"
    case nameEquivalence = "NAME_EQ"
    case workflow = "WORKFLOW"
    case cache = "CACHE"
}

public final class DebugLogger {
    public static let shared = DebugLogger()

    private var currentLevel: LogLevel = .info
    private var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    private let startTime = Date()
    private var timers: [String: Date] = [:]

    private init() {}

    private func log(_ level: LogLevel, _ category: LogCategory, _ message: String, file: String, line: Int) {
        guard level.rawValue <= currentLevel.rawValue else { return }
        guard enabledCategories.contains(category) else { return }

        let timestamp = String(format: "%.3f", Date().timeIntervalSince(startTime))
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let location = "\(fileName):\(line)"
        let logMessage = "[\(timestamp)s] \(level.prefix) \(category.rawValue) | \(message) | \(location)"
        print(logMessage)
    }

    public func setLevel(_ level: LogLevel) {
        currentLevel = level
    }

    public func enableCategory(_ category: LogCategory) {
        enabledCategories.insert(category)
    }

    public func disableCategory(_ category: LogCategory) {
        enabledCategories.remove(category)
    }

    public func startTimer(_ name: String) {
        timers[name] = Date()
    }

    public func endTimer(_ name: String) -> TimeInterval {
        guard let start = timers[name] else { return 0 }
        let duration = Date().timeIntervalSince(start)
        timers.removeValue(forKey: name)
        return duration
    }

    public func error(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.error, category, message, file: file, line: line)
    }

    public func warn(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.warn, category, message, file: file, line: line)
    }

    public func info(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.info, category, message, file: file, line: line)
    }

    public func debug(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.debug, category, message, file: file, line: line)
    }

    public func trace(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.trace, category, message, file: file, line: line)
    }
}

public func logError(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.error(category, message, file: file, line: line)
}

public func logWarn(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.warn(category, message, file: file, line: line)
}

public func logInfo(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.info(category, message, file: file, line: line)
}

public func logDebug(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.debug(category, message, file: file, line: line)
}

public func logTrace(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.trace(category, message, file: file, line: line)
}
