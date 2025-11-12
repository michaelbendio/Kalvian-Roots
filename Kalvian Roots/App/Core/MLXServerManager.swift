//
//  MLXServerManager.swift
//  Kalvian Roots
//
//  Manages MLX server lifecycle with auto-start, queuing, and model persistence
//

import Foundation

/**
 * MLX Server Manager
 *
 * Handles automatic startup, shutdown, and health monitoring of MLX server
 * Queues extractions while server is starting
 * Persists last used model as default
 */
class MLXServerManager: ObservableObject {
    
    // MARK: - Server Status
    
    enum ServerStatus: Equatable {
        case stopped
        case starting(model: String)
        case ready(model: String)
        case error(String)
        
        var description: String {
            switch self {
            case .stopped:
                return "MLX Server: Stopped"
            case .starting(let model):
                return "MLX Server: Starting \(model)..."
            case .ready(let model):
                return "MLX Server: Ready (\(model))"
            case .error(let message):
                return "MLX Server: Error - \(message)"
            }
        }
        
        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }
    
    // MARK: - Published State
    
    @Published var serverStatus: ServerStatus = .stopped
    @Published var currentModel: String?
    @Published var queuedExtractions: [String] = []
    
    // Callback for when server becomes ready
    var onServerReady: (() async -> Void)?
    
    // MARK: - Private State
    
    private var serverProcess: Process?
    private let baseURL = "http://127.0.0.1:8080"
    private let modelsBasePath = "~/.kalvian_roots_mlx/models"
    private let lastModelKey = "MLXServerManager_LastModel"
    
    // MARK: - Model Configuration
    
    struct MLXModel {
        let name: String
        let displayName: String
        let path: String
        
        static let allModels: [MLXModel] = [
            MLXModel(
                name: "phi-3.5-mini",
                displayName: "Phi-3.5-mini",
                path: "Phi-3.5-mini-instruct"
            ),
            MLXModel(
                name: "qwen2.5-14b",
                displayName: "Qwen2.5-14B",
                path: "Qwen2.5-14B-Instruct"
            ),
            MLXModel(
                name: "qwen3-30b",
                displayName: "Qwen3-30B",
                path: "Qwen3-30B-A3B-4bit"
            ),
            MLXModel(
                name: "llama-3.1-8b",
                displayName: "Llama-3.1-8B",
                path: "Llama-3.1-8B-Instruct"
            ),
            MLXModel(
                name: "mistral-7b",
                displayName: "Mistral-7B",
                path: "Mistral-7B-Instruct-4bit"
            )
        ]
        
        static func model(named name: String) -> MLXModel? {
            return allModels.first { $0.name == name }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        logInfo(.ai, "🎛️ MLXServerManager initialized")
        
        // Check if there's a server already running
        Task {
            await checkExistingServer()
        }
    }
    
    deinit {
        // Stop server synchronously in deinit
        serverProcess?.terminate()
        serverProcess = nil
    }
    
    // MARK: - Server Lifecycle
    
    /**
     * Start MLX server with specified model
     * Auto-starts in background, queues extractions until ready
     */
    func startServer(modelName: String) async throws {
        guard let model = MLXModel.model(named: modelName) else {
            throw MLXError.invalidModel(modelName)
        }
        
        logInfo(.ai, "🚀 Starting MLX server with model: \(model.displayName)")
        
        // Update status
        serverStatus = .starting(model: model.displayName)
        currentModel = modelName
        
        // Save as last used model
        UserDefaults.standard.set(modelName, forKey: lastModelKey)
        
        // Stop any existing server
        stopServer()
        
        // Build full model path
        let modelPath = expandPath("\(modelsBasePath)/\(model.path)")
        
        // Launch server process
        do {
            try launchMLXServer(modelPath: modelPath, modelName: model.displayName)
        } catch {
            serverStatus = .error("Failed to start: \(error.localizedDescription)")
            throw error
        }
        
        // Wait for server to be ready (non-blocking)
        await waitUntilReady(modelDisplayName: model.displayName)
        
        // Update status to ready
        serverStatus = .ready(model: model.displayName)
        logInfo(.ai, "✅ MLX server ready: \(model.displayName)")
        
        // Notify that server is ready
        if let callback = onServerReady {
            await callback()
        }
    }
    
    /**
     * Stop MLX server
     */
    func stopServer() {
        guard let process = serverProcess else { return }
        
        logInfo(.ai, "🛑 Stopping MLX server")
        
        process.terminate()
        
        // Give it a moment to shut down gracefully
        sleep(1)
        
        // Force kill if still running
        if process.isRunning {
            process.interrupt()
        }
        
        serverProcess = nil
        serverStatus = .stopped
        currentModel = nil
        
        logInfo(.ai, "✅ MLX server stopped")
    }
    
