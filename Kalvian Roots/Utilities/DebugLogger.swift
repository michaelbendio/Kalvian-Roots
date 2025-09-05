//
//  DebugLogger.swift
//  Kalvian Roots
//
//

import Foundation

// MARK: - LogLevel and LogCategory

enum LogLevel: Int, CaseIterable {
    case error = 0
    case warn = 1
    case info = 2
    case debug = 3
    case trace = 4
    
    var prefix: String {
        switch self {
        case .error: return "❌ ERROR"
        case .warn:  return "⚠️ WARN "
        case .info:  return "ℹ️ INFO "
        case .debug: return "🔍 DEBUG"
        case .trace: return "📍 TRACE"
        }
    }
    
    var description: String {
        switch self {
        case .error: return "Errors Only"
        case .warn:  return "Warnings+"
        case .info:  return "Info+"
        case .debug: return "Debug+"
        case .trace: return "All Tracing"
        }
    }
}

enum LogCategory: String, CaseIterable {
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
    
    var emoji: String {
        switch self {
        case .app: return "🚀"
        case .ai: return "🤖"
        case .parsing: return "📝"
        case .crossRef: return "🔗"
        case .resolver: return "🔍"
        case .file: return "📁"
        case .citation: return "📄"
        case .ui: return "🖥️"
        case .network: return "🌐"
        case .nameEquivalence: return "🔤"
        case .workflow: return "🔄"
        case .cache: return "💾"
        }
    }
}

// MARK: - DebugLogger Class

class DebugLogger {
    static let shared = DebugLogger()
    
    private var currentLevel: LogLevel = .debug
    private var enabledCategories: Set<LogCategory> = Set(LogCategory.allCases)
    private var startTime = Date()
    
    private init() {
        // Load settings from UserDefaults
        if let savedLevel = UserDefaults.standard.object(forKey: "DebugLogLevel") as? Int,
           let level = LogLevel(rawValue: savedLevel) {
            currentLevel = level
        }
        
        if let savedCategories = UserDefaults.standard.array(forKey: "DebugLogCategories") as? [String] {
            enabledCategories = Set(savedCategories.compactMap { LogCategory(rawValue: $0) })
        }
        
        info(.app, "DebugLogger initialized - Level: \(currentLevel.description)")
    }
    
    // MARK: - Configuration
    
    func setLevel(_ level: LogLevel) {
        currentLevel = level
        UserDefaults.standard.set(level.rawValue, forKey: "DebugLogLevel")
        info(.app, "Debug level changed to: \(level.description)")
    }
    
    func enableCategory(_ category: LogCategory) {
        enabledCategories.insert(category)
        saveCategories()
    }
    
    func disableCategory(_ category: LogCategory) {
        enabledCategories.remove(category)
        saveCategories()
    }
    
    func enableAllCategories() {
        enabledCategories = Set(LogCategory.allCases)
        saveCategories()
    }
    
    private func saveCategories() {
        let categoryStrings = enabledCategories.map { $0.rawValue }
        UserDefaults.standard.set(categoryStrings, forKey: "DebugLogCategories")
    }
    
    // MARK: - Logging Methods
    
    func error(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.error, category, message, file: file, line: line)
    }
    
    func warn(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.warn, category, message, file: file, line: line)
    }
    
    func info(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.info, category, message, file: file, line: line)
    }
    
    func debug(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.debug, category, message, file: file, line: line)
    }
    
    func trace(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
        log(.trace, category, message, file: file, line: line)
    }
    
    private func log(_ level: LogLevel, _ category: LogCategory, _ message: String, file: String, line: Int) {
        // Check if this level and category should be logged
        guard level.rawValue <= currentLevel.rawValue else { return }
        guard enabledCategories.contains(category) else { return }
        
        let timestamp = String(format: "%.3f", Date().timeIntervalSince(startTime))
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let location = "\(fileName):\(line)"
        
        let logMessage = "[\(timestamp)s] \(level.prefix) \(category.emoji) \(category.rawValue) | \(message) | \(location)"
        print(logMessage)
    }
    
    // MARK: - Specialized Logging Methods
    
    func logAIRequest(_ service: String, prompt: String) {
        debug(.ai, "AI Request to \(service)")
        trace(.ai, "Prompt preview: \(String(prompt.prefix(200)))...")
    }
    
    func logAIResponse(_ service: String, response: String, duration: TimeInterval) {
        debug(.ai, "AI Response from \(service) (took \(String(format: "%.2f", duration))s)")
        trace(.ai, "Response preview: \(String(response.prefix(200)))...")
        trace(.ai, "Full response length: \(response.count) characters")
    }
    
    func logParsingAttempt(_ familyId: String, textLength: Int) {
        info(.parsing, "Starting struct parsing for \(familyId)")
        debug(.parsing, "Family text length: \(textLength) characters")
    }
    
    func logParsingSuccess(_ family: Family) {
        info(.parsing, "✅ Successfully parsed family: \(family.familyId)")
        
        if let father = family.father {
            debug(.parsing, "Father: \(father.displayName)")
        } else {
            debug(.parsing, "Father: nil")
        }
        
        if let mother = family.mother {
            debug(.parsing, "Mother: \(mother.displayName)")
        } else {
            debug(.parsing, "Mother: nil")
        }
        
        debug(.parsing, "Children: \(family.children.count)")
        
        let parentsWithRefs = family.allParents.filter { $0.asChild != nil }.count
        let childrenWithRefs = family.children.filter { $0.asParent != nil }.count
        let totalRefs = parentsWithRefs + childrenWithRefs
        
        debug(.parsing, "Cross-references to resolve: \(totalRefs) (parents: \(parentsWithRefs), children: \(childrenWithRefs))")
    }
    
    func logParsingFailure(_ error: Error, familyId: String) {
        self.error(.parsing, "❌ Parsing failed for \(familyId): \(error.localizedDescription)")
    }
    
    // MARK: - Performance Timing
    
    private var timers: [String: Date] = [:]
    
    func startTimer(_ name: String) {
        timers[name] = Date()
        trace(.app, "⏱️ Started timer: \(name)")
    }
    
    func endTimer(_ name: String) -> TimeInterval {
        guard let startTime = timers[name] else {
            warn(.app, "Timer '\(name)' not found")
            return 0
        }
        
        let duration = Date().timeIntervalSince(startTime)
        timers.removeValue(forKey: name)
        debug(.app, "⏱️ Timer \(name): \(String(format: "%.3f", duration))s")
        return duration
    }
    
    // MARK: - Convenience Methods
    
    func parseStep(_ step: String, _ details: String = "") {
        debug(.parsing, "📝 Parse step: \(step)")
        if !details.isEmpty {
            trace(.parsing, "   \(details)")
        }
    }
    
}

// MARK: - Global Convenience Functions

func logError(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.error(category, message, file: file, line: line)
}

func logWarn(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.warn(category, message, file: file, line: line)
}

func logInfo(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.info(category, message, file: file, line: line)
}

func logDebug(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.debug(category, message, file: file, line: line)
}

func logTrace(_ category: LogCategory, _ message: String, file: String = #file, line: Int = #line) {
    DebugLogger.shared.trace(category, message, file: file, line: line)
}
