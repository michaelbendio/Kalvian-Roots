//
//  DebugLogger.swift
//  Kalvian Roots
//
//  Comprehensive debug logging system for genealogical parsing
//

import Foundation

/**
 * Multi-level debug logging system for tracing AI parsing and cross-reference resolution
 *
 * Levels:
 * - ERROR: Critical failures only
 * - WARN: Potential issues and fallbacks
 * - INFO: Major milestones and user actions
 * - DEBUG: Detailed workflow and API calls
 * - TRACE: Extremely detailed - every step
 */

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
    case file = "FILE"
    case citation = "CITE"
    case ui = "UI"
    case network = "NET"
    
    var emoji: String {
        switch self {
        case .app: return "🚀"
        case .ai: return "🤖"
        case .parsing: return "📝"
        case .crossRef: return "🔗"
        case .file: return "📁"
        case .citation: return "📄"
        case .ui: return "🖥️"
        case .network: return "🌐"
        }
    }
}

/**
 * Centralized debug logging with configurable levels and categories
 */
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
    
    // MARK: - Specialized Logging
    
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
        debug(.parsing, "Father: \(family.father.displayName)")
        debug(.parsing, "Mother: \(family.mother?.displayName ?? "nil")")
        debug(.parsing, "Children: \(family.children.count)")
        debug(.parsing, "Cross-references needed: \(family.totalCrossReferencesNeeded)")
    }
    
    func logParsingFailure(_ error: Error, familyId: String) {
        self.error(.parsing, "❌ Parsing failed for \(familyId): \(error.localizedDescription)")
    }
    
    func logCrossRefSearch(_ personName: String, birthDate: String?, searchType: String) {
        info(.crossRef, "Cross-reference search: \(personName) (\(searchType))")
        debug(.crossRef, "Birth date: \(birthDate ?? "unknown")")
    }
    
    func logCrossRefResult(_ personName: String, foundFamilies: [String], confidence: Double?) {
        debug(.crossRef, "Found \(foundFamilies.count) candidates for \(personName)")
        if let confidence = confidence {
            debug(.crossRef, "Best match confidence: \(String(format: "%.2f", confidence))")
        }
        trace(.crossRef, "Candidate families: \(foundFamilies.joined(separator: ", "))")
    }
    
    func logFileOperation(_ operation: String, fileName: String, success: Bool) {
        if success {
            info(.file, "✅ \(operation): \(fileName)")
        } else {
            warn(.file, "❌ \(operation) failed: \(fileName)")
        }
    }
    
    func logUserAction(_ action: String, details: String = "") {
        info(.ui, "User action: \(action)")
        if !details.isEmpty {
            debug(.ui, "Details: \(details)")
        }
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
    
    // MARK: - Data Inspection
    
    func logDataStructure<T>(_ data: T, name: String) {
        trace(.parsing, "Data structure '\(name)':")
        trace(.parsing, "\(String(describing: data))")
    }
    
    func logFamilyValidation(_ family: Family, warnings: [String]) {
        if warnings.isEmpty {
            debug(.parsing, "✅ Family \(family.familyId) validation passed")
        } else {
            warn(.parsing, "⚠️ Family \(family.familyId) validation warnings:")
            for warning in warnings {
                warn(.parsing, "  - \(warning)")
            }
        }
    }
    
    // MARK: - Statistics
    
    func getCurrentSettings() -> (level: LogLevel, categories: Set<LogCategory>) {
        return (currentLevel, enabledCategories)
    }
}

// MARK: - Convenience Extensions

extension DebugLogger {
    // Quick access methods for common patterns
    
    func aiCall(_ service: String, _ action: String) {
        debug(.ai, "🔄 \(service): \(action)")
    }
    
    func parseStep(_ step: String, _ details: String = "") {
        debug(.parsing, "📝 Parse step: \(step)")
        if !details.isEmpty {
            trace(.parsing, "   \(details)")
        }
    }
    
    func crossRefStep(_ step: String, _ person: String) {
        debug(.crossRef, "🔗 \(step): \(person)")
    }
    
    func fileStep(_ step: String, _ file: String) {
        debug(.file, "📁 \(step): \(file)")
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
