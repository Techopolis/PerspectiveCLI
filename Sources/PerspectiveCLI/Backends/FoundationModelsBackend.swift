// FoundationModelsBackend.swift
// PerspectiveCLI
//
// Foundation Models backend using Apple's on-device language model.
// Requires macOS 26+ with Apple Silicon.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import FoundationModels

/// Foundation Models backend — uses Apple's on-device LanguageModelSession
/// with native tool calling support.
actor FoundationModelsBackend {
    private var session: LanguageModelSession?
    private let conversation = CLIConversation()
    private var streamingEnabled = true
    private var temperature: Double = 0.7
    private var generationOptions: GenerationOptions { GenerationOptions(temperature: temperature) }
    private var adapterURL: URL?

    // MARK: - Initialization

    /// Check if Foundation Models are available on this device.
    static func checkAvailability() -> (available: Bool, message: String) {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return (true, "Foundation Models available")
        case .unavailable(let reason):
            return (false, "Foundation Models unavailable: \(reason)")
        @unknown default:
            return (false, "Unknown availability status")
        }
    }

    /// Detailed availability status for the /status command.
    static func detailedAvailability() -> (available: Bool, reason: String) {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return (true, "Ready")
        case .unavailable(let reason):
            let detail: String
            switch reason {
            case .deviceNotEligible:
                detail = "Device not eligible (requires Apple Silicon with Apple Intelligence support)"
            case .appleIntelligenceNotEnabled:
                detail = "Apple Intelligence is not enabled (enable in Settings > Apple Intelligence & Siri)"
            case .modelNotReady:
                detail = "Model assets are not ready (still downloading or not yet installed)"
            @unknown default:
                detail = "Unknown reason"
            }
            return (false, detail)
        @unknown default:
            return (false, "Unknown availability status")
        }
    }

    /// Initialize or reinitialize the FM session.
    /// When `enableTools` is true, tools and tool-usage instructions are included.
    func initialize(customPrompt: String? = nil, enableTools: Bool = false) throws {
        var instructions = Self.systemInstructions
        if enableTools {
            instructions += "\n\n" + Self.toolInstructions
        }
        if let customPrompt, !customPrompt.isEmpty {
            instructions = customPrompt + "\n\n" + instructions
        }

        let model: SystemLanguageModel
        if let adapterURL {
            let adapter = try SystemLanguageModel.Adapter(fileURL: adapterURL)
            model = SystemLanguageModel(adapter: adapter)
        } else {
            model = SystemLanguageModel.default
        }

        if enableTools {
            let tools = ToolRegistry.shared.allTools()
            session = LanguageModelSession(
                model: model,
                tools: tools,
                instructions: instructions
            )
        } else {
            session = LanguageModelSession(
                model: model,
                instructions: instructions
            )
        }
    }

    // MARK: - Adapter Management

    /// Load an adapter from a .fmadapter file path.
    func loadAdapter(from path: String) throws {
        // Strip shell escape backslashes and quotes, then expand ~
        let cleaned = path
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let expanded = NSString(string: cleaned).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError.adapterNotFound(expanded)
        }
        adapterURL = url
    }

    /// Clear the currently loaded adapter.
    func clearAdapter() {
        adapterURL = nil
    }

    /// Returns the path of the currently loaded adapter, if any.
    func currentAdapterPath() -> String? {
        adapterURL?.path
    }

    /// Returns the built-in default system prompt.
    static func defaultSystemPrompt() -> String {
        return systemInstructions
    }

    // MARK: - Messaging

    /// Send a message and get a complete response (with tool calling handled automatically).
    func sendMessage(_ message: String) async throws -> String {
        guard let session else {
            throw CLIError.sessionNotInitialized
        }

        conversation.addUserMessage(message)
        let response = try await session.respond(to: message, options: generationOptions)
        let text = response.content
        conversation.addAssistantMessage(text)
        return text
    }

    /// Stream a message response token-by-token.
    /// Each yielded string is the accumulated text so far (delta from previous).
    func streamMessage(_ message: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let session else {
            throw CLIError.sessionNotInitialized
        }

        conversation.addUserMessage(message)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var fullResponse = ""
                    let stream = session.streamResponse(to: message, options: self.generationOptions)
                    for try await partial in stream {
                        let text = partial.content
                        continuation.yield(text)
                        fullResponse = text
                    }
                    self.conversation.addAssistantMessage(fullResponse)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Configuration

    func isStreaming() -> Bool { streamingEnabled }
    func setStreaming(_ enabled: Bool) { streamingEnabled = enabled }
    func toggleStreaming() -> Bool {
        streamingEnabled.toggle()
        return streamingEnabled
    }

    func setTemperature(_ value: Float) {
        temperature = Double(value)
    }

    func getTemperature() -> Float {
        return Float(temperature)
    }

    // MARK: - Session Management

    func resetSession() {
        session = nil
        conversation.clearMessages()
    }

    // MARK: - System Instructions

    private static let systemInstructions = "You are a helpful assistant."

    private static let toolInstructions = """
        IMPORTANT: Only use tools when the user's request SPECIFICALLY requires \
        real-time or external data that you cannot answer from general knowledge. \
        For example, use the weather tool ONLY when the user explicitly asks about \
        current weather or forecast for a location.

        Do NOT use tools for general knowledge questions, definitions, explanations, \
        opinions, coding help, math, history, science, or any question you can \
        answer directly. When in doubt, answer directly without tools.
        """
}
