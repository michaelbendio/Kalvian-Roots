//
//  MLXServerManager_Fixed.swift
//  Kalvian Roots
//
//  Fixed version with proper health check and only 3 models
//

import Foundation
import Combine

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
    
    // MARK: - Model Configuration (ONLY 3 MODELS)
    
    struct MLXModel {
        let name: String
        let displayName: String
        let path: String
        
        static let allModels: [MLXModel] = [
            MLXModel(
                name: "qwen3-30b",
                displayName: "Qwen3-30B",
                path: "Qwen3-30B-A3B-4bit"
            ),
            MLXModel(
                name: "qwen2.5-14b",
                displayName: "Qwen2.5-14B",
                path: "Qwen2.5-14B-Instruct"
            ),
            MLXModel(
                name: "llama-3.1-8b",
                displayName: "Llama-3.1-8B",
                path: "Llama-3.1-8B-Instruct"
            )
        ]
        
        static func model(named name: String) -> MLXModel? {
            return allModels.first { $0.name == name }
        }
    }
    
    // MARK: - Initialization

    init() {
        logInfo(.ai, "🎛️ MLXServerManager initialized")

        // Check platform compatibility
        if !isPlatformCompatible() {
            logError(.ai, "⚠️ MLX is only supported on Apple Silicon Macs (M1/M2/M3/M4)")
            serverStatus = .error("MLX requires Apple Silicon Mac")
            return
        }

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
        // Check platform compatibility first
        guard isPlatformCompatible() else {
            let error = MLXError.unsupportedPlatform
            serverStatus = .error(error.localizedDescription)
            throw error
        }

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
        
        // Wait for server to be ready (with longer timeout for large models)
        let timeout = modelName.contains("30b") ? 180 : 120 // 3 minutes for 30B, 2 minutes for others
        await waitUntilReady(modelDisplayName: model.displayName, timeout: timeout)
        
        // Check final status
        if case .error = serverStatus {
            // Timeout occurred, but check one more time
            if await checkServerHealth() {
                serverStatus = .ready(model: model.displayName)
                logInfo(.ai, "✅ MLX server ready (after timeout)")
            }
        } else {
            serverStatus = .ready(model: model.displayName)
            logInfo(.ai, "✅ MLX server ready with \(model.displayName)")
        }
        
        // Execute any queued operations
        if let onReady = onServerReady {
            await onReady()
            onServerReady = nil
        }
    }
    
    /**
     * Stop the MLX server
     */
    func stopServer() {
        guard let process = serverProcess else { return }
        
        logInfo(.ai, "🛑 Stopping MLX server")
        process.terminate()
        serverProcess = nil
        currentModel = nil
        serverStatus = .stopped
    }
    
    // MARK: - Queue Management
    
    /**
     * Queue a family extraction while server is starting
     */
    func queueExtraction(_ familyId: String) {
        guard !serverStatus.isReady else {
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
    
    /**
     * Check if a server is already running
     */
    func checkExistingServer() async {
        if await checkServerHealth() {
            // Server is already running
            if let lastModel = UserDefaults.standard.string(forKey: lastModelKey),
               let model = MLXModel.model(named: lastModel) {
                currentModel = lastModel
                serverStatus = .ready(model: model.displayName)
                logInfo(.ai, "✅ Found existing MLX server running with \(model.displayName)")
            } else {
                serverStatus = .ready(model: "Unknown Model")
                logInfo(.ai, "✅ Found existing MLX server running")
            }
        }
    }
    
    /**
     * Get recommended default model based on system memory
     */
    func getDefaultModel() -> String {
        // Check for saved preference
        if let lastModel = UserDefaults.standard.string(forKey: lastModelKey),
           MLXModel.model(named: lastModel) != nil {
            logInfo(.ai, "📖 Using last selected model: \(lastModel)")
            return lastModel
        }
        
        // Default based on memory
        let memory = getSystemMemory() / (1024 * 1024 * 1024) // Convert to GB
        
        if memory >= 48 {
            logInfo(.ai, "🎯 Using default model: qwen3-30b (48GB+ RAM)")
            return "qwen3-30b"
        } else if memory >= 24 {
            logInfo(.ai, "🎯 Using default model: qwen2.5-14b (24-48GB RAM)")
            return "qwen2.5-14b"
        } else {
            logInfo(.ai, "🎯 Using default model: llama-3.1-8b (<24GB RAM)")
            return "llama-3.1-8b"
        }
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
     * Check if server is responding (FIXED VERSION)
     */
    func checkServerHealth() async -> Bool {
        // Try a simple OPTIONS or HEAD request first
        do {
            guard let url = URL(string: "\(baseURL)/") else { return false }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.httpMethod = "HEAD"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                // Any response means server is running
                logDebug(.ai, "✅ MLX server health check: HTTP \(httpResponse.statusCode)")
                return httpResponse.statusCode > 0
            }
        } catch {
            // Try a POST request with minimal body
            do {
                guard let url = URL(string: "\(baseURL)/v1/chat/completions") else { return false }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 5.0
                
                // Minimal valid request body
                let body: [String: Any] = [
                    "model": "test",
                    "messages": [],
                    "max_tokens": 1
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    // Even error responses mean server is running
                    logDebug(.ai, "✅ MLX server responding: HTTP \(httpResponse.statusCode)")
                    return true
                }
            } catch {
                logTrace(.ai, "❌ MLX server not responding: \(error.localizedDescription)")
            }
        }
        
        return false
    }
    
    // MARK: - Private Helpers
    
    private func launchMLXServer(modelPath: String, modelName: String) throws {
        // Verify model path exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: modelPath) {
            let error = MLXError.modelNotFound(modelPath)
            logError(.ai, "❌ Model not found at: \(modelPath)")
            throw error
        }

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
    
    private func waitUntilReady(modelDisplayName: String, timeout: Int = 120) async {
        let delayNanoseconds: UInt64 = 2_000_000_000 // 2 seconds between checks

        // Check if process is still running
        guard let process = serverProcess, process.isRunning else {
            serverStatus = .error("Server process failed to start. Check if mlx_lm is installed (pip3 install mlx-lm)")
            logError(.ai, "❌ MLX server process not running. Is mlx_lm installed?")
            return
        }

        for attempt in stride(from: 2, through: timeout, by: 2) {
            // Check if process died
            if let process = serverProcess, !process.isRunning {
                serverStatus = .error("Server process terminated unexpectedly. Check if mlx_lm is installed.")
                logError(.ai, "❌ MLX server process died. Exit code: \(process.terminationStatus)")
                return
            }

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
        serverStatus = .error("Server startup timeout after \(timeout) seconds. Check logs for errors.")
        logError(.ai, "❌ MLX server startup timeout after \(timeout) seconds")
    }
    
    private func expandPath(_ path: String) -> String {
        return NSString(string: path).expandingTildeInPath
    }
    
    private func getSystemMemory() -> UInt64 {
        #if os(macOS)
        var size = MemoryLayout<UInt64>.size
        var memSize: UInt64 = 0
        sysctlbyname("hw.memsize", &memSize, &size, nil, 0)
        return memSize
        #else
        return 0
        #endif
    }

    /**
     * Check if the current platform supports MLX
     * MLX requires Apple Silicon (ARM64) on macOS
     */
    private func isPlatformCompatible() -> Bool {
        #if os(macOS) && arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - MLX Errors

enum MLXError: LocalizedError {
    case invalidModel(String)
    case serverNotRunning
    case startupFailed(String)
    case unsupportedPlatform
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel(let name):
            return "Invalid MLX model: \(name)"
        case .serverNotRunning:
            return "MLX server is not running"
        case .startupFailed(let reason):
            return "MLX server startup failed: \(reason)"
        case .unsupportedPlatform:
            return "MLX is only supported on Apple Silicon Macs (M1/M2/M3/M4). Current platform is not compatible."
        case .modelNotFound(let path):
            return "Model not found at path: \(path). Please download models to ~/.kalvian_roots_mlx/models/"
        }
    }
}