    /**
     * Restart server with same model
     */
    func restartServer() async throws {
        guard let modelName = currentModel else {
            throw MLXError.noModelSelected
        }
        
        try await startServer(modelName: modelName)
    }
    
    // MARK: - Queue Management
    
    /**
     * Queue a family extraction while server is starting
     */
    func queueExtraction(_ familyId: String) {
        guard !serverStatus.isReady else {
            // Server is ready, no need to queue
            return
        }
        
        if !queuedExtractions.contains(familyId) {
            queuedExtractions.append(familyId)
            logInfo(.ai, "📋 Queued extraction: \(familyId) (queue size: \(queuedExtractions.count))")
        }
    }
    
    /**
     * Clear extraction queue
     */
    func clearQueue() {
        queuedExtractions.removeAll()
        logInfo(.ai, "🗑️ Extraction queue cleared")
    }
    
    // MARK: - Model Selection
    
    /**
     * Get last used model or recommended default
     */
    func getDefaultModel() -> String {
        // Check for saved preference
        if let lastModel = UserDefaults.standard.string(forKey: lastModelKey),
           MLXModel.model(named: lastModel) != nil {
            logInfo(.ai, "📖 Using last selected model: \(lastModel)")
            return lastModel
        }
        
        // Default to Phi-3.5-mini for fastest startup
        logInfo(.ai, "🎯 Using default model: phi-3.5-mini")
        return "phi-3.5-mini"
    }
    
    /**
     * Switch to a different model
     */
    func switchModel(to modelName: String) async throws {
        guard MLXModel.model(named: modelName) != nil else {
            throw MLXError.invalidModel(modelName)
        }
        
        // If already using this model, do nothing
        if currentModel == modelName && serverStatus.isReady {
            logInfo(.ai, "ℹ️ Already using model: \(modelName)")
            return
        }
        
        // Start server with new model
        try await startServer(modelName: modelName)
    }
    
    // MARK: - Server Health
    
    /**
     * Check if server is responding
     */
    func checkServerHealth() async -> Bool {
        let endpointsToTest = [
            "/v1/chat/completions",
            "/generate",
            "/health"
        ]
        
        for endpoint in endpointsToTest {
            do {
                guard let url = URL(string: "\(baseURL)\(endpoint)") else { continue }
                
                var request = URLRequest(url: url)
                request.timeoutInterval = 2.0
                request.httpMethod = "GET"
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode < 500 {
                    return true
                }
            } catch {
                continue
            }
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func launchMLXServer(modelPath: String, modelName: String) throws {
        let process = Process()
        
        // Use python3 explicitly
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-m", "mlx_lm.server",
            "--model", modelPath,
            "--port", "8080"
        ]
        
        // Set up environment
        process.environment = ProcessInfo.processInfo.environment
        
        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Log output in background
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                logTrace(.ai, "MLX: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                logDebug(.ai, "MLX error: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        // Launch
        try process.run()
        serverProcess = process
        
        logInfo(.ai, "🔧 MLX server process launched (PID: \(process.processIdentifier))")
    }
    
    private func waitUntilReady(modelDisplayName: String) async {
        let maxAttempts = 60 // 60 seconds max
        let delayNanoseconds: UInt64 = 1_000_000_000 // 1 second
        
        for attempt in 1...maxAttempts {
            // Check if server is responding
            if await checkServerHealth() {
                logInfo(.ai, "✅ Server ready after \(attempt) seconds")
                return
            }
            
            // Update status with progress
            serverStatus = .starting(model: "\(modelDisplayName) (\(attempt)s)")
            
            // Wait before next check
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        
        // Timeout
        serverStatus = .error("Server failed to start within 60 seconds")
        logError(.ai, "❌ MLX server failed to start within timeout")
    }
    
    private func checkExistingServer() async {
        if await checkServerHealth() {
            // Server is already running, try to determine which model
            serverStatus = .ready(model: "Unknown Model")
            logInfo(.ai, "ℹ️ Found existing MLX server running")
            
            // Notify callback if server was already ready
            if let callback = onServerReady {
                await callback()
            }
        }
    }
    
    private func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            return path.replacingOccurrences(of: "~", with: homeDir)
        }
        return path
    }
}

// MARK: - Errors

enum MLXError: LocalizedError {
    case invalidModel(String)
    case noModelSelected
    case serverNotRunning
    
    var errorDescription: String? {
        switch self {
        case .invalidModel(let name):
            return "Invalid model: \(name)"
        case .noModelSelected:
            return "No model selected"
        case .serverNotRunning:
            return "MLX server is not running"
        }
    }
}
