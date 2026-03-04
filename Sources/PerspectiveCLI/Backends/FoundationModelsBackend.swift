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

    /// Initialize or reinitialize the FM session.
    /// When `enableTools` is true, tools and tool-usage instructions are included.
    func initialize(customPrompt: String? = nil, enableTools: Bool = false) {
        var instructions = Self.systemInstructions
        if enableTools {
            instructions += "\n\n" + Self.toolInstructions
        }
        if let customPrompt, !customPrompt.isEmpty {
            instructions = customPrompt + "\n\n" + instructions
        }
        if enableTools {
            let tools = ToolRegistry.shared.allTools()
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: instructions
            )
        } else {
            session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: instructions
            )
        }
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
