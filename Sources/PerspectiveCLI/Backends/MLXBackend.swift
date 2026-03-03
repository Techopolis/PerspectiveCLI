// MLXBackend.swift
// PerspectiveCLI
//
// MLX backend using mlx-swift for on-device model inference.
// Downloads models from HuggingFace on first use.
//
// Copyright (c) 2026 Michael Doise
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import MLXLLM
import MLXVLM
import MLXLMCommon

/// MLX backend — uses mlx-swift for running open-weight models locally.
/// Models are downloaded from HuggingFace on first use and cached.
actor MLXBackend {
    private var container: ModelContainer?
    private var session: ChatSession?
    private var modelId: String = "mlx-community/gemma-3-1b-it-qat-4bit"
    private let conversation = CLIConversation()

    // MARK: - Configuration

    func setModelId(_ id: String) {
        modelId = id
    }

    func getModelId() -> String {
        return modelId
    }

    // MARK: - Initialization

    /// Initialize the MLX model container. Downloads model on first use.
    func initialize(customPrompt: String? = nil) async throws {
        printInfo("Loading MLX model: \(modelId)")
        printInfo("(First run will download the model from HuggingFace...)")

        let container = try await loadModelContainer(id: modelId) { progress in
            if progress.fractionCompleted < 1.0 {
                let pct = Int(progress.fractionCompleted * 100)
                print("\r\u{001B}[90m  Downloading: \(pct)%\u{001B}[0m", terminator: "")
                fflush(stdout)
            } else {
                print("\r\u{001B}[90m  Download complete.          \u{001B}[0m")
            }
        }
        self.container = container

        // TODO: Re-enable MLX tool calling once small models handle it reliably
        var instructions = Self.systemInstructions
        if let customPrompt, !customPrompt.isEmpty {
            instructions = customPrompt + "\n\n" + instructions
        }

        self.session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(temperature: 0.7)
        )
    }

    /// Returns the built-in default system prompt.
    static func defaultSystemPrompt() -> String {
        return systemInstructions
    }

    private static let systemInstructions = "You are a helpful assistant."

    // MARK: - Messaging

    /// Stream a message response token-by-token.
    func streamMessage(_ message: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let session else {
            throw CLIError.sessionNotInitialized
        }

        conversation.addUserMessage(message)

        // ChatSession.streamResponse returns AsyncThrowingStream<String, Error> directly
        let stream = session.streamResponse(to: message)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var fullResponse = ""
                    for try await chunk in stream {
                        fullResponse += chunk
                        continuation.yield(fullResponse)
                    }

                    // TODO: Re-enable MLX tool call parsing once small models handle it reliably
                    self.conversation.addAssistantMessage(fullResponse)

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // TODO: Re-enable MLX tool calling. Needs:
    // - Tool description injection into system prompt (ToolRegistry.shared.mlxToolDescriptions())
    // - handleToolCall() parser for ```tool_call``` JSON blocks
    // - Follow-up streaming to feed tool results back to the model
    // Disabled because small models (gemma-3-1b) hallucinate tool calls on general questions.

    // MARK: - Session Management

    func resetSession() {
        container = nil
        session = nil
        conversation.clearMessages()
    }
}
